import Foundation
import Network

final class LatencyProbe {
    private let queue = DispatchQueue(label: "latency.probe.queue")

    func measureLatency(host: String = "8.8.8.8", port: UInt16 = 53, timeout: TimeInterval = 0.45, completion: @escaping (Double?) -> Void) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            completion(nil)
            return
        }

        let endpointHost = NWEndpoint.Host(host)
        let start = DispatchTime.now()
        let connection = NWConnection(host: endpointHost, port: nwPort, using: .tcp)

        var completed = false
        func finish(_ value: Double?) {
            guard !completed else { return }
            completed = true
            connection.cancel()
            DispatchQueue.main.async {
                completion(value)
            }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let elapsedNs = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                let elapsedMs = Double(elapsedNs) / 1_000_000
                finish(elapsedMs)
            case .failed, .cancelled:
                finish(nil)
            default:
                break
            }
        }

        queue.asyncAfter(deadline: .now() + timeout) {
            finish(nil)
        }

        connection.start(queue: queue)
    }
}
