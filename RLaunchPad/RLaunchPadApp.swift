//
//  RLaunchPadApp.swift
//  RLaunchPad
//
//  Created by luo on 2026/1/14.
//

import SwiftUI
import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    static let rLaunchPadHideRequested = Notification.Name("RLaunchPad.HideRequested")
    static let rLaunchPadWillHide = Notification.Name("RLaunchPad.WillHide")
    static let rLaunchPadWindowDiscovered = Notification.Name("RLaunchPad.WindowDiscovered")
    static let rLaunchPadActivateExistingInstance = Notification.Name("RLaunchPad.ActivateExistingInstance")
}

@main
struct RLaunchPadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("RLaunchPad", id: "main-window") {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .pasteboard) {}
            CommandGroup(replacing: .undoRedo) {}
            CommandGroup(replacing: .appTermination) {
                Button("隐藏 RLaunchPad") {
                    appDelegate.hideLaunchPad(nil)
                }
                .keyboardShortcut("q")
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow?

    private var statusItem: NSStatusItem?
    private var hotKeyHandlerRef: EventHandlerRef?
    private var toggleHotKeyRef: EventHotKeyRef?
    private var activeHotKeyCandidate: GlobalHotKeyCandidate?
    private var allowTermination = false

    private let hotKeySignature: OSType = 0x514C5044 // "RLPD"
    private let toggleHotKeyID: UInt32 = 1
    private var configuredWindowIdentity: ObjectIdentifier?
    private let hotKeyCandidates: [GlobalHotKeyCandidate] = [
        GlobalHotKeyCandidate(
            keyCode: UInt32(kVK_ANSI_Backslash),
            keyEquivalent: "\\",
            modifierMask: [.control, .option],
            carbonModifiers: UInt32(controlKey | optionKey),
            display: "⌃⌥\\"
        ),
        GlobalHotKeyCandidate(
            keyCode: UInt32(kVK_ANSI_Semicolon),
            keyEquivalent: ";",
            modifierMask: [.control, .option],
            carbonModifiers: UInt32(controlKey | optionKey),
            display: "⌃⌥;"
        ),
        GlobalHotKeyCandidate(
            keyCode: UInt32(kVK_ANSI_Quote),
            keyEquivalent: "'",
            modifierMask: [.control, .option],
            carbonModifiers: UInt32(controlKey | optionKey),
            display: "⌃⌥'"
        ),
        GlobalHotKeyCandidate(
            keyCode: UInt32(kVK_ANSI_Backslash),
            keyEquivalent: "\\",
            modifierMask: [.control, .option, .command],
            carbonModifiers: UInt32(controlKey | optionKey | cmdKey),
            display: "⌃⌥⌘\\"
        )
    ]
    private lazy var appVersionDisplay: String = {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (shortVersion, build) {
        case let (.some(short), .some(build)) where short != build:
            return "\(short) (\(build))"
        case let (.some(short), _):
            return short
        case let (_, .some(build)):
            return build
        default:
            return "Unknown"
        }
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if redirectToExistingInstanceIfNeeded() {
            return
        }

        // Menubar-style resident app.
        NSApp.setActivationPolicy(.accessory)

        registerGlobalHotKeys()
        setupStatusItem()
        setupNotifications()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.attachAndConfigureMainWindowIfNeeded()
            self.hideLaunchPad(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let toggleHotKeyRef {
            UnregisterEventHotKey(toggleHotKeyRef)
        }
        if let hotKeyHandlerRef {
            RemoveEventHandler(hotKeyHandlerRef)
        }
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app alive in background.
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard allowTermination else {
            hideLaunchPad(nil)
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showLaunchPad(nil)
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideLaunchPad(nil)
        return false
    }

    @objc func showLaunchPad(_ sender: Any?) {
        showLaunchPadInternal(retryCount: 0, forceSwitchSpace: false)
    }

    @objc func hideLaunchPad(_ sender: Any?) {
        attachAndConfigureMainWindowIfNeeded()
        NotificationCenter.default.post(name: .rLaunchPadWillHide, object: nil)
        window?.orderOut(nil)
    }

    @objc func toggleLaunchPad(_ sender: Any?) {
        attachAndConfigureMainWindowIfNeeded()
        if window?.isVisible == true {
            hideLaunchPad(nil)
        } else {
            showLaunchPad(nil)
        }
    }

    @objc func quitApp(_ sender: Any?) {
        allowTermination = true
        NSApp.terminate(nil)
    }

    private func attachAndConfigureMainWindowIfNeeded(retryCount: Int = 0) {
        if let existing = window, isLaunchPadWindowCandidate(existing) {
            configureMainWindow(existing)
            pruneDuplicateLaunchPadWindows(keeping: existing)
            return
        }

        if let target = NSApp.windows.reversed().first(where: { isLaunchPadWindowCandidate($0) }) {
            window = target
            configureMainWindow(target)
            pruneDuplicateLaunchPadWindows(keeping: target)
            return
        }

        guard retryCount < 6 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.attachAndConfigureMainWindowIfNeeded(retryCount: retryCount + 1)
        }
    }

    private func showLaunchPadInternal(retryCount: Int, forceSwitchSpace: Bool) {
        attachAndConfigureMainWindowIfNeeded()
        guard let window else {
            guard retryCount < 8 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.showLaunchPadInternal(
                    retryCount: retryCount + 1,
                    forceSwitchSpace: forceSwitchSpace
                )
            }
            return
        }

        if forceSwitchSpace {
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.orderFrontRegardless()
        }

        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func configureMainWindow(_ window: NSWindow) {
        let identity = ObjectIdentifier(window)
        if configuredWindowIdentity != identity {
            configuredWindowIdentity = identity

            window.delegate = self
            window.isReleasedWhenClosed = false
            window.styleMask.insert(.fullSizeContentView)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .floating
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .stationary]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
        }

        if let screen = NSScreen.main, window.frame != screen.frame {
            window.setFrame(screen.frame, display: true)
        }
    }

    private func isLaunchPadWindowCandidate(_ candidate: NSWindow) -> Bool {
        !isStatusOrMenuWindow(candidate) && candidate.contentView != nil
    }

    private func pruneDuplicateLaunchPadWindows(keeping keepWindow: NSWindow) {
        let duplicates = NSApp.windows.filter { candidate in
            candidate !== keepWindow && isLaunchPadWindowCandidate(candidate)
        }
        duplicates.forEach { $0.orderOut(nil) }
    }

    private func isStatusOrMenuWindow(_ candidate: NSWindow) -> Bool {
        if candidate == statusItem?.button?.window {
            return true
        }

        let className = NSStringFromClass(type(of: candidate))
        if className.contains("NSStatusBarWindow")
            || className.contains("NSMenuWindow")
            || className.contains("NSCarbonMenuWindow")
        {
            return true
        }

        if candidate.level == .statusBar {
            return true
        }

        return false
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = menuBarIconImage()
            button.imageScaling = .scaleProportionallyUpOrDown
            if let activeHotKeyCandidate {
                button.toolTip = "RLaunchPad \(appVersionDisplay) (\(activeHotKeyCandidate.display))"
            } else {
                button.toolTip = "RLaunchPad \(appVersionDisplay)"
            }
        }

        let menu = NSMenu()

        let toggleItem = NSMenuItem(
            title: "切换 LaunchPad",
            action: #selector(toggleLaunchPadFromMenu(_:)),
            keyEquivalent: activeHotKeyCandidate?.keyEquivalent ?? ""
        )
        toggleItem.keyEquivalentModifierMask = activeHotKeyCandidate?.modifierMask ?? []
        menu.addItem(toggleItem)

        menu.addItem(.separator())
        let aboutItem = NSMenuItem(title: "About RLaunchPad", action: #selector(showAboutPanel(_:)), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitAppFromMenu(_:)), keyEquivalent: "")
        quitItem.keyEquivalentModifierMask = []
        quitItem.target = self
        menu.addItem(quitItem)

        toggleItem.target = self

        item.menu = menu
        statusItem = item
    }

    private func menuBarIconImage() -> NSImage {
        let icon = (
            NSImage(named: NSImage.Name("MenuBarIcon"))?.copy() as? NSImage
            ?? NSApp.applicationIconImage.copy() as? NSImage
            ?? NSImage()
        )
        icon.size = NSSize(width: 18, height: 18)
        icon.isTemplate = false
        return icon
    }

    @objc private func toggleLaunchPadFromMenu(_ sender: Any?) {
        statusItem?.menu?.cancelTrackingWithoutAnimation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.toggleLaunchPad(nil)
        }
    }

    @objc private func quitAppFromMenu(_ sender: Any?) {
        DispatchQueue.main.async { [weak self] in
            self?.quitApp(nil)
        }
    }

    @objc private func showAboutPanel(_ sender: Any?) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "RLaunchPad"
        alert.informativeText = "Version \(appVersionDisplay)"
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hideLaunchPad(_:)),
            name: .rLaunchPadHideRequested,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDiscovered(_:)),
            name: .rLaunchPadWindowDiscovered,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleActivateExistingInstance(_:)),
            name: .rLaunchPadActivateExistingInstance,
            object: Bundle.main.bundleIdentifier,
            suspensionBehavior: .deliverImmediately
        )
    }

    @objc private func handleWindowDiscovered(_ notification: Notification) {
        guard let discoveredWindow = notification.object as? NSWindow else { return }
        guard !isStatusOrMenuWindow(discoveredWindow) else { return }
        if window === discoveredWindow { return }

        window = discoveredWindow
        DispatchQueue.main.async { [weak self] in
            self?.configureMainWindow(discoveredWindow)
        }
    }

    @objc private func handleActivateExistingInstance(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.showLaunchPadInternal(retryCount: 0, forceSwitchSpace: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.showLaunchPadInternal(retryCount: 0, forceSwitchSpace: true)
            }
        }
    }

    private func redirectToExistingInstanceIfNeeded() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let otherInstances = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != currentPID }

        guard let existing = otherInstances.first else { return false }

        existing.activate(options: [.activateAllWindows])
        DistributedNotificationCenter.default().postNotificationName(
            .rLaunchPadActivateExistingInstance,
            object: bundleID,
            userInfo: ["sourcePID": "\(currentPID)"],
            deliverImmediately: true
        )
        NSApp.terminate(nil)
        return true
    }

    private func registerGlobalHotKeys() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, eventRef, userData in
                guard let userData else { return noErr }
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                return appDelegate.handleHotKeyEvent(eventRef)
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyHandlerRef
        )
        if installStatus != noErr {
            print("InstallEventHandler failed: \(installStatus)")
        }

        for candidate in hotKeyCandidates {
            let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: toggleHotKeyID)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                candidate.keyCode,
                candidate.carbonModifiers,
                hotKeyID,
                GetEventDispatcherTarget(),
                0,
                &ref
            )

            if status == noErr, let ref {
                toggleHotKeyRef = ref
                activeHotKeyCandidate = candidate
                print("Registered RLaunchPad hot key: \(candidate.display)")
                return
            }
        }

        print("Failed to register any RLaunchPad hot key candidate")
    }

    private func handleHotKeyEvent(_ eventRef: EventRef?) -> OSStatus {
        guard let eventRef else { return noErr }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else { return status }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch hotKeyID.id {
            case self.toggleHotKeyID:
                self.toggleLaunchPad(nil)
            default:
                break
            }
        }

        return noErr
    }
}

private struct GlobalHotKeyCandidate {
    let keyCode: UInt32
    let keyEquivalent: String
    let modifierMask: NSEvent.ModifierFlags
    let carbonModifiers: UInt32
    let display: String
}
