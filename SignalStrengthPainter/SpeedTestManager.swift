import Foundation

enum SpeedTestPhase: Equatable {
    case idle
    case selectingServer
    case latency
    case download
    case upload
    case complete
}

/// Metadata about the speed-test server that was actually selected/used for
/// a run. This is surfaced in the UI so the user can verify that the test
/// is hitting a geographically sensible endpoint — the #1 cause of
/// surprisingly-low scores is not the Wi-Fi but an ISP whose routing sends
/// the traffic to a far-away Cloudflare POP (e.g. a user in Arizona whose
/// Anycast route lands in LAX or DFW instead of PHX).
struct SpeedTestServerInfo: Equatable {
    /// Human-friendly provider name (always "Cloudflare" today).
    let providerName: String
    /// IATA-style 3-letter colo code returned by Cloudflare, e.g. "PHX".
    let coloCode: String?
    /// Friendly city for that colo when known, e.g. "Phoenix, AZ".
    let coloCity: String?
    /// Latitude/longitude of the colo (for distance display).
    let coloLatitude: Double?
    let coloLongitude: Double?
    /// Client's geolocated city/region/country as seen by Cloudflare.
    let clientCity: String?
    let clientRegion: String?
    let clientCountry: String?
    let clientLatitude: Double?
    let clientLongitude: Double?
    /// Client's ISP (ASN organization). Useful for diagnosing routing.
    let clientISP: String?
    let clientASN: Int?
    /// Warmup round-trip time to the chosen server's /meta endpoint, in ms.
    let warmupLatencyMs: Double?
    /// Great-circle distance client → colo in miles, when both coords known.
    let distanceMiles: Double?

    /// Short display line, e.g. "Cloudflare PHX · Phoenix, AZ".
    var displayLine: String {
        var parts: [String] = [providerName]
        if let code = coloCode {
            parts.append(code)
        }
        var line = parts.joined(separator: " ")
        if let city = coloCity {
            line += " · \(city)"
        }
        return line
    }

    /// "~12 mi away" string when distance is known, else nil.
    var distanceText: String? {
        guard let miles = distanceMiles else { return nil }
        if miles < 1 { return "<1 mi away" }
        return "~\(Int(miles.rounded())) mi away"
    }

    /// True if the chosen POP is suspiciously far from the client — likely
    /// an ISP routing issue. Threshold tuned to flag cross-region hops
    /// (e.g. AZ → DFW ≈ 890 mi) while not flagging same-region jumps
    /// (AZ → LAX ≈ 370 mi is common and acceptable).
    var isLikelySuboptimal: Bool {
        guard let d = distanceMiles else { return false }
        return d > 500
    }
}

@MainActor
final class SpeedTestManager: ObservableObject {
    @Published var phase: SpeedTestPhase = .idle
    @Published var currentSpeed: Double = 0
    @Published var downloadSpeed: Double = 0
    @Published var uploadSpeed: Double = 0
    @Published var pingMs: Double = 0
    @Published var jitterMs: Double = 0
    @Published var progress: Double = 0
    @Published var speedSamples: [Double] = []
    @Published var isTesting = false
    @Published var testDate: Date?
    /// Info about the server actually used for the last (or in-progress) run.
    /// Persists across test runs so the completed card can keep showing it.
    @Published var serverInfo: SpeedTestServerInfo?

    private var testTask: Task<Void, Never>?
    private let phaseDuration: TimeInterval = 12
    private let sampleIntervalNs: UInt64 = 250_000_000

    func startTest() {
        guard !isTesting else { return }
        resetResults()
        isTesting = true
        testDate = Date()

        testTask = Task {
            await runServerSelectionPhase()
            guard !Task.isCancelled else { return cleanup() }
            await runLatencyPhase()
            guard !Task.isCancelled else { return cleanup() }
            await runDownloadPhase()
            guard !Task.isCancelled else { return cleanup() }
            await runUploadPhase()
            phase = .complete
            isTesting = false
            publishCompletedRunToKlaus()
        }
    }

