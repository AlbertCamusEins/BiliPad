import Foundation

struct CDNProbeResult: Sendable {
    let url: URL
    let duration: TimeInterval
    let bytesReceived: Int
    let bytesPerSecond: Double
}

private actor CDNPerformanceStore {
    static let shared = CDNPerformanceStore()

    private struct Entry: Sendable {
        var estimatedBytesPerSecond: Double
        var lastSuccess: Date
        var successCount: Int
        var failureCount: Int
    }

    private var entries: [String: Entry] = [:]

    func ranked(_ candidates: [URL]) -> [URL] {
        candidates.enumerated().sorted { lhs, rhs in
            let lhsScore = score(for: lhs.element)
            let rhsScore = score(for: rhs.element)
            if lhsScore == rhsScore { return lhs.offset < rhs.offset }
            return lhsScore > rhsScore
        }.map(\.element)
    }

    func recordSuccess(_ result: CDNProbeResult) {
        guard let host = result.url.host else { return }
        if var entry = entries[host] {
            entry.estimatedBytesPerSecond = entry.estimatedBytesPerSecond * 0.7 + result.bytesPerSecond * 0.3
            entry.lastSuccess = Date()
            entry.successCount += 1
            entries[host] = entry
        } else {
            entries[host] = Entry(
                estimatedBytesPerSecond: result.bytesPerSecond,
                lastSuccess: Date(),
                successCount: 1,
                failureCount: 0
            )
        }
    }

    func recordFailure(url: URL) {
        guard let host = url.host else { return }
        if var entry = entries[host] {
            entry.failureCount += 1
            entries[host] = entry
        } else {
            entries[host] = Entry(
                estimatedBytesPerSecond: 0,
                lastSuccess: .distantPast,
                successCount: 0,
                failureCount: 1
            )
        }
    }

    private func score(for url: URL) -> Double {
        guard let host = url.host, let entry = entries[host] else { return -1 }
        let reliability = Double(entry.successCount) / Double(max(1, entry.successCount + entry.failureCount))
        return entry.estimatedBytesPerSecond * max(0.25, reliability)
    }
}
struct MediaCDNSelector: Sendable {
    private let probeByteCount = 64 * 1024
    private let maximumCandidates = 3
    private let fastEnoughBytesPerSecond = 2.0 * 1024 * 1024
    private let minimumDecisionWindow: TimeInterval = 0.35
    private let softDeadline: TimeInterval = 0.70
    private let hardTimeout: TimeInterval = 2.5
    private let performanceStore = CDNPerformanceStore.shared

    func select(candidates: [URL], headers: [String: String]) async -> URL? {
        guard let fallback = candidates.first else { return nil }

        let uniqueCandidates = candidates.reduce(into: [URL]()) { result, url in
            if !result.contains(url) { result.append(url) }
        }
        guard uniqueCandidates.count > 1 else { return fallback }

        let ranked = await performanceStore.ranked(uniqueCandidates)
        var probeCandidates = Array(ranked.prefix(maximumCandidates))
        if !probeCandidates.contains(fallback) {
            if probeCandidates.count == maximumCandidates {
                probeCandidates.removeLast()
            }
            probeCandidates.insert(fallback, at: 0)
        }

        print("[BiliPad CDN] probing \(probeCandidates.count) candidates")
        guard let winner = await probeConcurrently(probeCandidates, headers: headers) else {
            print("[BiliPad CDN] all probes failed; using primary host=\(fallback.host ?? "unknown")")
            return fallback
        }

        print("[BiliPad CDN] selected host=\(winner.url.host ?? "unknown")")
        return winner.url
    }

    private func probeConcurrently(_ candidates: [URL], headers: [String: String]) async -> CDNProbeResult? {
        let raceStart = Date()
        let (stream, continuation) = AsyncStream<ProbeEvent>.makeStream()

        var tasks = candidates.map { url in
            Task {
                let result = await probe(url: url, headers: headers)
                guard !Task.isCancelled else { return }
                continuation.yield(.result(url, result))
            }
        }

        tasks.append(Task {
            do {
                try await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                continuation.yield(.minimumDecisionWindow)
            } catch {}
        })
        tasks.append(Task {
            do {
                try await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                continuation.yield(.softDeadline)
            } catch {}
        })
        tasks.append(Task {
            do {
                try await Task.sleep(for: .milliseconds(2500))
                guard !Task.isCancelled else { return }
                continuation.yield(.hardTimeout)
            } catch {}
        })

        defer {
            tasks.forEach { $0.cancel() }
            continuation.finish()
        }

        var results: [CDNProbeResult] = []
        var completed = 0

        for await event in stream {
            guard !Task.isCancelled else { return bestResult(in: results) }
            let elapsed = Date().timeIntervalSince(raceStart)

            switch event {
            case let .result(url, result):
                completed += 1

                if let result {
                    results.append(result)
                    await performanceStore.recordSuccess(result)

                    if result.bytesPerSecond >= fastEnoughBytesPerSecond {
                        printDecision("fast enough", elapsed: elapsed, result: result)
                        return result
                    }

                    if elapsed >= minimumDecisionWindow, results.count >= 2,
                       let best = bestResult(in: results) {
                        printDecision("two results", elapsed: elapsed, result: best)
                        return best
                    }
                } else {
                    await performanceStore.recordFailure(url: url)
                }

                if completed == candidates.count {
                    if let best = bestResult(in: results) {
                        printDecision("all results", elapsed: elapsed, result: best)
                    }
                    return bestResult(in: results)
                }

            case .minimumDecisionWindow:
                if results.count >= 2, let best = bestResult(in: results) {
                    printDecision("minimum decision window", elapsed: elapsed, result: best)
                    return best
                }

            case .softDeadline:
                if let best = bestResult(in: results) {
                    printDecision("soft deadline", elapsed: elapsed, result: best)
                    return best
                }

            case .hardTimeout:
                if let best = bestResult(in: results) {
                    printDecision("hard timeout", elapsed: elapsed, result: best)
                }
                return bestResult(in: results)
            }
        }

        return bestResult(in: results)
    }
    private func probe(url: URL, headers: [String: String]) async -> CDNProbeResult? {
        guard !Task.isCancelled else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = hardTimeout
        request.setValue("bytes=0-\(probeByteCount - 1)", forHTTPHeaderField: "Range")
        for (name, value) in headers where !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = hardTimeout
        configuration.timeoutIntervalForResource = hardTimeout
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

    private func bestResult(in results: [CDNProbeResult]) -> CDNProbeResult? {
        results.max { lhs, rhs in lhs.bytesPerSecond < rhs.bytesPerSecond }
    }

    private func printDecision(_ reason: String, elapsed: TimeInterval, result: CDNProbeResult) {
        print(
            String(
                format: "[BiliPad CDN] decision=%@ elapsed=%.2fs host=%@ speed=%.0f KB/s",
                reason,
                elapsed,
                result.url.host ?? "unknown",
                result.bytesPerSecond / 1024
            )
        )
    }

    private enum ProbeEvent: Sendable {
        case result(URL, CDNProbeResult?)
        case minimumDecisionWindow
        case softDeadline
        case hardTimeout
    }
}
