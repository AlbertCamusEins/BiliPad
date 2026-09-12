import Combine
import Foundation
@preconcurrency import GameController

enum ControllerAction: String, Sendable {
    case up, down, left, right
    case confirm, back, danmaku, fullscreen, disableAutoplay, menu, previousTab, nextTab, refresh
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
    private let stickDeadZone: Float = 0.55

    init(bindings: ControllerBindings) {
        self.bindings = bindings
        observeControllers()
        selectController()
    }

    func captureNextButton(_ handler: @escaping (ControllerButton) -> Void) { captureHandler = handler }
    func cancelCapture() { captureHandler = nil }

    private func observeControllers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in self?.selectController() } })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in self?.selectController() } })
    }

    private func selectController() {
        let selected = GCController.controllers().first(where: \.isAttachedToDevice) ?? GCController.controllers().first
        guard selected !== activeController else { return }
        clearHandlers(on: activeController); stopDirectionalRepeat(); activeController = selected
        guard let selected else { isConnected = false; controllerName = "手柄"; return }
        isConnected = true; controllerName = selected.vendorName ?? selected.productCategory; configure(selected)
    }

    private func configure(_ controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }
        gamepad.dpad.valueChangedHandler = { [weak self] _, x, y in Task { @MainActor [weak self] in self?.dpadDirection = Self.direction(x: x, y: y, deadZone: 0.5); self?.updateDirectionalRepeat() } }
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in Task { @MainActor [weak self] in guard let self else { return }; self.stickDirection = Self.direction(x: x, y: y, deadZone: self.stickDeadZone); self.updateDirectionalRepeat() } }
        gamepad.buttonA.pressedChangedHandler = Self.buttonHandler(owner: self, button: .a)
        gamepad.buttonB.pressedChangedHandler = Self.buttonHandler(owner: self, button: .b)
        gamepad.buttonX.pressedChangedHandler = Self.buttonHandler(owner: self, button: .x)
        gamepad.buttonY.pressedChangedHandler = Self.buttonHandler(owner: self, button: .y)
        gamepad.buttonOptions?.pressedChangedHandler = Self.buttonHandler(owner: self, button: .options)
        gamepad.buttonMenu.pressedChangedHandler = Self.buttonHandler(owner: self, button: .menu)
        gamepad.leftShoulder.pressedChangedHandler = Self.buttonHandler(owner: self, button: .leftShoulder)
        gamepad.rightShoulder.pressedChangedHandler = Self.buttonHandler(owner: self, button: .rightShoulder)
        gamepad.leftThumbstickButton?.pressedChangedHandler = Self.buttonHandler(owner: self, button: .leftStick)
    }

    private nonisolated static func buttonHandler(owner: ControllerManager, button: ControllerButton) -> GCControllerButtonValueChangedHandler {
        { [weak owner] _, _, pressed in guard pressed else { return }; Task { @MainActor [weak owner] in owner?.handle(button) } }
    }

    private func handle(_ button: ControllerButton) {
        if let captureHandler { self.captureHandler = nil; captureHandler(button); return }
        if let action = bindings.action(for: button) { actions.send(action) }
    }

    private func clearHandlers(on controller: GCController?) {
        guard let gamepad = controller?.extendedGamepad else { return }
        gamepad.dpad.valueChangedHandler = nil; gamepad.leftThumbstick.valueChangedHandler = nil
        gamepad.buttonA.pressedChangedHandler = nil; gamepad.buttonB.pressedChangedHandler = nil
        gamepad.buttonX.pressedChangedHandler = nil; gamepad.buttonY.pressedChangedHandler = nil
        gamepad.buttonOptions?.pressedChangedHandler = nil; gamepad.buttonMenu.pressedChangedHandler = nil
        gamepad.leftShoulder.pressedChangedHandler = nil; gamepad.rightShoulder.pressedChangedHandler = nil
        gamepad.leftThumbstickButton?.pressedChangedHandler = nil
    }

    private func updateDirectionalRepeat() {
        let direction = dpadDirection ?? stickDirection
        guard direction != repeatingDirection else { return }
        stopDirectionalRepeat(); guard let direction else { return }
        repeatingDirection = direction; actions.send(direction)
        repeatTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 360_000_000)
                while !Task.isCancelled {
                    guard let self, self.repeatingDirection == direction else { return }
                    self.actions.send(direction); try await Task.sleep(nanoseconds: 155_000_000)
                }
            } catch { return }
        }
    }

    private func stopDirectionalRepeat() { repeatTask?.cancel(); repeatTask = nil; repeatingDirection = nil }

    private static func direction(x: Float, y: Float, deadZone: Float) -> ControllerAction? {
        guard max(abs(x), abs(y)) >= deadZone else { return nil }
        if abs(x) > abs(y) { return x > 0 ? .right : .left }
        return y > 0 ? .up : .down
    }
}