    /// Push the freshly-finished test results into `KlausContextHub`
    /// so the chat assistant can speak to "your last Speed Test was X
    /// down / Y up" without rerunning the test itself. Called once per
    /// completed run from inside the test task.
    private func publishCompletedRunToKlaus() {
        let info = serverInfo
        let download = downloadSpeed
        let upload = uploadSpeed
        let ping = pingMs
        let jitter = jitterMs
        let date = testDate
        KlausContextHub.shared.update { ctx in
            ctx.lastDownloadMbps = download
            ctx.lastUploadMbps = upload
            ctx.lastSpeedPingMs = ping
            ctx.lastSpeedJitterMs = jitter
            ctx.lastSpeedTestAt = date
            ctx.ispOrganization = info?.clientISP
            ctx.serverColo = info?.coloCode
            ctx.serverCity = info?.coloCity
            ctx.distanceMiles = info?.distanceMiles
            ctx.isLikelySuboptimalRoute = info?.isLikelySuboptimal ?? false
        }
    }

    func cancelTest() {
        testTask?.cancel()
        testTask = nil
        cleanup()
    }

    private func cleanup() {
        isTesting = false
        phase = .idle
    }

    private func resetResults() {
        phase = .idle
        currentSpeed = 0
        downloadSpeed = 0
        uploadSpeed = 0
        pingMs = 0
        jitterMs = 0
        progress = 0
        speedSamples = []
        // NOTE: intentionally keep serverInfo from the prior run so the UI
        // doesn't flicker. It gets overwritten once the new selection runs.
    }

    // MARK: - Server Selection Phase

    /// Picks which speed-test endpoint to use for this run by warmup-pinging
    /// a small set of candidates and fetching Cloudflare's /meta endpoint
    /// for geolocation/colo info. Today all candidates point at Cloudflare
    /// (Anycast picks a POP automatically) but the warmup confirms the
    /// routing is healthy and exposes the chosen colo to the user.
    private func runServerSelectionPhase() async {
        phase = .selectingServer
        progress = 0

        // Parallel: fetch /meta (for colo + client geo) and warmup-ping
        // a couple of candidate endpoints to confirm routing works. Both
        // run with tight timeouts so a slow/no network doesn't block the
        // main test phases.
        async let metaResult: CloudflareMeta? = fetchCloudflareMeta()
        async let warmupMs: Double? = warmupLatency(to: "https://speed.cloudflare.com/__down?bytes=0")

        let meta = await metaResult
        let warmup = await warmupMs

        // Resolve colo → city/lat/lng via the static lookup.
        let coloCode = meta?.colo
        let coloDetails = coloCode.flatMap { CloudflareColoDirectory.details(for: $0) }

        // Compute client → colo great-circle distance when both are known.
        var distanceMiles: Double?
        if let clientLat = meta?.latitude,
           let clientLng = meta?.longitude,
           let cLat = coloDetails?.latitude,
           let cLng = coloDetails?.longitude {
            distanceMiles = haversineMiles(
                lat1: clientLat, lng1: clientLng,
                lat2: cLat, lng2: cLng
            )
        }

        serverInfo = SpeedTestServerInfo(
            providerName: "Cloudflare",
            coloCode: coloCode,
            coloCity: coloDetails?.city,
            coloLatitude: coloDetails?.latitude,
            coloLongitude: coloDetails?.longitude,
            clientCity: meta?.city,
            clientRegion: meta?.region,
            clientCountry: meta?.country,
            clientLatitude: meta?.latitude,
            clientLongitude: meta?.longitude,
            clientISP: meta?.asOrganization,
            clientASN: meta?.asn,
            warmupLatencyMs: warmup,
            distanceMiles: distanceMiles
        )

        progress = 1.0 / 4.0
    }

