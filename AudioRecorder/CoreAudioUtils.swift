//
//  CoreAudioUtils.swift
//  AudioRecorder
//
//  Created by Oleg Rybalko on 23.06.25.
//

import Foundation
import AudioToolbox

func readDefaultSystemOutputDevice() throws -> AudioDeviceID {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    var deviceID = kAudioObjectClassID
    var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
    
    let err = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &dataSize,
        &deviceID
    )
    
    guard err == noErr else {
        throw "Error reading default system output device: \(err)"
    }
    
    guard deviceID != kAudioObjectUnknown else {
        throw "Invalid device ID returned"
    }
    
    return deviceID
}

func readDeviceUID(for deviceID: AudioDeviceID) throws -> String {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceUID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    var dataSize: UInt32 = 0
    var err = AudioObjectGetPropertyDataSize(
        deviceID,
        &address,
        0,
        nil,
        &dataSize
    )
    
    guard err == noErr else {
        throw "Error getting UID data size: \(err)"
    }
    
    var deviceUID = "" as CFString
    err = AudioObjectGetPropertyData(
        deviceID,
        &address,
        0,
        nil,
        &dataSize,
        &deviceUID
    )
    
    guard err == noErr else {
        throw "Error reading device UID: \(err)"
    }
    
    return deviceUID as String
}

func readAudioTapStreamBasicDescription(for tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioTapPropertyFormat,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    var streamDescription = AudioStreamBasicDescription()
    
    let err = AudioObjectGetPropertyData(
        tapID,
        &address,
        0,
        nil,
        &dataSize,
        &streamDescription
    )
    
    guard err == noErr else {
        throw "Error reading tap stream format: \(err)"
    }
    
    return streamDescription
}

func readDefaultInputDevice() throws -> AudioDeviceID {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    var deviceID = kAudioObjectClassID
    var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

    let err = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &dataSize,
        &deviceID
    )

    guard err == noErr else {
        throw "Error reading default system input device: \(err)"
    }

    guard deviceID != kAudioObjectUnknown else {
        throw "Invalid device ID returned"
    }

    return deviceID
}

func readDeviceStreamBasicDescription(for deviceID: AudioObjectID, scope: AudioObjectPropertyScope) throws -> AudioStreamBasicDescription {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamFormat,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain
    )

    var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    var streamDescription = AudioStreamBasicDescription()

    let err = AudioObjectGetPropertyData(
        deviceID,
        &address,
        0,
        nil,
        &dataSize,
        &streamDescription
    )

    guard err == noErr else {
        throw "Error reading device stream format: \(err)"
    }

    return streamDescription
}

func readDeviceSampleRate(for deviceID: AudioObjectID) throws -> Float64 {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyNominalSampleRate,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = UInt32(MemoryLayout<Float64>.size)
    var sampleRate: Float64 = 0
    
    let err = AudioObjectGetPropertyData(
        deviceID,
        &address,
        0,
        nil,
        &dataSize,
        &sampleRate
    )
    
    guard err == noErr else {
        throw "Error reading sample rate: \(err)"
    }
    return sampleRate
}

