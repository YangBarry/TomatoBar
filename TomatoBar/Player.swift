import AppKit
import AVFoundation
import CoreAudio
import SwiftUI

enum BackgroundAudioMode: String, CaseIterable, Identifiable {
    case brownNoise = "brown_noise"
    case lofiRadio = "lofi_radio"
    case none = "none"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .brownNoise:
            return "Brown Noise"
        case .lofiRadio:
            return "Lofi Hip Hop"
        case .none:
            return "无背景音"
        }
    }
}

enum LofiSourceMode: String, CaseIterable, Identifiable {
    case appleMusic = "apple_music"
    case offline = "offline"

    var id: String { rawValue }
}

/// Real-time Academic Brown Noise DSP Synthesizer
/// Models the Mindful Frequencies Lab "Academic Brown Noise" acoustic profile:
/// - True -6 dB/octave (1/f^2) Brownian integration down to 20 Hz
/// - 22 Hz high-pass infrasonic/DC blocker for tight, clean sub-bass
/// - Dual-stage velvet low-pass shaping (460 Hz warmth + 1.35 kHz air rolloff) to eliminate high-frequency static hiss
/// - Mid/Side stereo coherence (80% centered grounding bass + 20% spacious stereo field for headphone comfort)
final class AcademicBrownNoiseSynth {
    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var configObserver: NSObjectProtocol?

    private var isRunning: Bool = false
    private var targetVolume: Float = 0.7
    private var currentEnvelope: Float = 0.0

    private var rngState: UInt64 = 0x9E3779B97F4A7C15
    private var brownM: Float = 0.0
    private var brownS: Float = 0.0
    private var hpInPrevM: Float = 0.0
    private var hpOutPrevM: Float = 0.0
    private var hpInPrevS: Float = 0.0
    private var hpOutPrevS: Float = 0.0
    private var lp1M: Float = 0.0
    private var lp2M: Float = 0.0
    private var lp1S: Float = 0.0
    private var lp2S: Float = 0.0

    init() {
        rngState = UInt64(bitPattern: Int64(Date().timeIntervalSince1970 * 1_000_000)) ^ 0x853C49E6748FEA9B
        if rngState == 0 {
            rngState = 0x2545F4914F6CDD1D
        }
    }

    deinit {
        stop()
    }

    func setVolume(_ volume: Double) {
        targetVolume = Float(max(0.0, min(volume, 1.5)))
    }

    @inline(__always)
    private func nextGaussianWhite() -> Float {
        var sum: Float = 0.0
        for _ in 0..<4 {
            rngState ^= rngState >> 12
            rngState ^= rngState << 25
            rngState ^= rngState >> 27
            let raw = rngState &* 0x2545F4914F6CDD1D
            let u = Float(Int32(bitPattern: UInt32(truncatingIfNeeded: raw >> 32))) / Float(Int32.max)
            sum += u
        }
        return sum * 0.5
    }

    func start(volume: Double) {
        setVolume(volume)
        if isRunning, let engine = engine, engine.isRunning {
            return
        }
        setupAndStartEngine()
    }

    private func setupAndStartEngine() {
        stopEngineOnly()

        let audioEngine = AVAudioEngine()
        let outputNode = audioEngine.outputNode
        let hwFormat = outputNode.inputFormat(forBus: 0)
        let sampleRate = hwFormat.sampleRate > 0 ? hwFormat.sampleRate : 48000.0

        guard let renderFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        ) else {
            return
        }

        let fs = Float(sampleRate)
        let twoPi = Float.pi * 2.0

        let pole20Hz = exp(-twoPi * 20.0 / fs)
        let normIntegrator = sqrt(1.0 - pole20Hz * pole20Hz)
        let hpR = exp(-twoPi * 22.0 / fs)

        let lpAlpha1 = 1.0 - exp(-twoPi * 460.0 / fs)
        let lpAlpha2 = 1.0 - exp(-twoPi * 1350.0 / fs)

