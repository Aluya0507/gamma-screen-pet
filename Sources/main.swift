import AppKit

struct AnimationSpec {
    let state: String
    let durations: [TimeInterval]
}

let animationSpecs: [String: AnimationSpec] = [
    "idle": AnimationSpec(state: "idle", durations: [0.28, 0.11, 0.11, 0.14, 0.14, 0.32]),
    "running-right": AnimationSpec(state: "running-right", durations: [0.12, 0.12, 0.12, 0.12, 0.12, 0.12, 0.12, 0.22]),
    "running-left": AnimationSpec(state: "running-left", durations: [0.12, 0.12, 0.12, 0.12, 0.12, 0.12, 0.12, 0.22]),
    "waving": AnimationSpec(state: "waving", durations: [0.14, 0.14, 0.14, 0.28]),
    "jumping": AnimationSpec(state: "jumping", durations: [0.14, 0.14, 0.14, 0.14, 0.28]),
    "failed": AnimationSpec(state: "failed", durations: [0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.24]),
    "waiting": AnimationSpec(state: "waiting", durations: [0.15, 0.15, 0.15, 0.15, 0.15, 0.26]),
    "running": AnimationSpec(state: "running", durations: [0.12, 0.12, 0.12, 0.12, 0.12, 0.22]),
    "review": AnimationSpec(state: "review", durations: [0.15, 0.15, 0.15, 0.15, 0.15, 0.28]),
]

let oneShotStates: Set<String> = ["waving", "jumping", "failed", "review"]

let visualScaleByState: [String: CGFloat] = [
    "idle": 0.62,
    "running-right": 1.0,
    "running-left": 1.0,
    "waving": 0.63,
    "jumping": 0.61,
    "failed": 0.97,
    "waiting": 0.72,
    "running": 0.61,
    "review": 0.63,
]

final class GammaView: NSView {
    private var framesByState: [String: [NSImage]] = [:]
    private var currentState = "idle"
    private var frameIndex = 0
    private var timer: Timer?
    private var lockCurrentState = false
    private var isIdlePatrolling = false
    private var idlePatrolDirection: CGFloat = -1
    private var idlePatrolTimer: Timer?
    private var idlePatrolGeneration = 0
    private var idlePatrolTargetX: CGFloat?
    private var idlePatrolGroundY: CGFloat?
    private var dragStartLocation: NSPoint?
    private var dragStartOrigin: NSPoint?
    private var lastDragX: CGFloat?
    private var didDrag = false
    private var clickCountTimer: Timer?
    private var idleCycles = 0
    private var pounceCooldownUntil = Date.distantPast
    private var pounceReturnOrigin: NSPoint?
    private var debugEnabled = false
    private var lastDebugLog = Date.distantPast

    override var acceptsFirstResponder: Bool { true }

    init(frame: NSRect, resourcesURL: URL) {
        super.init(frame: frame)
        debugEnabled = ProcessInfo.processInfo.environment["GAMMA_DEBUG"] == "1"
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        framesByState = Self.loadFrames(resourcesURL: resourcesURL)
        setupMenu()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func loadFrames(resourcesURL: URL) -> [String: [NSImage]] {
        var result: [String: [NSImage]] = [:]
        for state in animationSpecs.keys {
            let dir = resourcesURL.appendingPathComponent("frames").appendingPathComponent(state)
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil
            )) ?? []
            let images = urls
                .filter { $0.pathExtension.lowercased() == "png" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .compactMap { NSImage(contentsOf: $0) }
            if !images.isEmpty {
                result[state] = images
            }
        }
        return result
    }

    private func setupMenu() {
        let menu = NSMenu()
        addMenuItem(menu, title: "Wave", state: "waving")
        addMenuItem(menu, title: "Jump", state: "jumping")
        addMenuItem(menu, title: "Work", state: "running")
        addMenuItem(menu, title: "Review", state: "review")
        addMenuItem(menu, title: "Nap", state: "waiting")
        addMenuItem(menu, title: "Oops", state: "failed")
        addMenuItem(menu, title: "Idle", state: "idle")
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Gamma", action: #selector(quit), keyEquivalent: "q"))
        self.menu = menu
    }