    /// Cloudflare's /meta endpoint returns client geo + the colo handling
    /// the request. Parsed via JSONSerialization to avoid a dedicated
    /// Codable type and to be lenient about field presence. Capped at a
    /// short timeout so offline runs don't stall the test.
    private func fetchCloudflareMeta() async -> CloudflareMeta? {
        guard let url = URL(string: "https://speed.cloudflare.com/meta") else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 3

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            // All fields optional — Cloudflare occasionally omits any of
            // them (e.g. for IP ranges without a good geoip record).
            let colo = (obj["colo"] as? String).map { $0.uppercased() }
            let city = obj["city"] as? String
            let region = obj["region"] as? String
            let country = obj["country"] as? String
            let asn: Int? = {
                if let n = obj["asn"] as? Int { return n }
                if let s = obj["asn"] as? String, let n = Int(s) { return n }
                return nil
            }()
            let org = obj["asOrganization"] as? String
            // lat/lng are returned as strings in Cloudflare's /meta.
            let lat: Double? = {
                if let s = obj["latitude"] as? String { return Double(s) }
                if let d = obj["latitude"] as? Double { return d }
                return nil
            }()
            let lng: Double? = {
                if let s = obj["longitude"] as? String { return Double(s) }
                if let d = obj["longitude"] as? Double { return d }
                return nil
            }()

            return CloudflareMeta(
                colo: colo,
                city: city,
                region: region,
                country: country,
                asn: asn,
                asOrganization: org,
                latitude: lat,
                longitude: lng
            )
        } catch {
            return nil
        }
    }

    private func warmupLatency(to urlString: String) async -> Double? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 3
        let start = CFAbsoluteTimeGetCurrent()
        do {
            _ = try await URLSession.shared.data(for: request)
            return (CFAbsoluteTimeGetCurrent() - start) * 1000
        } catch {
            return nil
        }
    }

    // MARK: - Latency Phase

    private func runLatencyPhase() async {
        phase = .latency
        var pings: [Double] = []

        for i in 0..<10 {
            guard !Task.isCancelled else { return }
            if let ms = await singleHTTPPing() {
                pings.append(ms)
            }
            // Previous progress base was 0, span was 1/3. We've now
            // reserved 0..1/4 for server selection, so latency runs
            // from 1/4 → 1/2.
            progress = 1.0 / 4.0 + (Double(i + 1) / 10.0) * (1.0 / 4.0)
            try? await Task.sleep(nanoseconds: 150_000_000)
        }

        guard !pings.isEmpty else { return }
        let sorted = pings.sorted()
        let trimmed = sorted.count > 4 ? Array(sorted.dropFirst().dropLast()) : sorted
        pingMs = trimmed.reduce(0, +) / Double(trimmed.count)

        if pings.count > 1 {
            var diffs: [Double] = []
            for i in 1..<pings.count {
                diffs.append(abs(pings[i] - pings[i - 1]))
            }
            jitterMs = diffs.reduce(0, +) / Double(diffs.count)
        }
    }

    private func singleHTTPPing() async -> Double? {
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=0") else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let _ = try await URLSession.shared.data(for: request)
            return (CFAbsoluteTimeGetCurrent() - start) * 1000
        } catch {
            return nil
        }
    }

    // MARK: - Download Phase

    private func runDownloadPhase() async {
        phase = .download
        speedSamples = []
        currentSpeed = 0

        let counter = TransferCounter()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 15
        config.httpMaximumConnectionsPerHost = 16
        let session = URLSession(configuration: config)

        let phaseStart = CFAbsoluteTimeGetCurrent()
        let duration = phaseDuration

        let streams = Task.detached {
            await withTaskGroup(of: Void.self) { group in
                for streamId in 0..<8 {
                    group.addTask {
                        var iteration = 0
                        while !Task.isCancelled {
                            if CFAbsoluteTimeGetCurrent() - phaseStart >= duration { break }

                            let size = 4_000_000
                            let bust = "\(streamId).\(iteration).\(UInt64.random(in: 0...UInt64.max))"
                            guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(size)&cachebust=\(bust)") else { break }
                            var req = URLRequest(url: url)
                            req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                            req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

                            do {
                                let (data, response) = try await session.data(for: req)
                                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                                    counter.add(Int64(data.count))
                                }
                            } catch {
                                if Task.isCancelled { break }
                                try? await Task.sleep(nanoseconds: 200_000_000)
                            }
                            iteration += 1
                        }
                    }
                }
            }
        }

        let samples = await sampleTransferPhase(
            counter: counter,
            phaseStart: phaseStart,
            progressBase: 2.0 / 4.0,
            progressSpan: 1.0 / 4.0
        )

        streams.cancel()
        session.invalidateAndCancel()

        let totalTime = CFAbsoluteTimeGetCurrent() - phaseStart
        if totalTime > 0 && counter.total > 0 {
            downloadSpeed = Double(counter.total) * 8.0 / (totalTime * 1_000_000.0)
        } else if !samples.isEmpty {
            downloadSpeed = samples.reduce(0, +) / Double(samples.count)
        }
    }

    // MARK: - Upload Phase

    private func runUploadPhase() async {
        phase = .upload
        speedSamples = []
        currentSpeed = 0

        let counter = TransferCounter()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 15
        config.httpMaximumConnectionsPerHost = 16
        let session = URLSession(configuration: config)

        let chunkSize = 4_000_000
        let payload = Data(count: chunkSize)
        let phaseStart = CFAbsoluteTimeGetCurrent()
        let duration = phaseDuration

        let streams = Task.detached {
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<8 {
                    group.addTask {
                        while !Task.isCancelled {
                            if CFAbsoluteTimeGetCurrent() - phaseStart >= duration { break }

                            guard let url = URL(string: "https://speed.cloudflare.com/__up") else { break }
                            var req = URLRequest(url: url)
                            req.httpMethod = "POST"
                            req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                            req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

                            do {
                                let (_, response) = try await session.upload(for: req, from: payload)
                                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                                    counter.add(Int64(chunkSize))
                                }
                            } catch {
                                if Task.isCancelled { break }
                                try? await Task.sleep(nanoseconds: 200_000_000)
                            }
                        }
                    }
                }
            }
        }

        let samples = await sampleTransferPhase(
            counter: counter,
            phaseStart: phaseStart,
            progressBase: 3.0 / 4.0,
            progressSpan: 1.0 / 4.0
        )

        streams.cancel()
        session.invalidateAndCancel()

        let totalTime = CFAbsoluteTimeGetCurrent() - phaseStart
        if totalTime > 0 && counter.total > 0 {
            uploadSpeed = Double(counter.total) * 8.0 / (totalTime * 1_000_000.0)
        } else if !samples.isEmpty {
            uploadSpeed = samples.reduce(0, +) / Double(samples.count)
        }
    }

    // MARK: - Shared Sampling Loop

    private func sampleTransferPhase(
        counter: TransferCounter,
        phaseStart: CFAbsoluteTime,
        progressBase: Double,
        progressSpan: Double
    ) async -> [Double] {
        var lastSampleTime = phaseStart
        var lastSampleBytes: Int64 = 0
        var samples: [Double] = []

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: sampleIntervalNs)
            let now = CFAbsoluteTimeGetCurrent()
            let elapsed = now - phaseStart
            let totalBytes = counter.total
            let sampleDuration = now - lastSampleTime
            let sampleBytes = totalBytes - lastSampleBytes

            if elapsed > 1.0 && sampleDuration > 0.05 {
                let instantMbps = Double(sampleBytes) * 8.0 / (sampleDuration * 1_000_000.0)
                samples.append(instantMbps)
                speedSamples = samples

                let window = samples.suffix(4)
                currentSpeed = window.reduce(0, +) / Double(window.count)
            }

            lastSampleTime = now
            lastSampleBytes = totalBytes
            progress = progressBase + min(elapsed / phaseDuration, 1.0) * progressSpan

            if elapsed >= phaseDuration { break }
        }

        return samples
    }
}

