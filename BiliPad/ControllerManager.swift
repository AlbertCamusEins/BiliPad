import Combine
import Foundation
@preconcurrency import GameController

enum ControllerAction: String, Sendable {
    case up
    case down
    case left
    case right
    case confirm
    case back
    case danmaku
    case fullscreen
    case disableAutoplay
    case menu
}

@MainActor
final class ControllerManager: ObservableObject {
    let actions = PassthroughSubject<ControllerAction, Never>()

    @Published private(set) var isConnected = false
    @Published private(set) var controllerName = "手柄"

    private var activeController: GCController?
    private var observers: [NSObjectProtocol] = []
    private var dpadDirection: ControllerAction?
    private var stickDirection: ControllerAction?
    private var repeatTask: Task<Void, Never>?
    private var repeatingDirection: ControllerAction?

    private let stickDeadZone: Float = 0.55
    private let initialRepeatDelay: UInt64 = 360_000_000
    private let repeatInterval: UInt64 = 155_000_000

    init() {
        observeControllers()
        selectController()
    }

    private func observeControllers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.selectController() }
        })
        observers.append(center.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.selectController() }
        })
    }

    private func selectController() {
        let controllers = GCController.controllers()
        let selected = controllers.first(where: \.isAttachedToDevice) ?? controllers.first

        guard selected !== activeController else { return }
        clearHandlers(on: activeController)
        stopDirectionalRepeat()
        activeController = selected

        guard let selected else {
            isConnected = false
            controllerName = "手柄"
            return
        }

        isConnected = true
        controllerName = selected.vendorName ?? selected.productCategory
        configure(selected)
    }

    private func configure(_ controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }

        gamepad.dpad.valueChangedHandler = { [weak self] _, x, y in
            Task { @MainActor [weak self] in
                self?.dpadDirection = Self.direction(x: x, y: y, deadZone: 0.5)
                self?.updateDirectionalRepeat()
            }
        }
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.stickDirection = Self.direction(x: x, y: y, deadZone: self.stickDeadZone)
                self.updateDirectionalRepeat()
            }
        }

        gamepad.buttonA.pressedChangedHandler = Self.buttonHandler(owner: self, action: .confirm)
        gamepad.buttonB.pressedChangedHandler = Self.buttonHandler(owner: self, action: .back)
        gamepad.buttonX.pressedChangedHandler = Self.buttonHandler(owner: self, action: .danmaku)
        gamepad.buttonY.pressedChangedHandler = Self.buttonHandler(owner: self, action: .fullscreen)
        gamepad.buttonOptions?.pressedChangedHandler = Self.buttonHandler(owner: self, action: .disableAutoplay)
        gamepad.buttonMenu.pressedChangedHandler = Self.buttonHandler(owner: self, action: .menu)
    }

    private nonisolated static func buttonHandler(
        owner: ControllerManager,
        action: ControllerAction
    ) -> GCControllerButtonValueChangedHandler {
        { [weak owner] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor [weak owner] in owner?.actions.send(action) }
        }
    }

    private func clearHandlers(on controller: GCController?) {
        guard let gamepad = controller?.extendedGamepad else { return }
        gamepad.dpad.valueChangedHandler = nil
        gamepad.leftThumbstick.valueChangedHandler = nil
        gamepad.buttonA.pressedChangedHandler = nil
        gamepad.buttonB.pressedChangedHandler = nil
        gamepad.buttonX.pressedChangedHandler = nil
        gamepad.buttonY.pressedChangedHandler = nil
        gamepad.buttonOptions?.pressedChangedHandler = nil
        gamepad.buttonMenu.pressedChangedHandler = nil
    }

    private func updateDirectionalRepeat() {
        let direction = dpadDirection ?? stickDirection
        guard direction != repeatingDirection else { return }

        stopDirectionalRepeat()
        guard let direction else { return }

        repeatingDirection = direction
        actions.send(direction)
        let delay = initialRepeatDelay
        let interval = repeatInterval
        repeatTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
                while !Task.isCancelled {
                    guard let self, self.repeatingDirection == direction else { return }
                    self.actions.send(direction)
                    try await Task.sleep(nanoseconds: interval)
                }
            } catch {
                return
            }
        }
    }

    private func stopDirectionalRepeat() {
        repeatTask?.cancel()
        repeatTask = nil
        repeatingDirection = nil
    }

    private static func direction(x: Float, y: Float, deadZone: Float) -> ControllerAction? {
        guard max(abs(x), abs(y)) >= deadZone else { return nil }
        if abs(x) > abs(y) {
            return x > 0 ? .right : .left
        }
        return y > 0 ? .up : .down
    }
}