    private func addMenuItem(_ menu: NSMenu, title: String, state: String) {
        let item = NSMenuItem(title: title, action: #selector(menuAction(_:)), keyEquivalent: "")
        item.representedObject = state
        item.target = self
        menu.addItem(item)
    }

    @objc private func menuAction(_ sender: NSMenuItem) {
        if let state = sender.representedObject as? String {
            play(state, locked: true)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func play(_ state: String, locked: Bool = false) {
        guard framesByState[state] != nil else { return }

        if state == "idle" {
            lockCurrentState = locked
            startIdlePatrol()
            return
        }

        stopIdlePatrol()
        currentState = state
        frameIndex = 0
        idleCycles = 0
        lockCurrentState = locked
        scheduleNextFrame(after: 0)
    }

    private func startIdlePatrol() {
        isIdlePatrolling = true
        idlePatrolGeneration += 1
        idlePatrolDirection = -idlePatrolDirection
        idleCycles = 0
        advanceIdlePatrol(generation: idlePatrolGeneration)
    }

    private func stopIdlePatrol() {
        isIdlePatrolling = false
        idlePatrolGeneration += 1
        idlePatrolTimer?.invalidate()
        idlePatrolTimer = nil
        if let window, let groundY = idlePatrolGroundY {
            window.setFrameOrigin(NSPoint(x: window.frame.origin.x, y: groundY))
        }
        idlePatrolTargetX = nil
        idlePatrolGroundY = nil
    }

    private func advanceIdlePatrol(generation: Int) {
        guard isIdlePatrolling, generation == idlePatrolGeneration else { return }
        guard let window else {
            idlePatrolTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
                self?.advanceIdlePatrol(generation: generation)
            }
            return
        }

        idlePatrolDirection *= -1
        let walkingState = idlePatrolDirection < 0 ? "running-left" : "running-right"
        currentState = walkingState
        frameIndex = 0
        scheduleNextFrame(after: 0)

        let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
        let duration: TimeInterval = 2.5
        let distance: CGFloat = 180
        let start = window.frame.origin
        let targetX = min(
            max(start.x + idlePatrolDirection * distance, screenFrame.minX + 12),
            screenFrame.maxX - window.frame.width - 12
        )
        idlePatrolTargetX = targetX
        idlePatrolGroundY = start.y

        idlePatrolTimer?.invalidate()
        idlePatrolTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.advanceIdlePatrol(generation: generation)
        }
    }

    private func stepIdlePatrol(frameDuration: TimeInterval) {
        guard isIdlePatrolling,
              currentState == "running-left" || currentState == "running-right",
              let window,
              let targetX = idlePatrolTargetX,
              let groundY = idlePatrolGroundY else { return }

        let speed: CGFloat = 72
        let step = idlePatrolDirection * speed * CGFloat(frameDuration)
        let origin = window.frame.origin
        let nextX: CGFloat
        if idlePatrolDirection < 0 {
            nextX = max(targetX, origin.x + step)
        } else {
            nextX = min(targetX, origin.x + step)
        }

        let bobPattern: [CGFloat] = [0, 2, 1, 0, 2, 1, 0, -1]
        let bob = bobPattern[frameIndex % bobPattern.count]
        window.setFrameOrigin(NSPoint(x: nextX.rounded(), y: groundY + bob))
    }

    func maybePounce(at mouse: NSPoint) {
        guard Date() >= pounceCooldownUntil, let window else { return }
        guard !isIdlePatrolling else { return }
        guard !lockCurrentState else { return }
        guard currentState == "idle" || currentState == "waiting" else { return }

        let frame = window.frame
        let horizontalPadding: CGFloat = 150
        let isAbove = mouse.y > frame.maxY - 16 && mouse.y < frame.maxY + 280
        let isNearHorizontally = mouse.x > frame.minX - horizontalPadding && mouse.x < frame.maxX + horizontalPadding

        if debugEnabled, Date().timeIntervalSince(lastDebugLog) > 0.5 {
            lastDebugLog = Date()
            print(
                "Gamma debug mouse=(\(Int(mouse.x)),\(Int(mouse.y))) window=(\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height))) above=\(isAbove) near=\(isNearHorizontally) state=\(currentState)"
            )
            fflush(stdout)
        }

        guard isAbove && isNearHorizontally else { return }

        pounceCooldownUntil = Date().addingTimeInterval(1.6)
        if debugEnabled {
            print("Gamma debug pounce triggered")
            fflush(stdout)
        }
        play("jumping")

        let currentOrigin = frame.origin
        pounceReturnOrigin = currentOrigin
        let targetX = currentOrigin.x + max(-34, min(34, mouse.x - frame.midX))
        let targetY = currentOrigin.y + 44

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrameOrigin(NSPoint(x: targetX, y: targetY))
        } completionHandler: { [weak self, weak window] in
            guard let self, let window, let origin = self.pounceReturnOrigin else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrameOrigin(origin)
            } completionHandler: {
                if self.currentState == "jumping", !self.lockCurrentState {
                    self.play("idle")
                }
            }
        }
    }

    private func scheduleNextFrame(after delay: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.advanceFrame()
        }
    }

    private func advanceFrame() {
        needsDisplay = true
        guard let spec = animationSpecs[currentState],
              let frames = framesByState[currentState],
              !frames.isEmpty else { return }

        let duration = spec.durations[frameIndex % spec.durations.count]
        frameIndex += 1

        if frameIndex >= frames.count {
            if oneShotStates.contains(currentState), !lockCurrentState {
                play("idle")
                return
            }
            if currentState == "idle", !lockCurrentState {
                idleCycles += 1
                if idleCycles >= Int.random(in: 4...7) {
                    play(Bool.random() ? "idle" : "waiting")
                    return
                }
            }
            if currentState == "waiting", !lockCurrentState, Int.random(in: 0...5) == 0 {
                play("idle")
                return
            }
        }

        stepIdlePatrol(frameDuration: duration)
        scheduleNextFrame(after: duration)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        guard let frames = framesByState[currentState], !frames.isEmpty else { return }
        let image = frames[frameIndex % frames.count]
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
            * (visualScaleByState[currentState] ?? 1.0)
        let width = image.size.width * scale
        let height = image.size.height * scale
        let rect = NSRect(
            x: (bounds.width - width) / 2,
            y: (bounds.height - height) / 2,
            width: width,
            height: height
        )
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        dragStartLocation = NSEvent.mouseLocation
        dragStartOrigin = window?.frame.origin
        lastDragX = dragStartLocation?.x
        didDrag = false
        stopIdlePatrol()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let dragStartLocation, let dragStartOrigin else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - dragStartLocation.x
        let dy = current.y - dragStartLocation.y
        window.setFrameOrigin(NSPoint(x: dragStartOrigin.x + dx, y: dragStartOrigin.y + dy))
        didDrag = didDrag || abs(dx) > 3 || abs(dy) > 3

        if let lastDragX {
            let direction = current.x - lastDragX
            if direction > 2, currentState != "running-right" {
                play("running-right", locked: true)
            } else if direction < -2, currentState != "running-left" {
                play("running-left", locked: true)
            }
        }
        lastDragX = current.x
    }

    override func mouseUp(with event: NSEvent) {
        dragStartLocation = nil
        dragStartOrigin = nil
        lastDragX = nil

        if didDrag {
            didDrag = false
            return
        }

        if event.clickCount >= 2 {
            play("jumping", locked: true)
        } else {
            play("waving", locked: true)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if let menu {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "w": play("waving", locked: true)
        case "j": play("jumping", locked: true)
        case "r": play("running", locked: true)
        case "i": play("idle", locked: true)
        case "\u{1b}": NSApp.terminate(nil)
        default: super.keyDown(with: event)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private weak var gammaView: GammaView?
    private var cursorTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        guard let resourcesURL = Bundle.main.resourceURL else {
            NSApp.terminate(nil)
            return
        }

        let size = NSSize(width: 192, height: 208)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let origin = NSPoint(
            x: min(max(mouse.x - size.width / 2, screenFrame.minX + 24), screenFrame.maxX - size.width - 24),
            y: max(screenFrame.minY + 36, min(mouse.y - size.height - 120, screenFrame.maxY - size.height - 36))
        )
        let frame = NSRect(origin: origin, size: size)

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = false
        window.acceptsMouseMovedEvents = true

        let view = GammaView(frame: NSRect(origin: .zero, size: size), resourcesURL: resourcesURL)
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        self.window = window
        self.gammaView = view
        view.play("idle")

        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.gammaView?.maybePounce(at: NSEvent.mouseLocation)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
