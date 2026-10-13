import Foundation
import CoreAudio

/// Bir uygulamanın (bir veya birden çok süreç) sesini Core Audio tap ile orijinal çıkıştan keser,
/// kazanç uygulayıp varsayılan çıkış cihazına yeniden çalar.
///
///   uygulama süreçleri ──► CATap (mutedWhenTapped) ──► özel aggregate cihaz ──► IOProc (× gain) ──► hoparlör
final class ProcessTap {
    static let uidPrefix = "com.canerod.qmixer.agg."

    let processObjects: [AudioObjectID]
    let outputUID: String

    private var tapID: AudioObjectID = .unknown
    private var aggregateID: AudioObjectID = .unknown
    private var ioProcID: AudioDeviceIOProcID?
    /// [0] = hedef kazanç, [1] = anlık kazanç (tıkırtı olmaması için yumuşak geçiş). IO thread okur.
    private let gain = UnsafeMutablePointer<Float>.allocate(capacity: 2)

    init(processObjects: [AudioObjectID], outputUID: String, name: String, initialGain: Float) throws {
        self.processObjects = processObjects
        self.outputUID = outputUID
        gain[0] = initialGain
        gain[1] = initialGain
        do {
            try start(name: name)
        } catch {
            teardown()
            throw error
        }
    }

    deinit {
        teardown()
        gain.deallocate()
    }

    func setGain(_ g: Float) {
        gain[0] = max(0, g)
    }

    private func start(name: String) throws {
        let desc = CATapDescription(stereoMixdownOfProcesses: processObjects)
        desc.uuid = UUID()
        desc.name = "Qmixer – \(name)"
        desc.muteBehavior = .mutedWhenTapped
        desc.isPrivate = true

        var tap = AudioObjectID.unknown
        try check(AudioHardwareCreateProcessTap(desc, &tap), "Process tap oluşturma")
        tapID = tap

        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Qmixer \(name)",
            kAudioAggregateDeviceUIDKey: Self.uidPrefix + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: desc.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        var agg = AudioObjectID.unknown
        try check(AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &agg), "Aggregate cihaz oluşturma")
        aggregateID = agg

        let g = gain
        var procID: AudioDeviceIOProcID?
        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, agg, nil) { _, inData, _, outData, _ in
            ProcessTap.render(inData, outData, g)
        }, "IOProc oluşturma")
        ioProcID = procID

        disableDeviceInputStreams()
        try check(AudioDeviceStart(agg, procID), "Aggregate cihaz başlatma")
    }

    /// Çıkış cihazının kendi mikrofonu varsa (AirPods, USB kulaklık) onu açmayalım:
    /// açılırsa mikrofon göstergesi yanar ve Bluetooth kulaklık düşük kaliteli moda geçer.
    /// Aggregate'in giriş akışları önce alt cihazınkiler, en sonda tap'inki gelir.
    private func disableDeviceInputStreams() {
        guard let ioProcID else { return }
        var a = propAddr(kAudioDevicePropertyIOProcStreamUsage, kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(aggregateID, &a, 0, nil, &size) == noErr, size >= 12 else { return }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 8)
        defer { raw.deallocate() }
        raw.initializeMemory(as: UInt8.self, repeating: 0, count: Int(size))
        raw.storeBytes(of: unsafeBitCast(ioProcID, to: UnsafeMutableRawPointer.self), as: UnsafeMutableRawPointer.self)
        guard AudioObjectGetPropertyData(aggregateID, &a, 0, nil, &size, raw) == noErr else { return }
        let count = Int(raw.load(fromByteOffset: 8, as: UInt32.self))
        guard count > 1 else { return }
        for i in 0..<count {
            raw.storeBytes(of: UInt32(i == count - 1 ? 1 : 0), toByteOffset: 12 + i * 4, as: UInt32.self)
        }
        AudioObjectSetPropertyData(aggregateID, &a, 0, nil, size, raw)
    }

    private func teardown() {
        if aggregateID != .unknown, let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil
        if aggregateID != .unknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = .unknown
        if tapID != .unknown { AudioHardwareDestroyProcessTap(tapID) }
        tapID = .unknown
    }

    /// Gerçek zamanlı ses thread'i: bellek ayırma / kilit yok.
    private static func render(_ inData: UnsafePointer<AudioBufferList>,
                               _ outData: UnsafeMutablePointer<AudioBufferList>,
                               _ gain: UnsafeMutablePointer<Float>) {
        let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
        let outs = UnsafeMutableAudioBufferListPointer(outData)

        // Tap akışı = verisi olan son giriş tamponu (stereo, interleaved float32).
        var src: UnsafeMutablePointer<Float>?
        var srcCh = 0, srcFrames = 0
        for i in stride(from: ins.count - 1, through: 0, by: -1) {
            let b = ins[i]
            if let d = b.mData, b.mNumberChannels > 0, b.mDataByteSize > 0 {
                src = d.assumingMemoryBound(to: Float.self)
                srcCh = Int(b.mNumberChannels)
                srcFrames = Int(b.mDataByteSize) / (4 * srcCh)
                break
            }
        }

        let target = gain[0]
        let start = gain[1]
        var outChBase = 0
        var maxFrames = 0
        for i in 0..<outs.count {
            let b = outs[i]
            guard let d = b.mData, b.mNumberChannels > 0 else { continue }
            let dst = d.assumingMemoryBound(to: Float.self)
            let ch = Int(b.mNumberChannels)
            let outFrames = Int(b.mDataByteSize) / (4 * ch)
            maxFrames = max(maxFrames, outFrames)
            guard let src, srcCh > 0 else {
                dst.update(repeating: 0, count: outFrames * ch)
                continue
            }
            let n = min(outFrames, srcFrames)
            let step = n > 0 ? (target - start) / Float(n) : 0
            var g = start
            for f in 0..<n {
                g += step
                for c in 0..<ch {
                    dst[f * ch + c] = src[f * srcCh + (outChBase + c) % srcCh] * g
                }
            }
            if n < outFrames {
                (dst + n * ch).update(repeating: 0, count: (outFrames - n) * ch)
            }
            outChBase += ch
        }
        if maxFrames > 0 { gain[1] = target }
    }
}
