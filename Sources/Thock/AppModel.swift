import AppKit
import Carbon
import CoreAudio
import Observation
import os
import ServiceManagement
import ThockCore

@Observable
final class AppModel {
    enum CaptureState {
        case needsPermission
        case running
        case failed
        case benchmark
    }

    static let defaultPackID = "holypanda"

    private(set) var captureState: CaptureState = .needsPermission
    private(set) var outputs: [OutputDevice] = []
    private(set) var packs: [PackEntry] = []
    private(set) var muteReasons: MuteReasons = []
    private(set) var secureInputActive = false
    private(set) var loginItemStatus = SMAppService.mainApp.status
    private(set) var loginItemError: String?
    private(set) var hotKeyError: String?
    private(set) var packError: String?
    private(set) var excludedFrontAppName: String?
    let isProbe: Bool

    var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Keys.enabled)
            signals.enabled = enabled
        }
    }

    var muteRules: MuteRules {
        didSet {
            UserDefaults.standard.set(muteRules.microphoneInUse, forKey: Keys.muteOnMicrophone)
            UserDefaults.standard.set(muteRules.excludedApp, forKey: Keys.muteOnExcludedApp)
            UserDefaults.standard.set(muteRules.systemOutputMuted, forKey: Keys.muteOnSystemOutput)
            updateMicrophoneMonitor()
            applyMute()
        }
    }

    var excludedBundleIDs: [String] {
        didSet {
            UserDefaults.standard.set(excludedBundleIDs, forKey: Keys.excludedApps)
            applyExclusions()
        }
    }

    private(set) var hotKey: KeyCombo

    var includeSynthetic: Bool {
        didSet {
            UserDefaults.standard.set(includeSynthetic, forKey: Keys.includeSynthetic)
            pipeline.setIncludeSynthetic(includeSynthetic)
        }
    }

    var packID: String {
        didSet {
            UserDefaults.standard.set(packID, forKey: Keys.pack)
            packError = nil
            if packID == loadedPackID {
                packLoad?.cancel()
            } else {
                loadPack()
            }
        }
    }

    var volume: Double {
        didSet {
            UserDefaults.standard.set(volume, forKey: Keys.volume)
            audio.setVolume(Float(volume))
        }
    }

    var spatialization: Bool {
        didSet {
            UserDefaults.standard.set(spatialization, forKey: Keys.spatialization)
            audio.setSpatialization(spatialization)
        }
    }

    var mouseSounds: Bool {
        didSet {
            UserDefaults.standard.set(mouseSounds, forKey: Keys.mouseSounds)
            audio.setMouseSounds(mouseSounds)
        }
    }

    var outputUID: String? {
        didSet {
            UserDefaults.standard.set(outputUID, forKey: Keys.output)
            audio.setOutputDevice(uid: outputUID)
            outputMonitor?.refresh()
            microphoneMonitor?.refresh()
        }
    }

    private var selectedOutputDevice: AudioDeviceID? {
        outputUID.flatMap(OutputDevices.device(uid:)) ?? OutputDevices.defaultOutput
    }

    var measuringLatency: Bool {
        didSet { audio.setLatencyMeasurement(measuringLatency) }
    }

    @ObservationIgnored private var signals = MuteSignals() {
        didSet { applyMute() }
    }
    @ObservationIgnored private var frontApp: (bundleID: String?, name: String?) = (nil, nil)
    @ObservationIgnored let packLibrary: PackLibrary
    @ObservationIgnored let windows = WindowPresenter()
    @ObservationIgnored private let audio: AudioEngine
    @ObservationIgnored private let pipeline: InputPipeline
    @ObservationIgnored private let tapLocation: EventTap.Location
    @ObservationIgnored private var tap: EventTap?
    @ObservationIgnored private var bench: TypingBench?
    @ObservationIgnored private var systemEvents: SystemEvents?
    @ObservationIgnored private var outputMonitor: OutputDeviceMonitor?
    @ObservationIgnored private var microphoneMonitor: MicrophoneMonitor?
    @ObservationIgnored private var hotKeyRegistration: HotKey?
    @ObservationIgnored private var permissionWait: Task<Void, Never>?
    @ObservationIgnored private var packLoad: Task<Void, Never>?
    @ObservationIgnored private var loadedPackID: String?
    @ObservationIgnored private var secureInputTimer: Timer?
    @ObservationIgnored private var workspaceObserver: NSObjectProtocol?
    @ObservationIgnored private let logger = Logger(subsystem: "com.louis.thock", category: "bench")

    private enum Keys {
        static let enabled = "enabled"
        static let includeSynthetic = "includeSyntheticInput"
        static let pack = "pack"
        static let volume = "volume"
        static let spatialization = "spatialization"
        static let mouseSounds = "mouseSounds"
        static let output = "outputDeviceUID"
        static let hotKey = "hotKey"
        static let muteOnMicrophone = "muteOnMicrophone"
        static let muteOnExcludedApp = "muteOnExcludedApp"
        static let muteOnSystemOutput = "muteOnSystemOutputMuted"
        static let excludedApps = "excludedBundleIDs"
    }

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        func value(after flag: String) -> String? {
            arguments.firstIndex(of: flag).map { $0 + 1 }.flatMap { arguments.indices.contains($0) ? arguments[$0] : nil }
        }
        isProbe = arguments.contains("--probe")
        tapLocation = value(after: "--tap-level") == "hid" ? .hid : .session
        let benchDuration = arguments.contains("--bench-typing") ? Double(value(after: "--bench-typing") ?? "") ?? 20 : nil

        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Keys.enabled: true, Keys.pack: Self.defaultPackID, Keys.volume: 0.8, Keys.spatialization: true,
            Keys.muteOnMicrophone: true, Keys.muteOnExcludedApp: true, Keys.muteOnSystemOutput: true,
        ])
        let includeSynthetic = defaults.bool(forKey: Keys.includeSynthetic)
        self.includeSynthetic = includeSynthetic
        enabled = defaults.bool(forKey: Keys.enabled)
        var rules = MuteRules()
        rules.microphoneInUse = defaults.bool(forKey: Keys.muteOnMicrophone)
        rules.excludedApp = defaults.bool(forKey: Keys.muteOnExcludedApp)
        rules.systemOutputMuted = defaults.bool(forKey: Keys.muteOnSystemOutput)
        muteRules = rules
        excludedBundleIDs = defaults.stringArray(forKey: Keys.excludedApps) ?? []
        hotKey = defaults.data(forKey: Keys.hotKey).flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) } ?? .defaultToggle
        volume = defaults.double(forKey: Keys.volume)
        spatialization = defaults.bool(forKey: Keys.spatialization)
        mouseSounds = defaults.bool(forKey: Keys.mouseSounds)
        outputUID = defaults.string(forKey: Keys.output)
        measuringLatency = arguments.contains("--measure-latency") || benchDuration != nil

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        packLibrary = PackLibrary(bundledRoot: Bundle.main.url(forResource: "Packs", withExtension: nil),
                                  importedRoot: support.appendingPathComponent("Packs", isDirectory: true))
        let available = packLibrary.all()
        packs = available
        let storedPackID = defaults.string(forKey: Keys.pack)
        packID = available.contains { $0.id == storedPackID } ? storedPackID ?? Self.defaultPackID : Self.defaultPackID

        let queue = DispatchQueue(label: "com.louis.thock.audio", qos: .userInteractive)
        let audio = AudioEngine(queue: queue)
        self.audio = audio
        pipeline = InputPipeline(queue: queue, filter: SourceFilter(includeSynthetic: includeSynthetic), probe: isProbe) { trigger, timestamp in
            audio.play(trigger, eventTimestamp: timestamp)
        }

        audio.setVolume(Float(volume))
        audio.setSpatialization(spatialization)
        audio.setMouseSounds(mouseSounds)
        audio.setLatencyMeasurement(measuringLatency)
        audio.setOutputDevice(uid: outputUID)
        audio.start()
        loadPack()

        let outputMonitor = OutputDeviceMonitor(
            outputDevice: { [weak self] in self?.selectedOutputDevice },
            onDevicesChanged: { [weak self] in
                guard let self else { return }
                outputs = OutputDevices.all()
                audio.refreshRoute()
                microphoneMonitor?.refresh()
            },
            onSystemMuteChanged: { [weak self] muted in
                self?.signals.systemOutputMuted = muted
            })
        outputs = OutputDevices.all()
        outputMonitor.start()
        self.outputMonitor = outputMonitor

        let systemEvents = SystemEvents { [weak self] event in self?.handle(event) }
        systemEvents.start()
        self.systemEvents = systemEvents

        signals.enabled = enabled
        updateMicrophoneMonitor()
        watchFrontmostApp()
        watchSecureInput()
        let hotKeyRegistration = HotKey { [weak self] in self?.enabled.toggle() }
        self.hotKeyRegistration = hotKeyRegistration
        if !hotKeyRegistration.register(hotKey) {
            hotKeyError = "Le raccourci \(hotKey.displayString) est déjà pris par une autre app."
        }

        if let benchDuration {
            startBench(duration: benchDuration)
        } else {
            startCapture()
        }
        if arguments.contains("--snapshot") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { Snapshots.write(model: self) }
        }
    }

    var stats: InputStats { pipeline.stats }
    var audioStats: AudioStats { audio.stats }

    var menuBarSymbol: String {
        switch captureState {
        case .needsPermission, .failed: "keyboard.badge.ellipsis"
        case .running, .benchmark: muteReasons.isEmpty ? "keyboard" : "speaker.slash"
        }
    }

    func showOnboarding() {
        windows.show(.onboarding, title: "Bienvenue dans Thock") { OnboardingView(model: self) }
    }

    func showSettings() {
        windows.show(.settings, title: "Réglages de Thock") { SettingsView(model: self) }
    }

    func requestPermission() {
        Permissions.requestInputMonitoring()
        Permissions.openInputMonitoringSettings()
        waitForPermission()
    }

    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
        }
    }

    private func startCapture() {
        guard Permissions.isInputMonitoringGranted else {
            captureState = .needsPermission
            waitForPermission()
            DispatchQueue.main.async { self.showOnboarding() }
            return
        }
        let tap = EventTap(ring: pipeline.ring, wake: pipeline.wakeSource, location: tapLocation) { [weak self] in
            DispatchQueue.main.async { self?.permissionLost() }
        }
        if tap.start() {
            self.tap = tap
            captureState = .running
        } else {
            captureState = .failed
        }
    }

    private func permissionLost() {
        guard let tap else { return }
        tap.stop()
        self.tap = nil
        pipeline.reset()
        captureState = .needsPermission
        waitForPermission()
        showOnboarding()
    }

    private func waitForPermission() {
        guard permissionWait == nil else { return }
        permissionWait = Task { [weak self] in
            let granted = await Permissions.waitForInputMonitoring()
            guard let self else { return }
            permissionWait = nil
            if granted { startCapture() }
        }
    }

    func suspendHotKey() {
        hotKeyRegistration?.unregister()
    }

    func resumeHotKey() {
        hotKeyRegistration?.register(hotKey)
    }

    @discardableResult
    func setHotKey(_ combo: KeyCombo) -> Bool {
        guard let hotKeyRegistration else { return false }
        guard hotKeyRegistration.register(combo) else {
            hotKeyError = "\(combo.displayString) est déjà utilisé par une autre app ou par macOS."
            hotKeyRegistration.register(hotKey)
            return false
        }
        hotKey = combo
        hotKeyError = nil
        UserDefaults.standard.set(try? JSONEncoder().encode(combo), forKey: Keys.hotKey)
        return true
    }

    var launchAtLogin: Bool {
        get { loginItemStatus == .enabled || loginItemStatus == .requiresApproval }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                loginItemError = nil
            } catch {
                loginItemError = error.localizedDescription
            }
            refreshLoginItemStatus()
        }
    }

    func refreshLoginItemStatus() {
        let status = SMAppService.mainApp.status
        if status != loginItemStatus { loginItemStatus = status }
    }

    private func applyMute() {
        let reasons = signals.reasons(under: muteRules)
        guard reasons != muteReasons else { return }
        muteReasons = reasons
        audio.setMuted(reasons)
    }

    private func updateMicrophoneMonitor() {
        if muteRules.microphoneInUse {
            guard microphoneMonitor == nil else { return }
            let monitor = MicrophoneMonitor(outputDevice: { [weak self] in self?.selectedOutputDevice }, onChange: { [weak self] inUse in
                self?.signals.microphoneInUse = inUse
            })
            microphoneMonitor = monitor
            monitor.start()
        } else {
            microphoneMonitor?.stop()
            microphoneMonitor = nil
            signals.microphoneInUse = false
        }
    }

    private func watchFrontmostApp() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let snapshot = app.map { (bundleID: $0.bundleIdentifier, name: $0.localizedName) }
            MainActor.assumeIsolated { self?.updateFrontmostApp(bundleID: snapshot?.bundleID, name: snapshot?.name) }
        }
        updateFrontmostApp(NSWorkspace.shared.frontmostApplication)
    }

    private func updateFrontmostApp(_ app: NSRunningApplication?) {
        updateFrontmostApp(bundleID: app?.bundleIdentifier, name: app?.localizedName)
    }

    private func updateFrontmostApp(bundleID: String?, name: String?) {
        guard bundleID != Bundle.main.bundleIdentifier else { return }
        frontApp = (bundleID, name)
        applyExclusions()
    }

    private func applyExclusions() {
        let excluded = frontApp.bundleID.map(excludedBundleIDs.contains) ?? false
        let name = excluded ? (frontApp.name ?? frontApp.bundleID) : nil
        if name != excludedFrontAppName { excludedFrontAppName = name }
        signals.excludedAppInFront = excluded
    }

    func excludeApp(bundleID: String) {
        guard !excludedBundleIDs.contains(bundleID), bundleID != Bundle.main.bundleIdentifier else { return }
        excludedBundleIDs.append(bundleID)
    }

    func removeExcludedApp(bundleID: String) {
        excludedBundleIDs.removeAll { $0 == bundleID }
    }

    func chooseAppToExclude() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Exclure"
        panel.message = "Thock se taira quand cette app est au premier plan."
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        excludeApp(bundleID: bundleID)
    }

    private func watchSecureInput() {
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollSecureInput() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        secureInputTimer = timer
        pollSecureInput()
    }

    private func pollSecureInput() {
        let active = IsSecureEventInputEnabled()
        if active != secureInputActive { secureInputActive = active }
    }

    func importPack(from url: URL) async throws {
        let library = packLibrary
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let entry = try await Task.detached(priority: .userInitiated) { try library.importPack(from: url) }.value
        packs = packLibrary.all()
        packID = entry.id
    }

    func deletePack(_ entry: PackEntry) throws {
        try packLibrary.delete(entry)
        packs = packLibrary.all()
        if packID == entry.id { packID = Self.defaultPackID }
    }

    private func loadPack() {
        guard let pack = packs.first(where: { $0.id == packID }) ?? packs.first(where: { $0.id == Self.defaultPackID }) ?? packs.first else { return }
        let audio = audio
        let (id, url, name) = (pack.id, pack.url, pack.info.name)
        packLoad?.cancel()
        packLoad = Task { [weak self] in
            do {
                let source = try await Task.detached(priority: .userInitiated) { try PackLoader.load(directory: url) }.value
                // A newer selection cancelled this load while it ran off the main actor; its result is stale.
                guard !Task.isCancelled, let self else { return }
                audio.setPack(source)
                loadedPackID = id
            } catch {
                guard !Task.isCancelled, let self else { return }
                Logger(subsystem: "com.louis.thock", category: "audio").error("Pack \(id, privacy: .public) failed to load: \(String(describing: error), privacy: .public)")
                // Point the selection back at the pack the engine still plays, so the UI never shows a pack it isn't playing.
                if let fallback = loadedPackID ?? (id == Self.defaultPackID ? nil : Self.defaultPackID) {
                    packID = fallback
                }
                let reason = (error as? PackLoaderError).flatMap { PackImportError.invalid($0).errorDescription } ?? error.localizedDescription
                packError = "Le pack « \(name) » n'a pas pu être chargé. \(reason)"
            }
        }
    }

    private func handle(_ event: SystemEvents.Event) {
        pipeline.reset()
        switch event {
        case .willSleep: audio.setSuspended(.sleep, true)
        case .didWake: audio.setSuspended(.sleep, false)
        case .screenLocked: audio.setSuspended(.screenLocked, true)
        case .screenUnlocked: audio.setSuspended(.screenLocked, false)
        case .sessionResignedActive: audio.setSuspended(.sessionInactive, true)
        case .sessionBecameActive: audio.setSuspended(.sessionInactive, false)
        }
    }

    private func startBench(duration: Double) {
        captureState = .benchmark
        let bench = TypingBench(ring: pipeline.ring, wake: pipeline.wakeSource)
        self.bench = bench
        let audio = audio
        let logger = logger
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            logger.notice("Bench started: \(TypingBench.eventsPerSecond, privacy: .public) events/s for \(duration, privacy: .public) s")
            bench.start(duration: duration) {
                audio.queue.async {
                    let stats = audio.stats
                    logger.notice("Bench done: played=\(stats.played, privacy: .public) p50=\(stats.latencyP50Us ?? -1, privacy: .public)us p99=\(stats.latencyP99Us ?? -1, privacy: .public)us samples=\(stats.latencySamples, privacy: .public) stale=\(stats.stale, privacy: .public) late=\(stats.late, privacy: .public) stolen=\(stats.stolen, privacy: .public) invalid=\(stats.invalidTimestamps, privacy: .public) io=\(stats.ioBufferFrames, privacy: .public) outputLatency=\(stats.outputLatencyMs, privacy: .public)ms")
                }
            }
        }
    }
}
