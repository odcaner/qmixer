import CoreAudio
import AudioToolbox

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = AudioObjectID(kAudioObjectUnknown)
}

func propAddr(_ selector: AudioObjectPropertySelector,
              _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
              _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
}

struct CoreAudioError: LocalizedError {
    let what: String
    let status: OSStatus
    var errorDescription: String? { "\(what) başarısız (OSStatus \(status))" }
}

func check(_ status: OSStatus, _ what: String) throws {
    if status != noErr { throw CoreAudioError(what: what, status: status) }
}

enum CA {
    static func has(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var a = address
        return AudioObjectHasProperty(id, &a)
    }

    static func isSettable(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var a = address
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(id, &a, &settable) == noErr && settable.boolValue
    }

    static func get<T>(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress, as: T.Type = T.self) -> T? {
        var a = address
        var size = UInt32(MemoryLayout<T>.size)
        let ptr = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { ptr.deallocate() }
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, ptr) == noErr else { return nil }
        return ptr.pointee
    }

    @discardableResult
    static func set<T>(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: T) -> Bool {
        var a = address
        var v = value
        return AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<T>.size), &v) == noErr
    }

    static func array<T>(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress, of: T.Type = T.self) -> [T] {
        var a = address
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<T>.stride
        let ptr = UnsafeMutablePointer<T>.allocate(capacity: count)
        defer { ptr.deallocate() }
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, ptr) == noErr else { return [] }
        return Array(UnsafeBufferPointer(start: ptr, count: Int(size) / MemoryLayout<T>.stride))
    }

    static func string(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress) -> String? {
        var a = address
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    /// Bir özellik değiştiğinde ana kuyrukta blok çalıştırır.
    static func listen(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress, _ block: @escaping () -> Void) {
        var a = address
        AudioObjectAddPropertyListenerBlock(id, &a, DispatchQueue.main) { _, _ in block() }
    }
}
