import Foundation

enum SpeedTestPhase: Equatable {
    case idle
    case latency
    case download
    case upload
    case complete
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

    private var testTask: Task<Void, Never>?
    private let phaseDuration: TimeInterval = 12
    private let sampleIntervalNs: UInt64 = 250_000_000

    func startTest() {
        guard !isTesting else { return }
        resetResults()
        isTesting = true
        testDate = Date()

        testTask = Task {
            await runLatencyPhase()
            guard !Task.isCancelled else { return cleanup() }
            await runDownloadPhase()
            guard !Task.isCancelled else { return cleanup() }
            await runUploadPhase()
            phase = .complete
            isTesting = false
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
            progress = Double(i + 1) / 30.0
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
            progressBase: 1.0 / 3.0,
            progressSpan: 1.0 / 3.0
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
            progressBase: 2.0 / 3.0,
            progressSpan: 1.0 / 3.0
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