        let envStep = 1.0 / (0.4 * fs)
        currentEnvelope = 0.0

        let node = AVAudioSourceNode(format: renderFormat) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard ablPointer.count >= 2,
                  let leftBuf = ablPointer[0].mData?.assumingMemoryBound(to: Float.self),
                  let rightBuf = ablPointer[1].mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }

            let frames = Int(frameCount)
            let vol = self.targetVolume

            for i in 0..<frames {
                if self.currentEnvelope < 1.0 {
                    self.currentEnvelope = min(1.0, self.currentEnvelope + envStep)
                }

                let wM = self.nextGaussianWhite()
                let wS = self.nextGaussianWhite()

                self.brownM = pole20Hz * self.brownM + normIntegrator * wM
                self.brownS = pole20Hz * self.brownS + normIntegrator * wS

                let hpM = hpR * (self.hpOutPrevM + self.brownM - self.hpInPrevM)
                self.hpInPrevM = self.brownM
                self.hpOutPrevM = hpM

                let hpS = hpR * (self.hpOutPrevS + self.brownS - self.hpInPrevS)
                self.hpInPrevS = self.brownS
                self.hpOutPrevS = hpS

                self.lp1M += lpAlpha1 * (hpM - self.lp1M)
                self.lp2M += lpAlpha2 * (self.lp1M - self.lp2M)

                self.lp1S += lpAlpha1 * (hpS - self.lp1S)
                self.lp2S += lpAlpha2 * (self.lp1S - self.lp2S)

                let shapedMid = 0.80 * self.lp2M + 0.20 * hpM
                let shapedSide = 0.85 * self.lp2S + 0.15 * hpS

                let gain = vol * self.currentEnvelope * 0.42
                let rawL = (shapedMid + 0.20 * shapedSide) * gain
                let rawR = (shapedMid - 0.20 * shapedSide) * gain

                leftBuf[i] = tanh(rawL)
                rightBuf[i] = tanh(rawR)
            }

            return noErr
        }

        audioEngine.attach(node)
        audioEngine.connect(node, to: audioEngine.mainMixerNode, format: renderFormat)

        do {
            try audioEngine.start()
            self.engine = audioEngine
            self.sourceNode = node
            self.isRunning = true

            configObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: audioEngine,
                queue: .main
            ) { [weak self] _ in
                guard let self = self, self.isRunning else { return }
                self.setupAndStartEngine()
            }
        } catch {
            print("Failed to start AcademicBrownNoiseSynth: \(error)")
        }
    }

    private func stopEngineOnly() {
        if let obs = configObserver {
            NotificationCenter.default.removeObserver(obs)
            configObserver = nil
        }
        engine?.stop()
        if let node = sourceNode {
            engine?.detach(node)
        }
        sourceNode = nil
        engine = nil
    }

    func stop() {
        isRunning = false
        stopEngineOnly()
    }
}

class TBPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private var windupSound: AVAudioPlayer?
    private var dingSound: AVAudioPlayer?
    private var tickingSound: AVAudioPlayer?
    private var customFilePlayer: AVAudioPlayer?
    private let academicBrownSynth = AcademicBrownNoiseSynth()

    // Apple Music Official Lofi Girl Playlist URL
    public let appleMusicPlaylistURL = URL(string: "music://music.apple.com/us/playlist/lofi-girl-beats-to-relax-study-to/pl.bf7a3cbca49644d8a33f09c1285aef5c")!
    private let appleScriptQueue = DispatchQueue(label: "com.tomatobar.applescript", qos: .userInitiated)

    // Offline Lofi playlist player
    public let lofiDirectoryURL: URL
    private var offlineLofiFiles: [URL] = []
    private var currentLofiTrackIndex: Int = 0
    private var offlineLofiPlayer: AVAudioPlayer?

    // CoreAudio output device monitoring for headphone auto-pause / auto-resume
    private var defaultOutputListenerBlock: AudioObjectPropertyListenerBlock?
    private var devicesListenerBlock: AudioObjectPropertyListenerBlock?
    private var dataSourceListenerBlock: AudioObjectPropertyListenerBlock?
    private var observedDataSourceDeviceID: AudioDeviceID = 0
    private var lastOutputDeviceID: AudioDeviceID = 0
    private var lastOutputWasHeadphones: Bool = false
    private var pendingHeadphoneResumeWorkItems: [DispatchWorkItem] = []

    @Published var isBackgroundAudioActive: Bool = false
    @Published var lofiStatusText: String = ""

    @AppStorage("backgroundAudioMode") var audioModeRaw: String = BackgroundAudioMode.brownNoise.rawValue {
        didSet {
            if isBackgroundAudioActive {
                restartBackgroundAudio()
            } else {
                updateLofiStatusLabel()
            }
        }
    }

    @AppStorage("lofiSourceMode") var lofiSourceRaw: String = LofiSourceMode.appleMusic.rawValue {
        didSet {
            if isBackgroundAudioActive && audioMode == .lofiRadio {
                restartBackgroundAudio()
            } else {
                updateLofiStatusLabel()
            }
        }
    }

    var audioMode: BackgroundAudioMode {
        get { BackgroundAudioMode(rawValue: audioModeRaw) ?? .brownNoise }
        set { audioModeRaw = newValue.rawValue }
    }

    var lofiSource: LofiSourceMode {
        get { LofiSourceMode(rawValue: lofiSourceRaw) ?? .appleMusic }
        set { lofiSourceRaw = newValue.rawValue }
    }

    @AppStorage("musicVolume") var musicVolume: Double = 0.7 {
        didSet {
            updateBackgroundVolume()
        }
    }

    @AppStorage("customBrownNoisePath") var customBrownNoisePath: String = "" {
        didSet {
            prepareCustomBrownNoisePlayer()
            if isBackgroundAudioActive && audioMode == .brownNoise {
                startBrownNoise()
            }
        }
    }

    @AppStorage("windupVolume") var windupVolume: Double = 0.6 {
        didSet {
            setVolume(windupSound, windupVolume)
        }
    }
    @AppStorage("dingVolume") var dingVolume: Double = 1.0 {
        didSet {
            setVolume(dingSound, dingVolume)
        }
    }
    @AppStorage("tickingVolume") var tickingVolume: Double = 0.0 {
        didSet {
            setVolume(tickingSound, tickingVolume)
        }
    }

    private func setVolume(_ sound: AVAudioPlayer?, _ volume: Double) {
        sound?.setVolume(Float(volume), fadeDuration: 0)
    }

    private func updateBackgroundVolume() {
        academicBrownSynth.setVolume(musicVolume)
        customFilePlayer?.setVolume(Float(musicVolume), fadeDuration: 0.1)
        offlineLofiPlayer?.setVolume(Float(musicVolume), fadeDuration: 0.1)
        if isBackgroundAudioActive && audioMode == .lofiRadio && lofiSource == .appleMusic {
            let volInt = max(0, min(100, Int((musicVolume / 1.0 * 100.0).rounded())))
            runMusicAppleScript("tell application \"Music\" to set sound volume to \(volInt)")
        }
    }

    override init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        lofiDirectoryURL = homeDir.appendingPathComponent(".tomatobar/lofi", isDirectory: true)
        super.init()

        windupSound = Self.loadAudioPlayer(name: "windup")
        dingSound = Self.loadAudioPlayer(name: "ding")
        tickingSound = Self.loadAudioPlayer(name: "ticking")

        windupSound?.prepareToPlay()
        dingSound?.prepareToPlay()
        tickingSound?.numberOfLoops = -1
        tickingSound?.prepareToPlay()

        setVolume(windupSound, windupVolume)
        setVolume(dingSound, dingVolume)
        setVolume(tickingSound, tickingVolume)

        prepareCustomBrownNoisePlayer()
        reloadOfflineLofiPlaylist()
        setupAudioOutputMonitoring()
    }

    deinit {
        teardownAudioOutputMonitoring()
    }

    private static func loadAudioPlayer(name: String) -> AVAudioPlayer? {
        let wav = AVFileType.wav.rawValue
        if let asset = NSDataAsset(name: name) {
            return try? AVAudioPlayer(data: asset.data, fileTypeHint: wav)
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "wav") {
            return try? AVAudioPlayer(contentsOf: url)
        }
        return nil
    }

    func reloadOfflineLofiPlaylist() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: lofiDirectoryURL.path) {
            try? fm.createDirectory(at: lofiDirectoryURL, withIntermediateDirectories: true)
        }
        let validExts: Set<String> = ["mp3", "m4a", "wav", "aac", "flac", "caf", "aiff"]
        if let urls = try? fm.contentsOfDirectory(at: lofiDirectoryURL, includingPropertiesForKeys: nil) {
            offlineLofiFiles = urls
                .filter { validExts.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        updateLofiStatusLabel()
    }

    private func updateLofiStatusLabel() {
        if lofiSource == .appleMusic {
            lofiStatusText = "Apple Music: Lofi Girl 官方歌单"
            return
        }
        if offlineLofiFiles.isEmpty {
            lofiStatusText = "未找到离线音频 (~/.tomatobar/lofi)"
        } else {
            let safeIdx = currentLofiTrackIndex % offlineLofiFiles.count
            let name = offlineLofiFiles[safeIdx].deletingPathExtension().lastPathComponent
            lofiStatusText = "离线 (\(safeIdx + 1)/\(offlineLofiFiles.count)): \(name)"
        }
    }

    private func prepareCustomBrownNoisePlayer() {
        customFilePlayer?.stop()
        customFilePlayer = nil

        if !customBrownNoisePath.isEmpty,
           FileManager.default.fileExists(atPath: customBrownNoisePath) {
            let fileURL = URL(fileURLWithPath: customBrownNoisePath)
            if let player = try? AVAudioPlayer(contentsOf: fileURL) {
                player.numberOfLoops = -1
                player.prepareToPlay()
                player.setVolume(Float(musicVolume), fadeDuration: 0)
                customFilePlayer = player
            }
        }
    }

    private func startBrownNoise() {
        if let customPlayer = customFilePlayer {
            academicBrownSynth.stop()
            customPlayer.setVolume(Float(musicVolume), fadeDuration: 0.2)
            customPlayer.play()
        } else {
            customFilePlayer?.stop()
            academicBrownSynth.start(volume: musicVolume)
        }
    }

    private func stopBrownNoise() {
        academicBrownSynth.stop()
        customFilePlayer?.stop()
    }

    func playWindup() {
        if windupVolume > 0 {
            windupSound?.play()
        }
    }

    func playDing() {
        if dingVolume > 0 {
            dingSound?.play()
        }
    }

    func startTicking() {
        if tickingVolume > 0 {
            tickingSound?.play()
        }
        startBackgroundAudio()
    }

    func stopTicking() {
        tickingSound?.stop()
        stopBackgroundAudio()
    }

    func startBackgroundAudio() {
        isBackgroundAudioActive = true
        if musicVolume <= 0.001 {
            stopBrownNoise()
            stopAllLofi()
            return
        }
        switch audioMode {
        case .brownNoise:
            stopAllLofi()
            startBrownNoise()
        case .lofiRadio:
            stopBrownNoise()
            if lofiSource == .appleMusic {
                pauseOfflineLofi()
                startAppleMusicLofi()
            } else {
                pauseAppleMusic()
                startOfflineLofi()
            }
        case .none:
            stopBrownNoise()
            stopAllLofi()
        }
    }

    func stopBackgroundAudio() {
        isBackgroundAudioActive = false
        cancelPendingHeadphoneResumes()
        stopBrownNoise()
        stopAllLofi()
    }

    private func stopAllLofi() {
        pauseOfflineLofi()
        pauseAppleMusic()
    }

    private func restartBackgroundAudio() {
        cancelPendingHeadphoneResumes()
        stopBrownNoise()
        stopAllLofi()
        if isBackgroundAudioActive {
            startBackgroundAudio()
        }
    }

    // MARK: - CoreAudio Headphone Route Monitoring

    private func setupAudioOutputMonitoring() {
        let currentID = Self.currentDefaultOutputDeviceID()
        lastOutputDeviceID = currentID
        lastOutputWasHeadphones = Self.isHeadphoneOutputDevice(currentID)
        attachDataSourceListener(for: currentID)

        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        let defaultOutListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.handleAudioOutputRouteChange(forceIfHeadphones: true)
            }
        }
        let devicesListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.handleAudioOutputRouteChange(forceIfHeadphones: false)
            }
        }
        defaultOutputListenerBlock = defaultOutListener
        devicesListenerBlock = devicesListener

        var defaultOutAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(systemObject, &defaultOutAddr, DispatchQueue.main, defaultOutListener)

        var devicesAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(systemObject, &devicesAddr, DispatchQueue.main, devicesListener)
    }

    private func teardownAudioOutputMonitoring() {
        cancelPendingHeadphoneResumes()
        detachDataSourceListener()
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        if let block = defaultOutputListenerBlock {
            var defaultOutAddr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(systemObject, &defaultOutAddr, DispatchQueue.main, block)
            defaultOutputListenerBlock = nil
        }
        if let block = devicesListenerBlock {
            var devicesAddr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(systemObject, &devicesAddr, DispatchQueue.main, block)
            devicesListenerBlock = nil
        }
    }

    private func attachDataSourceListener(for deviceID: AudioDeviceID) {
        detachDataSourceListener()
        guard deviceID != 0 else { return }
        var dataSourceAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &dataSourceAddr) else { return }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.handleAudioOutputRouteChange(forceIfHeadphones: true)
            }
        }
        if AudioObjectAddPropertyListenerBlock(deviceID, &dataSourceAddr, DispatchQueue.main, block) == noErr {
            dataSourceListenerBlock = block
            observedDataSourceDeviceID = deviceID
        }
    }

    private func detachDataSourceListener() {
        guard observedDataSourceDeviceID != 0, let block = dataSourceListenerBlock else {
            observedDataSourceDeviceID = 0
            dataSourceListenerBlock = nil
            return
        }
        var dataSourceAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(observedDataSourceDeviceID, &dataSourceAddr, DispatchQueue.main, block)
        observedDataSourceDeviceID = 0
        dataSourceListenerBlock = nil
    }

    private func cancelPendingHeadphoneResumes() {
        for item in pendingHeadphoneResumeWorkItems {
            item.cancel()
        }
        pendingHeadphoneResumeWorkItems.removeAll()
    }

    private func handleAudioOutputRouteChange(forceIfHeadphones: Bool) {
        let currentID = Self.currentDefaultOutputDeviceID()
        guard currentID != 0 else { return }

        if currentID != observedDataSourceDeviceID {
            attachDataSourceListener(for: currentID)
        }

        let currentIsHeadphones = Self.isHeadphoneOutputDevice(currentID)
        let previousWasHeadphones = lastOutputWasHeadphones
        let previousDeviceID = lastOutputDeviceID

        lastOutputDeviceID = currentID
        lastOutputWasHeadphones = currentIsHeadphones

        // Transition 1: Headphones removed / disconnected -> fallback to speakers or monitor
        if previousWasHeadphones && !currentIsHeadphones {
            cancelPendingHeadphoneResumes()
            if isBackgroundAudioActive && audioMode == .lofiRadio {
                stopAllLofi()
            }
            return
        }

        // Transition 2: Headphones put on / connected
        let switchedToHeadphones = currentIsHeadphones && (forceIfHeadphones || !previousWasHeadphones || currentID != previousDeviceID)
        guard switchedToHeadphones, isBackgroundAudioActive, musicVolume > 0.001 else {
            return
        }

        cancelPendingHeadphoneResumes()
        if audioMode == .lofiRadio {
            if lofiSource == .appleMusic {
                // Schedule at 0.8s and 1.8s so Bluetooth A2DP handshake has settled before Music.app resumes
                for delay in [0.8, 1.8] {
                    let work = DispatchWorkItem { [weak self] in
                        self?.resumeAppleMusicOnHeadphoneConnect()
                    }
                    pendingHeadphoneResumeWorkItems.append(work)
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
                }
            } else {
                startOfflineLofi()
            }
        }
    }

    private static func currentDefaultOutputDeviceID() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        return status == noErr ? deviceID : 0
    }

    private static func isHeadphoneOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        guard deviceID != 0 else { return false }

        // 1. Check Transport Type (Bluetooth / BluetoothLE / USB)
        var transport: UInt32 = 0
        var transSize = UInt32(MemoryLayout<UInt32>.size)
        var transAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(deviceID, &transAddr, 0, nil, &transSize, &transport) == noErr {
            if transport == kAudioDeviceTransportTypeBluetooth ||
               transport == kAudioDeviceTransportTypeBluetoothLE ||
               transport == kAudioDeviceTransportTypeUSB {
                return true
            }
        }

        // 2. Check Output DataSource for 3.5mm Headphone jack ('hdpn' = 0x6864706e)
        var dataSource: UInt32 = 0
        var dsSize = UInt32(MemoryLayout<UInt32>.size)
        var dsAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &dsAddr),
           AudioObjectGetPropertyData(deviceID, &dsAddr, 0, nil, &dsSize, &dataSource) == noErr {
            if dataSource == 0x6864706e {
                return true
            }
        }

        // 3. Fallback: Check device name for headphone keywords
        var unmanagedName: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var nameAddr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(deviceID, &nameAddr, 0, nil, &nameSize, &unmanagedName) == noErr,
           let cfName = unmanagedName?.takeUnretainedValue() {
            let lower = (cfName as String).lowercased()
            if lower.contains("headphone") || lower.contains("耳机") ||
               lower.contains("airpods") || lower.contains("beats") || lower.contains("earbuds") {
                return true
            }
        }

        return false
    }

    // MARK: - Apple Music Integration

    func openAppleMusicLofiPlaylist() {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.open(appleMusicPlaylistURL, configuration: config) { _, _ in
            self.runMusicAppleScript("""
            delay 1.5
            tell application "Music"
                play
            end tell
            """)
        }
    }

    private func startAppleMusicLofi() {
        let volInt = max(0, min(100, Int((min(musicVolume, 1.0) * 100.0).rounded())))
        let script = """
        tell application "Music"
            set sound volume to \(volInt)
            try
                set targetPlaylist to (first playlist whose name contains "Lofi Girl")
                play targetPlaylist
                return "playing_library_playlist"
            on error
                if player state is paused then
                    play
                    return "resumed"
                else if player state is stopped then
                    play
                    return "played"
                else
                    return "already_playing"
                end if
            end try
        end tell
        """
        appleScriptQueue.async { [weak self] in
            guard let self = self else { return }
            var errorDict: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                let result = appleScript.executeAndReturnError(&errorDict)
                DispatchQueue.main.async {
                    if errorDict != nil {
                        self.openAppleMusicLofiPlaylist()
                    } else if let str = result.stringValue, str == "played" {
                        self.lofiStatusText = "Apple Music: 正在播放 Lofi Girl"
                    }
                }
            }
        }
    }

    private func resumeAppleMusicOnHeadphoneConnect() {
        guard isBackgroundAudioActive, musicVolume > 0.001,
              audioMode == .lofiRadio, lofiSource == .appleMusic,
              Self.isHeadphoneOutputDevice(Self.currentDefaultOutputDeviceID()) else {
            return
        }
        let volInt = max(0, min(100, Int((min(musicVolume, 1.0) * 100.0).rounded())))
        let script = """
        if application "Music" is running then
            tell application "Music"
                set sound volume to \(volInt)
                if player state is paused then
                    play
                    return "resumed"
                else if player state is stopped then
                    return "stopped"
                else
                    return "already_playing"
                end if
            end tell
        end if
        return "not_running"
        """
        appleScriptQueue.async { [weak self] in
            guard let self = self else { return }
            var errorDict: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                let result = appleScript.executeAndReturnError(&errorDict)
                if let str = result.stringValue, str == "stopped" || str == "not_running" {
                    DispatchQueue.main.async {
                        if self.isBackgroundAudioActive &&
                           self.audioMode == .lofiRadio &&
                           self.lofiSource == .appleMusic &&
                           Self.isHeadphoneOutputDevice(Self.currentDefaultOutputDeviceID()) {
                            self.startAppleMusicLofi()
                        }
                    }
                }
            }
        }
    }

    private func pauseAppleMusic() {
        runMusicAppleScript("""
        if application "Music" is running then
            tell application "Music"
                if player state is playing then
                    pause
                end if
            end tell
        end if
        """)
    }

    private func runMusicAppleScript(_ source: String) {
        appleScriptQueue.async {
            var errorDict: NSDictionary?
            let script = NSAppleScript(source: source)
            script?.executeAndReturnError(&errorDict)
        }
    }

    // MARK: - Offline Lofi Integration

    private func startOfflineLofi() {
        reloadOfflineLofiPlaylist()
        guard !offlineLofiFiles.isEmpty else {
            lofiStatusText = "请将 MP3 放入 ~/.tomatobar/lofi"
            return
        }

        if let existing = offlineLofiPlayer {
            existing.setVolume(Float(musicVolume), fadeDuration: 0.2)
            existing.play()
            updateLofiStatusLabel()
            return
        }

        loadAndPlayLofiTrack(at: currentLofiTrackIndex)
    }

    private func loadAndPlayLofiTrack(at index: Int) {
        guard !offlineLofiFiles.isEmpty else { return }
        let safeIdx = index % offlineLofiFiles.count
        currentLofiTrackIndex = safeIdx
        let fileURL = offlineLofiFiles[safeIdx]

        do {
            let player = try AVAudioPlayer(contentsOf: fileURL)
            player.delegate = self
            player.numberOfLoops = offlineLofiFiles.count == 1 ? -1 : 0
            player.prepareToPlay()
            player.setVolume(Float(musicVolume), fadeDuration: 0.2)
            offlineLofiPlayer = player
            if isBackgroundAudioActive && audioMode == .lofiRadio && lofiSource == .offline {
                player.play()
            }
            updateLofiStatusLabel()
        } catch {
            lofiStatusText = "加载失败: \(fileURL.lastPathComponent)"
        }
    }

    private func pauseOfflineLofi() {
        offlineLofiPlayer?.pause()
    }

    func nextLofiTrack() {
        if lofiSource == .appleMusic {
            runMusicAppleScript("tell application \"Music\" to next track")
            return
        }
        reloadOfflineLofiPlaylist()
        guard !offlineLofiFiles.isEmpty else { return }
        offlineLofiPlayer?.stop()
        offlineLofiPlayer = nil
        currentLofiTrackIndex = (currentLofiTrackIndex + 1) % offlineLofiFiles.count
        loadAndPlayLofiTrack(at: currentLofiTrackIndex)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === offlineLofiPlayer else { return }
        DispatchQueue.main.async {
            self.nextLofiTrack()
        }
    }

    func revealLofiFolderInFinder() {
        reloadOfflineLofiPlaylist()
        NSWorkspace.shared.open(lofiDirectoryURL)
    }

    func chooseCustomBrownNoiseFile() {
        let panel = NSOpenPanel()
        panel.title = "选择自定义 Brown Noise 音频文件"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.audio]

        if panel.runModal() == .OK, let url = panel.url {
            customBrownNoisePath = url.path
        }
    }

    func resetToDefaultBrownNoise() {
        customBrownNoisePath = ""
    }
}
