import Combine
import Foundation

enum ControllerButton: String, CaseIterable, Codable, Identifiable, Sendable {
    case a, b, x, y, options, menu, leftShoulder, rightShoulder, leftStick
    var id: String { rawValue }
    var title: String {
        switch self {
        case .a: "A"
        case .b: "B"
        case .x: "X"
        case .y: "Y"
        case .options: "Options"
        case .menu: "Menu"
        case .leftShoulder: "LB"
        case .rightShoulder: "RB"
        case .leftStick: "L3"
        }
    }
}

enum MappableControllerAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case confirm, back, danmaku, context, disableAutoplay, menu, previousTab, nextTab, refresh
    var id: String { rawValue }
    var title: String {
        switch self {
        case .confirm: "确认 / 播放暂停"
        case .back: "返回"
        case .danmaku: "弹幕"
        case .context: "全屏 / 切换收藏视图"
        case .disableAutoplay: "切换自动连播"
        case .menu: "打开设置"
        case .previousTab: "上一个标签"
        case .nextTab: "下一个标签"
        case .refresh: "刷新当前页面"
        }
    }
    var action: ControllerAction {
        switch self {
        case .confirm: .confirm
        case .back: .back
        case .danmaku: .danmaku
        case .context: .fullscreen
        case .disableAutoplay: .disableAutoplay
        case .menu: .menu
        case .previousTab: .previousTab
        case .nextTab: .nextTab
        case .refresh: .refresh
        }
    }
}

@MainActor
final class ControllerBindings: ObservableObject {
    @Published private(set) var assignments: [MappableControllerAction: ControllerButton]
    private let defaultsKey = "controller-bindings-v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let stored = try? JSONDecoder().decode([MappableControllerAction: ControllerButton].self, from: data),
           MappableControllerAction.allCases.allSatisfy({ stored[$0] != nil }) {
            assignments = stored
        } else {
            assignments = Self.standard
        }
    }

    func button(for action: MappableControllerAction) -> ControllerButton { assignments[action] ?? Self.standard[action]! }

    func action(for button: ControllerButton) -> ControllerAction? {
        assignments.first(where: { $0.value == button })?.key.action
    }

    func assign(_ button: ControllerButton, to action: MappableControllerAction) {
        let oldButton = self.button(for: action)
        if let conflicting = assignments.first(where: { $0.value == button })?.key, conflicting != action {
            assignments[conflicting] = oldButton
        }
        assignments[action] = button
        if let data = try? JSONEncoder().encode(assignments) { UserDefaults.standard.set(data, forKey: defaultsKey) }
    }

    func reset() {
        assignments = Self.standard
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    private static let standard: [MappableControllerAction: ControllerButton] = [
        .confirm: .a, .back: .b, .danmaku: .x, .context: .y, .disableAutoplay: .options,
        .menu: .menu, .previousTab: .leftShoulder, .nextTab: .rightShoulder, .refresh: .leftStick
    ]
}
