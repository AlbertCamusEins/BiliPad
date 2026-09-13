import Foundation

enum PinyinIME {
    private struct Entry { let text: String; let weight: Int }
    private static let lexicon: [String: [String]] = loadLexicon()
    private static let domainTerms: [String: [String]] = [
        "bili": ["哔哩", "比例"], "bilibili": ["哔哩哔哩"], "danmu": ["弹幕"],
        "yuanshen": ["原神"], "saierda": ["塞尔达"], "shipin": ["视频"], "shoucang": ["收藏"]
    ]

    static func candidates(for pinyin: String) -> [String] {
        let key = pinyin.lowercased().filter(\.isLetter)
        guard !key.isEmpty else { return [] }
        let combined = (domainTerms[key] ?? []) + (lexicon[key] ?? [])
        var seen = Set<String>()
        let candidates = combined.filter { seen.insert($0).inserted }
        return candidates.isEmpty ? [key] : candidates
    }

    private static func loadLexicon() -> [String: [String]] {
        guard let url = Bundle.main.url(forResource: "pinyin_simp.dict", withExtension: "yaml"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return ["bilibili": ["哔哩哔哩"], "danmu": ["弹幕"], "shipin": ["视频"], "shoucang": ["收藏"]]
        }

        var table: [String: [Entry]] = [:]
        var bodyStarted = false
        contents.enumerateLines { line, _ in
            if !bodyStarted {
                if line.trimmingCharacters(in: .whitespacesAndNewlines) == "..." { bodyStarted = true }
                return
            }
            guard !line.isEmpty, line.first != "#" else { return }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 2 else { return }
            let text = String(fields[0])
            let key = fields[1].lowercased().filter(\.isLetter)
            guard !key.isEmpty else { return }
            let weight = fields.count > 2 ? Int(fields[2]) ?? 0 : 0
            table[key, default: []].append(Entry(text: text, weight: weight))
        }

        return table.mapValues { entries in
            var seen = Set<String>()
            return entries.sorted { $0.weight > $1.weight }.compactMap { entry in
                seen.insert(entry.text).inserted ? entry.text : nil
            }
        }
    }
}
