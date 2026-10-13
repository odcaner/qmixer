import Foundation
import CoreAudio
import AudioToolbox

struct AudioDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let symbol: String      // SF Symbol
    let kind: String        // "Bluetooth", "USB", ...

    init(id: AudioObjectID, uid: String, name: String, isInput: Bool) {
        self.id = id
        self.uid = uid
        self.name = name
        let transport: UInt32 = CA.get(id, propAddr(kAudioDevicePropertyTransportType)) ?? 0
        let lower = name.lowercased()
        let headset = ["headphone", "kulaklık", "headset", "earpods", "buds", "beats"].contains { lower.contains($0) }

        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            kind = "Dahili"
            symbol = isInput ? "mic" : headset ? "headphones" : "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            kind = "Bluetooth"
            symbol = lower.contains("airpods max") ? "airpods.max"
                : lower.contains("airpods pro") ? "airpods.pro"
                : lower.contains("airpods") ? "airpods"
                : lower.contains("iphone") ? "iphone"
                : headset ? "headphones" : "hifispeaker"
        case kAudioDeviceTransportTypeUSB:
            kind = "USB"
            symbol = headset ? "headphones" : isInput ? "music.mic" : "hifispeaker"
        case kAudioDeviceTransportTypeHDMI:
            kind = "HDMI"; symbol = "tv"
        case kAudioDeviceTransportTypeDisplayPort:
            kind = "DisplayPort"; symbol = "display"
        case kAudioDeviceTransportTypeAirPlay:
            kind = "AirPlay"; symbol = "airplay.audio"
        case kAudioDeviceTransportTypeThunderbolt:
            kind = "Thunderbolt"; symbol = isInput ? "music.mic" : "hifispeaker"
        case kAudioDeviceTransportTypeContinuityCaptureWired, kAudioDeviceTransportTypeContinuityCaptureWireless:
            kind = "Süreklilik"; symbol = "iphone"
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate:
            kind = "Birleşik"; symbol = "square.stack.3d.up"
        case kAudioDeviceTransportTypeVirtual:
            kind = "Sanal"; symbol = "waveform"
        default:
            kind = ""; symbol = isInput ? "mic" : "speaker.wave.2"
        }
    }
}

/// Sistem ses giriş/çıkış cihazlarını listeler; varsayılan cihazı, ses seviyesini ve sessizi yönetir.
@MainActor
final class DeviceController: ObservableObject {
    @Published private(set) var outputs: [AudioDevice] = []
    @Published private(set) var inputs: [AudioDevice] = []
    @Published private(set) var defaultOutput: AudioObjectID = .unknown
    @Published private(set) var defaultInput: AudioObjectID = .unknown

    @Published var outputVolume: Float = 0
    @Published var outputMuted = false
    @Published private(set) var outputHasVolume = false
    @Published var inputVolume: Float = 0
    @Published var inputMuted = false
    @Published private(set) var inputHasVolume = false

    private var timer: Timer?

