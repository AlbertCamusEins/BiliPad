import Combine
import Foundation
@preconcurrency import GameController

enum ControllerAction: String, Sendable {
    case up, down, left, right, stickUp, stickDown, confirm, back, playPause, fullscreen, interaction, tripleInteraction, toggleDanmaku, menu, previousTab, nextTab, refresh
}

@MainActor
final class ControllerManager: ObservableObject {
    let actions = PassthroughSubject<ControllerAction, Never>()
    @Published private(set) var isConnected = false
    @Published private(set) var controllerName = "手柄"
    private let bindings: ControllerBindings
    private var captureHandler: ((ControllerButton) -> Void)?
    private var activeController: GCController?
    private var observers: [NSObjectProtocol] = []
    private var dpadDirection: ControllerAction?
    private var stickDirection: ControllerAction?
    private var repeatTask: Task<Void, Never>?
    private var repeatingDirection: ControllerAction?
    private var holdTask: Task<Void, Never>?
    private var longInteractionSent = false

    init(bindings: ControllerBindings) { self.bindings = bindings; observeControllers(); selectController() }
    func captureNextButton(_ handler: @escaping (ControllerButton) -> Void) { captureHandler = handler }
    func cancelCapture() { captureHandler = nil }

    private func observeControllers() {
        observers.append(NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in self?.selectController() } })
        observers.append(NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in self?.selectController() } })
    }
    private func selectController() {
        let selected = GCController.controllers().first(where: \.isAttachedToDevice) ?? GCController.controllers().first
        guard selected !== activeController else { return }
        clearHandlers(on: activeController); stopRepeat(); activeController = selected
        guard let selected else { isConnected = false; controllerName = "手柄"; return }
        isConnected = true; controllerName = selected.vendorName ?? selected.productCategory; configure(selected)
    }
    private func configure(_ controller: GCController) {
        guard let g = controller.extendedGamepad else { return }
        g.dpad.valueChangedHandler = { [weak self] _, x, y in Task { @MainActor [weak self] in self?.dpadDirection = Self.direction(x, y, 0.5); self?.updateRepeat() } }
        g.leftThumbstick.valueChangedHandler = { [weak self] _, _, y in Task { @MainActor [weak self] in self?.stickDirection = Self.stickDirection(y, 0.55); self?.updateRepeat() } }
        [(g.buttonA, ControllerButton.a), (g.buttonB, .b), (g.buttonX, .x), (g.buttonY, .y), (g.buttonMenu, .menu), (g.leftShoulder, .leftShoulder), (g.rightShoulder, .rightShoulder), (g.leftTrigger, .leftTrigger), (g.rightTrigger, .rightTrigger)].forEach { input, button in input.pressedChangedHandler = Self.handler(self, button) }
        g.buttonOptions?.pressedChangedHandler = Self.handler(self, .options)
        g.leftThumbstickButton?.pressedChangedHandler = Self.handler(self, .leftStick)
    }
    private nonisolated static func handler(_ owner: ControllerManager, _ button: ControllerButton) -> GCControllerButtonValueChangedHandler {
        { [weak owner] _, _, pressed in Task { @MainActor [weak owner] in owner?.handle(button, pressed) } }
    }
    private func handle(_ button: ControllerButton, _ pressed: Bool) {
        if pressed, let captureHandler { self.captureHandler = nil; captureHandler(button); return }
        guard let action = bindings.action(for: button) else { return }
        if action == .interaction {
            if pressed {
                longInteractionSent = false; holdTask?.cancel()
                holdTask = Task { [weak self] in try? await Task.sleep(for: .seconds(3)); guard !Task.isCancelled, let self else { return }; self.longInteractionSent = true; self.actions.send(.tripleInteraction) }
            } else {
                holdTask?.cancel(); holdTask = nil
                if !longInteractionSent { actions.send(.interaction) }
            }
        } else if pressed { actions.send(action) }
    }
    private func clearHandlers(on controller: GCController?) {
        guard let g = controller?.extendedGamepad else { return }
        g.dpad.valueChangedHandler = nil; g.leftThumbstick.valueChangedHandler = nil
        [g.buttonA, g.buttonB, g.buttonX, g.buttonY, g.buttonMenu, g.leftShoulder, g.rightShoulder, g.leftTrigger, g.rightTrigger].forEach { $0.pressedChangedHandler = nil }
        g.buttonOptions?.pressedChangedHandler = nil; g.leftThumbstickButton?.pressedChangedHandler = nil
    }
    private func updateRepeat() {
        let direction = dpadDirection ?? stickDirection
        guard direction != repeatingDirection else { return }
        stopRepeat(); guard let direction else { return }; repeatingDirection = direction; actions.send(direction)
        repeatTask = Task { [weak self] in try? await Task.sleep(for: .milliseconds(360)); while !Task.isCancelled { guard let self, self.repeatingDirection == direction else { return }; self.actions.send(direction); try? await Task.sleep(for: .milliseconds(155)) } }
    }
    private func stopRepeat() { repeatTask?.cancel(); repeatTask = nil; repeatingDirection = nil }
    private static func direction(_ x: Float, _ y: Float, _ deadZone: Float) -> ControllerAction? {
        guard max(abs(x), abs(y)) >= deadZone else { return nil }
        return abs(x) > abs(y) ? (x > 0 ? .right : .left) : (y > 0 ? .up : .down)
    }
    private static func stickDirection(_ y: Float, _ deadZone: Float) -> ControllerAction? {
        guard abs(y) >= deadZone else { return nil }
        return y > 0 ? .stickUp : .stickDown
    }
}