// MARK: - TransferCounter (thread-safe byte counter)

final class TransferCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _total: Int64 = 0

    var total: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return _total
    }

    func add(_ bytes: Int64) {
        lock.lock()
        _total += bytes
        lock.unlock()
    }
}

// MARK: - Cloudflare /meta parsing

private struct CloudflareMeta {
    let colo: String?
    let city: String?
    let region: String?
    let country: String?
    let asn: Int?
    let asOrganization: String?
    let latitude: Double?
    let longitude: Double?
}

// MARK: - Cloudflare Colo Directory

/// Static lookup of Cloudflare POP (colo) codes to a friendly city name and
/// approximate coordinates. Cloudflare publicly documents its POPs at
/// https://www.cloudflare.com/network/ — the codes here cover the North
/// American POPs plus the busiest global ones most likely to show up for
/// app users. When a user lands in an unknown colo we fall back to
/// showing just the 3-letter code.
enum CloudflareColoDirectory {
    struct Details {
        let city: String
        let latitude: Double
        let longitude: Double
    }

    static func details(for coloCode: String) -> Details? {
        return directory[coloCode.uppercased()]
    }

    // Coordinates are the IATA airport coordinates associated with each
    // code. Rounded to 4 decimals (≈11 m of precision, plenty for a
    // human-facing "~N mi away" label).
    private static let directory: [String: Details] = [
        // US — West
        "LAX": Details(city: "Los Angeles, CA", latitude: 33.9416, longitude: -118.4085),
        "SFO": Details(city: "San Francisco, CA", latitude: 37.6213, longitude: -122.3790),
        "SJC": Details(city: "San Jose, CA", latitude: 37.3639, longitude: -121.9289),
        "SAN": Details(city: "San Diego, CA", latitude: 32.7338, longitude: -117.1933),
        "SEA": Details(city: "Seattle, WA", latitude: 47.4502, longitude: -122.3088),
        "PDX": Details(city: "Portland, OR", latitude: 45.5898, longitude: -122.5951),
        "PHX": Details(city: "Phoenix, AZ", latitude: 33.4343, longitude: -112.0080),
        "LAS": Details(city: "Las Vegas, NV", latitude: 36.0840, longitude: -115.1537),
        "SLC": Details(city: "Salt Lake City, UT", latitude: 40.7899, longitude: -111.9791),
        "DEN": Details(city: "Denver, CO", latitude: 39.8561, longitude: -104.6737),
        "ABQ": Details(city: "Albuquerque, NM", latitude: 35.0402, longitude: -106.6089),
        "ANC": Details(city: "Anchorage, AK", latitude: 61.1744, longitude: -149.9964),
        "HNL": Details(city: "Honolulu, HI", latitude: 21.3245, longitude: -157.9251),
        // US — Central
        "DFW": Details(city: "Dallas, TX", latitude: 32.8998, longitude: -97.0403),
        "IAH": Details(city: "Houston, TX", latitude: 29.9902, longitude: -95.3368),
        "AUS": Details(city: "Austin, TX", latitude: 30.1945, longitude: -97.6699),
        "SAT": Details(city: "San Antonio, TX", latitude: 29.5337, longitude: -98.4698),
        "OKC": Details(city: "Oklahoma City, OK", latitude: 35.3931, longitude: -97.6007),
        "MCI": Details(city: "Kansas City, MO", latitude: 39.2976, longitude: -94.7139),
        "OMA": Details(city: "Omaha, NE", latitude: 41.3032, longitude: -95.8940),
        "STL": Details(city: "St. Louis, MO", latitude: 38.7487, longitude: -90.3700),
        "MSY": Details(city: "New Orleans, LA", latitude: 29.9934, longitude: -90.2580),
        "MEM": Details(city: "Memphis, TN", latitude: 35.0421, longitude: -89.9792),
        "BNA": Details(city: "Nashville, TN", latitude: 36.1263, longitude: -86.6774),
        "MSP": Details(city: "Minneapolis, MN", latitude: 44.8848, longitude: -93.2223),
        "ORD": Details(city: "Chicago, IL", latitude: 41.9742, longitude: -87.9073),
        "IND": Details(city: "Indianapolis, IN", latitude: 39.7173, longitude: -86.2944),
        "CMH": Details(city: "Columbus, OH", latitude: 39.9980, longitude: -82.8919),
        "CVG": Details(city: "Cincinnati, OH", latitude: 39.0489, longitude: -84.6678),
        "DTW": Details(city: "Detroit, MI", latitude: 42.2162, longitude: -83.3554),
        // US — East / Southeast
        "ATL": Details(city: "Atlanta, GA", latitude: 33.6407, longitude: -84.4277),
        "CLT": Details(city: "Charlotte, NC", latitude: 35.2140, longitude: -80.9431),
        "RDU": Details(city: "Raleigh, NC", latitude: 35.8776, longitude: -78.7875),
        "MIA": Details(city: "Miami, FL", latitude: 25.7959, longitude: -80.2870),
        "MCO": Details(city: "Orlando, FL", latitude: 28.4312, longitude: -81.3081),
        "TPA": Details(city: "Tampa, FL", latitude: 27.9755, longitude: -82.5332),
        "JAX": Details(city: "Jacksonville, FL", latitude: 30.4941, longitude: -81.6879),
        "BHM": Details(city: "Birmingham, AL", latitude: 33.5629, longitude: -86.7535),
        // US — Northeast / Mid-Atlantic
        "IAD": Details(city: "Ashburn, VA", latitude: 38.9531, longitude: -77.4565),
        "DCA": Details(city: "Washington, DC", latitude: 38.8512, longitude: -77.0402),
        "BWI": Details(city: "Baltimore, MD", latitude: 39.1754, longitude: -76.6684),
        "PHL": Details(city: "Philadelphia, PA", latitude: 39.8744, longitude: -75.2424),
        "PIT": Details(city: "Pittsburgh, PA", latitude: 40.4915, longitude: -80.2329),
        "EWR": Details(city: "Newark, NJ", latitude: 40.6895, longitude: -74.1745),
        "JFK": Details(city: "New York, NY", latitude: 40.6413, longitude: -73.7781),
        "LGA": Details(city: "New York, NY (LGA)", latitude: 40.7769, longitude: -73.8740),
        "BUF": Details(city: "Buffalo, NY", latitude: 42.9397, longitude: -78.7322),
        "BOS": Details(city: "Boston, MA", latitude: 42.3656, longitude: -71.0096),
        "RIC": Details(city: "Richmond, VA", latitude: 37.5052, longitude: -77.3197),
        // Canada
        "YYZ": Details(city: "Toronto, ON", latitude: 43.6777, longitude: -79.6248),
        "YUL": Details(city: "Montréal, QC", latitude: 45.4706, longitude: -73.7408),
        "YVR": Details(city: "Vancouver, BC", latitude: 49.1967, longitude: -123.1815),
        "YYC": Details(city: "Calgary, AB", latitude: 51.1215, longitude: -114.0076),
        "YEG": Details(city: "Edmonton, AB", latitude: 53.3097, longitude: -113.5801),
        "YHZ": Details(city: "Halifax, NS", latitude: 44.8808, longitude: -63.5086),
        "YOW": Details(city: "Ottawa, ON", latitude: 45.3225, longitude: -75.6692),
        "YWG": Details(city: "Winnipeg, MB", latitude: 49.9100, longitude: -97.2399),
        // Mexico / Central America
        "MEX": Details(city: "Mexico City", latitude: 19.4361, longitude: -99.0719),
        "QRO": Details(city: "Querétaro", latitude: 20.6173, longitude: -100.1856),
        "GDL": Details(city: "Guadalajara", latitude: 20.5218, longitude: -103.3110),
        "MTY": Details(city: "Monterrey", latitude: 25.7785, longitude: -100.1077),
        "PTY": Details(city: "Panama City", latitude: 9.0714, longitude: -79.3835),
        // Europe (most-hit for US users on VPN; kept small)
        "LHR": Details(city: "London, UK", latitude: 51.4700, longitude: -0.4543),
        "AMS": Details(city: "Amsterdam, NL", latitude: 52.3086, longitude: 4.7639),
        "FRA": Details(city: "Frankfurt, DE", latitude: 50.0379, longitude: 8.5622),
        "CDG": Details(city: "Paris, FR", latitude: 49.0097, longitude: 2.5479),
        "MAD": Details(city: "Madrid, ES", latitude: 40.4983, longitude: -3.5676),
        "MXP": Details(city: "Milan, IT", latitude: 45.6306, longitude: 8.7281),
        "DUB": Details(city: "Dublin, IE", latitude: 53.4213, longitude: -6.2701),
        "ARN": Details(city: "Stockholm, SE", latitude: 59.6498, longitude: 17.9237),
        // Asia / Pacific (subset)
        "NRT": Details(city: "Tokyo, JP", latitude: 35.7720, longitude: 140.3929),
        "HND": Details(city: "Tokyo, JP (HND)", latitude: 35.5494, longitude: 139.7798),
        "ICN": Details(city: "Seoul, KR", latitude: 37.4602, longitude: 126.4407),
        "SIN": Details(city: "Singapore", latitude: 1.3644, longitude: 103.9915),
        "HKG": Details(city: "Hong Kong", latitude: 22.3080, longitude: 113.9185),
        "SYD": Details(city: "Sydney, AU", latitude: -33.9399, longitude: 151.1753),
        "AKL": Details(city: "Auckland, NZ", latitude: -37.0082, longitude: 174.7850),
        "BOM": Details(city: "Mumbai, IN", latitude: 19.0896, longitude: 72.8656),
        "DEL": Details(city: "Delhi, IN", latitude: 28.5562, longitude: 77.1000),
    ]
}

// MARK: - Haversine Distance

/// Great-circle distance between two lat/lng pairs, in miles. Standard
/// haversine formula, Earth radius = 3958.8 mi.
private func haversineMiles(lat1: Double, lng1: Double, lat2: Double, lng2: Double) -> Double {
    let radius = 3958.8
    let toRad = Double.pi / 180
    let dLat = (lat2 - lat1) * toRad
    let dLng = (lng2 - lng1) * toRad
    let a = sin(dLat / 2) * sin(dLat / 2)
        + cos(lat1 * toRad) * cos(lat2 * toRad)
        * sin(dLng / 2) * sin(dLng / 2)
    let c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return radius * c
}
