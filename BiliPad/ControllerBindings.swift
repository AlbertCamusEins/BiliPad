import Combine
import Foundation

enum ControllerButton: String, CaseIterable, Codable, Identifiable, Sendable {
    case a, b, x, y, options, menu, leftShoulder, rightShoulder, leftTrigger, rightTrigger, leftStick
    var id: String { rawValue }
    var title: String {
        switch self {
        case .a: "A"; case .b: "B"; case .x: "X"; case .y: "Y"
        case .options: "Options"; case .menu: "Menu"
        case .leftShoulder: "LB"; case .rightShoulder: "RB"
        case .leftTrigger: "LT"; case .rightTrigger: "RT"; case .leftStick: "L3"
        }
    }
}

enum MappableControllerAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case confirm, back, playPause, context, interaction, toggleDanmaku, menu, previousTab, nextTab, refresh
    var id: String { rawValue }
    var title: String {
        switch self {
        case .confirm: "确认 / 点击焦点"; case .back: "返回"; case .playPause: "播放 / 暂停"
        case .context: "全屏 / 切换视图"; case .interaction: "点赞 / 收藏"; case .toggleDanmaku: "开关弹幕"
        case .menu: "打开设置"; case .previousTab: "上一个标签"; case .nextTab: "下一个标签"; case .refresh: "刷新当前页面"
        }
    }
    var action: ControllerAction {
        switch self {
        case .confirm: .confirm; case .back: .back; case .playPause: .playPause; case .context: .fullscreen
        case .interaction: .interaction; case .toggleDanmaku: .toggleDanmaku; case .menu: .menu
        case .previousTab: .previousTab; case .nextTab: .nextTab; case .refresh: .refresh
        }
    }
}

@MainActor
final class ControllerBindings: ObservableObject {
    @Published private(set) var assignments: [MappableControllerAction: ControllerButton]
    private let defaultsKey = "controller-bindings-v2"
    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey), let stored = try? JSONDecoder().decode([MappableControllerAction: ControllerButton].self, from: data), MappableControllerAction.allCases.allSatisfy({ stored[$0] != nil }) { assignments = stored }
        else { assignments = Self.standard }
    }
    func button(for action: MappableControllerAction) -> ControllerButton { assignments[action] ?? Self.standard[action]! }
    func action(for button: ControllerButton) -> ControllerAction? { assignments.first(where: { $0.value == button })?.key.action }
    func assign(_ button: ControllerButton, to action: MappableControllerAction) {
        let old = self.button(for: action)
        if let conflict = assignments.first(where: { $0.value == button })?.key, conflict != action { assignments[conflict] = old }
        assignments[action] = button
        if let data = try? JSONEncoder().encode(assignments) { UserDefaults.standard.set(data, forKey: defaultsKey) }
    }
    func reset() { assignments = Self.standard; UserDefaults.standard.removeObject(forKey: defaultsKey) }
    private static let standard: [MappableControllerAction: ControllerButton] = [
        .confirm: .a, .back: .b, .playPause: .x, .context: .y, .interaction: .leftTrigger,
        .toggleDanmaku: .rightTrigger, .menu: .menu, .previousTab: .leftShoulder, .nextTab: .rightShoulder, .refresh: .leftStick
    ]
}