    init() {
        reload()
        for sel in [kAudioHardwarePropertyDevices,
                    kAudioHardwarePropertyDefaultOutputDevice,
                    kAudioHardwarePropertyDefaultInputDevice] {
            CA.listen(.system, propAddr(sel)) { [weak self] in self?.reload() }
        }
        // Ses seviyesi başka yerden (klavye, Denetim Merkezi) değişirse yakalamak için.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshLevels() }
        }
    }

    var defaultOutputUID: String? {
        CA.string(defaultOutput, propAddr(kAudioDevicePropertyDeviceUID))
    }

    func reload() {
        let ids: [AudioObjectID] = CA.array(.system, propAddr(kAudioHardwarePropertyDevices))
        var outs: [AudioDevice] = [], ins: [AudioDevice] = []
        for id in ids {
            guard let uid = CA.string(id, propAddr(kAudioDevicePropertyDeviceUID)),
                  !uid.hasPrefix(ProcessTap.uidPrefix) else { continue }
            let name = CA.string(id, propAddr(kAudioObjectPropertyName)) ?? uid
            if Self.hasStreams(id, kAudioObjectPropertyScopeOutput) {
                outs.append(AudioDevice(id: id, uid: uid, name: name, isInput: false))
            }
            if Self.hasStreams(id, kAudioObjectPropertyScopeInput) {
                ins.append(AudioDevice(id: id, uid: uid, name: name, isInput: true))
            }
        }
        outputs = outs
        inputs = ins
        defaultOutput = CA.get(.system, propAddr(kAudioHardwarePropertyDefaultOutputDevice)) ?? .unknown
        defaultInput = CA.get(.system, propAddr(kAudioHardwarePropertyDefaultInputDevice)) ?? .unknown
        refreshLevels()
    }

    func refreshLevels() {
        let ov = Self.volume(defaultOutput, kAudioObjectPropertyScopeOutput)
        outputHasVolume = ov != nil
        if let ov, abs(ov - outputVolume) > 0.001 { outputVolume = ov }
        let om = Self.muted(defaultOutput, kAudioObjectPropertyScopeOutput)
        if om != outputMuted { outputMuted = om }

        let iv = Self.volume(defaultInput, kAudioObjectPropertyScopeInput)
        inputHasVolume = iv != nil
        if let iv, abs(iv - inputVolume) > 0.001 { inputVolume = iv }
        let im = Self.muted(defaultInput, kAudioObjectPropertyScopeInput)
        if im != inputMuted { inputMuted = im }
    }

    // MARK: - Eylemler

    func setDefaultOutput(_ id: AudioObjectID) {
        CA.set(.system, propAddr(kAudioHardwarePropertyDefaultOutputDevice), id)
        CA.set(.system, propAddr(kAudioHardwarePropertyDefaultSystemOutputDevice), id)
        reload()
    }

    func setDefaultInput(_ id: AudioObjectID) {
        CA.set(.system, propAddr(kAudioHardwarePropertyDefaultInputDevice), id)
        reload()
    }

    func setOutputVolume(_ v: Float) {
        outputVolume = v
        Self.setVolume(defaultOutput, kAudioObjectPropertyScopeOutput, v)
        if v > 0, outputMuted { setOutputMuted(false) }
    }

    func setOutputMuted(_ m: Bool) {
        outputMuted = m
        Self.setMuted(defaultOutput, kAudioObjectPropertyScopeOutput, m)
    }

    func setInputVolume(_ v: Float) {
        inputVolume = v
        Self.setVolume(defaultInput, kAudioObjectPropertyScopeInput, v)
    }

    func setInputMuted(_ m: Bool) {
        inputMuted = m
        Self.setMuted(defaultInput, kAudioObjectPropertyScopeInput, m)
    }

    // MARK: - Core Audio

    private static func hasStreams(_ id: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Bool {
        let streams: [AudioStreamID] = CA.array(id, propAddr(kAudioDevicePropertyStreams, scope))
        return !streams.isEmpty
    }

    /// Önce "sanal ana ses" (tüm kanallar), yoksa ana eleman, yoksa 1. kanal.
    private static func volume(_ id: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Float? {
        guard id != .unknown else { return nil }
        var a = propAddr(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope)
        if AudioHardwareServiceHasProperty(id, &a) {
            var v: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioHardwareServiceGetPropertyData(id, &a, 0, nil, &size, &v) == noErr { return v }
        }
        for el: UInt32 in [kAudioObjectPropertyElementMain, 1] {
            if let v: Float32 = CA.get(id, propAddr(kAudioDevicePropertyVolumeScalar, scope, el)) { return v }
        }
        return nil
    }

    private static func setVolume(_ id: AudioObjectID, _ scope: AudioObjectPropertyScope, _ value: Float) {
        guard id != .unknown else { return }
        var v = Float32(max(0, min(1, value)))
        var a = propAddr(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope)
        if AudioHardwareServiceHasProperty(id, &a),
           AudioHardwareServiceSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr {
            return
        }
        let main = propAddr(kAudioDevicePropertyVolumeScalar, scope, kAudioObjectPropertyElementMain)
        if CA.isSettable(id, main) { CA.set(id, main, v); return }
        for ch: UInt32 in 1...8 {
            let a = propAddr(kAudioDevicePropertyVolumeScalar, scope, ch)
            if CA.isSettable(id, a) { CA.set(id, a, v) }
        }
    }

    private static func muted(_ id: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Bool {
        guard id != .unknown else { return false }
        let m: UInt32? = CA.get(id, propAddr(kAudioDevicePropertyMute, scope))
        return (m ?? 0) != 0
    }

    private static func setMuted(_ id: AudioObjectID, _ scope: AudioObjectPropertyScope, _ muted: Bool) {
        guard id != .unknown else { return }
        CA.set(id, propAddr(kAudioDevicePropertyMute, scope), UInt32(muted ? 1 : 0))
    }
}
