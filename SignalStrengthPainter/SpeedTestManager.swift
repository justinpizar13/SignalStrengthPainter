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

        let tracker = TransferTracker()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = phaseDuration + 5
        config.httpMaximumConnectionsPerHost = 8
        let session = URLSession(configuration: config, delegate: tracker, delegateQueue: nil)

        let perConnection = 25_000_000
        for i in 0..<4 {
            guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(perConnection)&cachebust=\(i)-\(Int.random(in: 0...999999))") else { continue }
            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            session.downloadTask(with: req).resume()
        }

        let phaseStart = CFAbsoluteTimeGetCurrent()
        var lastSampleTime = phaseStart
        var lastSampleBytes: Int64 = 0
        var samples: [Double] = []

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: sampleIntervalNs)
            let now = CFAbsoluteTimeGetCurrent()
            let elapsed = now - phaseStart
            let totalBytes = tracker.totalBytesDownloaded
            let sampleDuration = now - lastSampleTime
            let sampleBytes = totalBytes - lastSampleBytes

            if elapsed > 0.75 && sampleDuration > 0.05 {
                let mbps = Double(sampleBytes) * 8.0 / (sampleDuration * 1_000_000.0)
                samples.append(mbps)
                speedSamples = samples
                currentSpeed = mbps
            }

            lastSampleTime = now
            lastSampleBytes = totalBytes
            progress = 1.0 / 3.0 + min(elapsed / phaseDuration, 1.0) / 3.0

            let allDone = tracker.completedCount >= 4
            if elapsed >= phaseDuration || (allDone && elapsed > 1.5) { break }
        }

        session.invalidateAndCancel()
        downloadSpeed = trimmedMean(samples)
    }

    // MARK: - Upload Phase

    private func runUploadPhase() async {
        phase = .upload
        speedSamples = []
        currentSpeed = 0

        let tracker = TransferTracker()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = phaseDuration + 5
        config.httpMaximumConnectionsPerHost = 8
        let session = URLSession(configuration: config, delegate: tracker, delegateQueue: nil)

        let chunkSize = 25_000_000
        let payload = Data(count: chunkSize)

        for _ in 0..<4 {
            guard let url = URL(string: "https://speed.cloudflare.com/__up") else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            session.uploadTask(with: req, from: payload).resume()
        }

        let phaseStart = CFAbsoluteTimeGetCurrent()
        var lastSampleTime = phaseStart
        var lastSampleBytes: Int64 = 0
        var samples: [Double] = []

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: sampleIntervalNs)
            let now = CFAbsoluteTimeGetCurrent()
            let elapsed = now - phaseStart
            let totalBytes = tracker.totalBytesSent
            let sampleDuration = now - lastSampleTime
            let sampleBytes = totalBytes - lastSampleBytes

            if elapsed > 0.75 && sampleDuration > 0.05 {
                let mbps = Double(sampleBytes) * 8.0 / (sampleDuration * 1_000_000.0)
                samples.append(mbps)
                speedSamples = samples
                currentSpeed = mbps
            }

            lastSampleTime = now
            lastSampleBytes = totalBytes
            progress = 2.0 / 3.0 + min(elapsed / phaseDuration, 1.0) / 3.0

            if elapsed >= phaseDuration || tracker.completedCount >= 4 { break }
        }

        session.invalidateAndCancel()
        uploadSpeed = trimmedMean(samples)
    }

    // MARK: - Helpers

    private func trimmedMean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let dropCount = max(sorted.count / 10, 0)
        let trimmed = sorted.count > 2
            ? Array(sorted.dropFirst(dropCount).dropLast(dropCount))
            : sorted
        guard !trimmed.isEmpty else {
            return sorted.reduce(0, +) / Double(sorted.count)
        }
        return trimmed.reduce(0, +) / Double(trimmed.count)
    }
}

// MARK: - Transfer Tracker (URLSession Delegate)

final class TransferTracker: NSObject, URLSessionDataDelegate, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _bytesDownloaded: Int64 = 0
    private var _taskBytesSent: [Int: Int64] = [:]
    private var _completed: Int = 0

    var totalBytesDownloaded: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return _bytesDownloaded
    }

    var totalBytesSent: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return _taskBytesSent.values.reduce(0, +)
    }

    var completedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _completed
    }

    // MARK: Download tracking (URLSessionDownloadDelegate)

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        lock.lock()
        _bytesDownloaded += bytesWritten
        lock.unlock()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        try? FileManager.default.removeItem(at: location)
    }

    // MARK: Upload tracking (URLSessionTaskDelegate)

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        lock.lock()
        _taskBytesSent[task.taskIdentifier] = totalBytesSent
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        _completed += 1
        lock.unlock()
    }
}
