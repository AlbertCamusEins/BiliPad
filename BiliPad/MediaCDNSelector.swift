import Foundation

struct CDNProbeResult: Sendable {
    let url: URL
    let duration: TimeInterval
    let bytesReceived: Int
    let bytesPerSecond: Double
}

struct MediaCDNSelector: Sendable {
    private let probeByteCount = 256 * 1024
    private let maximumCandidates = 3
    private let timeout: TimeInterval = 2.5

    func select(candidates: [URL], headers: [String: String]) async -> URL? {
        let candidates = Array(candidates.prefix(maximumCandidates))
        guard let fallback = candidates.first else { return nil }
        guard candidates.count > 1 else { return fallback }

        print("[BiliPad CDN] probing \(candidates.count) candidates")
        let results = await probeConcurrently(candidates, headers: headers)
        guard let winner = results.max(by: { lhs, rhs in
            lhs.bytesPerSecond < rhs.bytesPerSecond
        }) else {
            print("[BiliPad CDN] all probes failed; using primary host=\(fallback.host ?? "unknown")")
            return fallback
        }

        print("[BiliPad CDN] selected host=\(winner.url.host ?? "unknown")")
        return winner.url
    }

    private func probeConcurrently(_ candidates: [URL], headers: [String: String]) async -> [CDNProbeResult] {
        await withTaskGroup(of: ProbeEvent.self, returning: [CDNProbeResult].self) { group in
            for url in candidates {
                group.addTask {
                    .result(await probe(url: url, headers: headers))
                }
            }
            group.addTask {
                do {
                    try await Task.sleep(for: .milliseconds(2500))
                    return .timeout
                } catch {
                    return .cancelled
                }
            }

            var results: [CDNProbeResult] = []
            var remaining = candidates.count

            probeLoop: while let event = await group.next() {
                switch event {
                case let .result(result):
                    remaining -= 1
                    if let result { results.append(result) }
                    if remaining == 0 {
                        group.cancelAll()
                        break probeLoop
                    }
                case .timeout:
                    group.cancelAll()
                    break probeLoop
                case .cancelled:
                    if Task.isCancelled {
                        group.cancelAll()
                        break probeLoop
                    }
                }
            }
            return results
        }
    }

    private func probe(url: URL, headers: [String: String]) async -> CDNProbeResult? {
        guard !Task.isCancelled else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("bytes=0-\(probeByteCount - 1)", forHTTPHeaderField: "Range")
        for (name, value) in headers where !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let start = Date()
        do {
            let (data, response) = try await session.data(for: request)
            guard !Task.isCancelled,
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 206,
                  !data.isEmpty else { return nil }

            let duration = max(Date().timeIntervalSince(start), 0.001)
            let result = CDNProbeResult(
                url: url,
                duration: duration,
                bytesReceived: data.count,
                bytesPerSecond: Double(data.count) / duration
            )
            printProbe(result)
            return result
        } catch {
            guard !Task.isCancelled else { return nil }
            print("[BiliPad CDN] probe failed host=\(url.host ?? "unknown")")
            return nil
        }
    }

    private func printProbe(_ result: CDNProbeResult) {
        let speed = result.bytesPerSecond / 1024
        print(
            String(
                format: "[BiliPad CDN] host=%@ bytes=%d duration=%.2fs speed=%.0f KB/s",
                result.url.host ?? "unknown",
                result.bytesReceived,
                result.duration,
                speed
            )
        )
    }

    private enum ProbeEvent: Sendable {
        case result(CDNProbeResult?)
        case timeout
        case cancelled
    }
}
