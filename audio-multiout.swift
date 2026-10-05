// audio-multiout: CoreAudio helper for the `meet` recording system.
// Creates/destroys a stacked aggregate (multi-output) device so system audio
// plays on the real output AND mirrors into BlackHole for recording.
//
// Commands:
//   default-output            print "UID<TAB>Name" of current default output
//   default-input             print "UID<TAB>Name" of current default input
//   create <mainUID> <bhUID>  create multi-output "MeetRec" (main + BlackHole)
//   set-default <uid>         set default output device by UID
//   destroy                   destroy the MeetRec device if it exists

import CoreAudio
import Foundation

let MULTI_UID = "com.meet.multiout"
let MULTI_NAME = "MeetRec"

func addr(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector,
                               mScope: kAudioObjectPropertyScopeGlobal,
                               mElement: kAudioObjectPropertyElementMain)
}

func getString(_ objID: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var a = addr(selector)
    var size = UInt32(MemoryLayout<CFString?>.size)
    var str: CFString? = nil
    let err = withUnsafeMutablePointer(to: &str) {
        AudioObjectGetPropertyData(objID, &a, 0, nil, &size, $0)
    }
    guard err == noErr, let s = str else { return nil }
    return s as String
}

func allDevices() -> [AudioObjectID] {
    var a = addr(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr else { return [] }
    var devs = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &devs) == noErr else { return [] }
    return devs
}

func deviceByUID(_ uid: String) -> AudioObjectID? {
    allDevices().first { getString($0, kAudioDevicePropertyDeviceUID) == uid }
}

func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioObjectID {
    var a = addr(selector)
    var dev = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &dev)
    return dev
}

func printDevice(_ dev: AudioObjectID) {
    let uid = getString(dev, kAudioDevicePropertyDeviceUID) ?? "?"
    let name = getString(dev, kAudioObjectPropertyName) ?? "?"
    print("\(uid)\t\(name)")
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 2 else { fail("usage: audio-multiout <default-output|default-input|create|set-default|destroy> [args]") }

switch args[1] {
case "default-output":
    printDevice(defaultDevice(kAudioHardwarePropertyDefaultOutputDevice))

case "default-input":
    printDevice(defaultDevice(kAudioHardwarePropertyDefaultInputDevice))

case "create":
    guard args.count == 4 else { fail("usage: create <mainUID> <blackholeUID>") }
    let mainUID = args[2], bhUID = args[3]
    let desc: [String: Any] = [
        kAudioAggregateDeviceUIDKey as String: MULTI_UID,
        kAudioAggregateDeviceNameKey as String: MULTI_NAME,
        kAudioAggregateDeviceIsStackedKey as String: 1,
        kAudioAggregateDeviceMainSubDeviceKey as String: mainUID,
        kAudioAggregateDeviceSubDeviceListKey as String: [
            [kAudioSubDeviceUIDKey as String: mainUID],
            [kAudioSubDeviceUIDKey as String: bhUID,
             kAudioSubDeviceDriftCompensationKey as String: 1],
        ],
    ]
    var newID = AudioObjectID(0)
    let err = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &newID)
    guard err == noErr else { fail("create failed: OSStatus \(err)") }
    // Give CoreAudio a moment to publish the device before callers use it.
    usleep(300_000)
    print(MULTI_UID)

case "set-default":
    guard args.count == 3 else { fail("usage: set-default <uid>") }
    guard var dev = deviceByUID(args[2]) else { fail("no device with UID \(args[2])") }
    var a = addr(kAudioHardwarePropertyDefaultOutputDevice)
    let err = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil,
                                         UInt32(MemoryLayout<AudioObjectID>.size), &dev)
    guard err == noErr else { fail("set-default failed: OSStatus \(err)") }

case "destroy":
    guard let dev = deviceByUID(MULTI_UID) else { exit(0) }
    let err = AudioHardwareDestroyAggregateDevice(dev)
    guard err == noErr else { fail("destroy failed: OSStatus \(err)") }

default:
    fail("unknown command: \(args[1])")
}
