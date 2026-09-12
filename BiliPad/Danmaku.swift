import AVFoundation
import Foundation
import SwiftUI

struct DanmakuItem: Identifiable, Sendable {
    let id: Int
    let time: Double
    let text: String
    let color: Int
}

struct DanmakuService: Sendable {
    func load(cid: Int64) async throws -> [DanmakuItem] {
        let (data, response) = try await URLSession.shared.data(from: URL(string: "https://comment.bilibili.com/\(cid).xml")!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw BiliError.invalidResponse }
        return DanmakuXMLParser.parse(data)
    }
}

private final class DanmakuXMLParser: NSObject, XMLParserDelegate {
    private var values: [DanmakuItem] = []
    private var metadata: String?
    private var buffer = ""

    static func parse(_ data: Data) -> [DanmakuItem] {
        let delegate = DanmakuXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.values.sorted { $0.time < $1.time }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard elementName == "d" else { return }
        metadata = attributeDict["p"]; buffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { if metadata != nil { buffer += string } }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName == "d", let metadata else { return }
        let parts = metadata.split(separator: ",")
        if let time = parts.first.flatMap({ Double($0) }) {
            let color = parts.count > 3 ? Int(parts[3]) ?? 0xFFFFFF : 0xFFFFFF
            values.append(DanmakuItem(id: values.count, time: time, text: buffer, color: color))
        }
        self.metadata = nil
    }
}

struct DanmakuOverlay: View {
    let currentTime: Double
    let items: [DanmakuItem]

    var body: some View {
        GeometryReader { geometry in
            ForEach(activeItems(at: currentTime)) { item in
                    let elapsed = max(0, currentTime - item.time)
                    let progress = elapsed / 8.0
                    Text(item.text)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(color(item.color))
                        .shadow(color: .black, radius: 1.5)
                        .lineLimit(1)
                        .position(x: geometry.size.width * (1.12 - progress * 1.35), y: 28 + CGFloat(item.id % 8) * 28)
            }
        }.allowsHitTesting(false).clipped()
    }

    private func activeItems(at time: Double) -> [DanmakuItem] {
        guard time.isFinite else { return [] }
        return items.filter { $0.time <= time && time - $0.time < 8 }.suffix(40)
    }

    private func color(_ rgb: Int) -> Color {
        Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
}
