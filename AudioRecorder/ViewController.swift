//
//  ViewController.swift
//  AudioRecorder
//
//  Created by Oleg Rybalko on 22.06.25.
//

import Cocoa
import CoreAudio
import AVFoundation
import Combine

class ViewController: NSViewController {
    
    private var isRecording = false
    
    private var aggregateDeviceID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private var tapID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private let queue = DispatchQueue(label: "ProcessTapRecorder", qos: .userInitiated)
    private var deviceProcID: AudioDeviceIOProcID?
    
    private var recordingButton: NSButton = NSButton()
    private var filePathField: NSTextField = NSTextField()
    
    private var currentFile: AVAudioFile?
    private var permissionGranted = false

    override func viewDidLoad() {
        super.viewDidLoad()

        // Setup recording button
        recordingButton = NSButton(title: "Record", target: self, action: #selector(recordingButtonClicked))
        recordingButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(recordingButton)
        
        // Setup file path field
        filePathField.isEditable = false
        filePathField.isSelectable = true
        filePathField.backgroundColor = .clear
        filePathField.isBordered = false
        filePathField.alignment = .center
        filePathField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        filePathField.textColor = .secondaryLabelColor
        filePathField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(filePathField)
        
        NSLayoutConstraint.activate([
            recordingButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            recordingButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            
            filePathField.topAnchor.constraint(equalTo: recordingButton.bottomAnchor, constant: 8),
            filePathField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            filePathField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }
    
    @objc
    func recordingButtonClicked(_ sender: NSButton) {
        if !permissionGranted {
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                self?.permissionGranted = granted
            }
            return
        }
        isRecording ? stopRecording() : startRecording()
    }
    
    private func startRecording() {
        // Update UI state
        recordingButton.title = "Stop"
        filePathField.stringValue = ""
        isRecording.toggle()
        
        // Create and configure the audio tap description
        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = .unmuted
        tapID = kAudioObjectUnknown
        
        // Create the process tap that will capture audio
        var err = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard err == noErr else {
            print("Process tap creation failed with error \(err)")
            return
        }
        print("Created process tap #\(tapID)")

        // Get the default system output device
        guard let systemOutputID = try? readDefaultSystemOutputDevice() else {
            print("failed to read default system output device")
            return
        }

        // Get the unique identifier of the output device
        guard let outputUID = try? readDeviceUID(for: systemOutputID) else {
            print("failed to read device uid")
            return
        }
        
        guard let inputID = try? readDefaultInputDevice() else {
            print("default input device")
            return
        }
        
        guard let inputUID = try? readDeviceUID(for: inputID) else {
            print("failed to read dev uid")
            return
        }
        
        guard let inputSampleRate = try? readDeviceSampleRate(for: inputID) else {
            print("failed to read input sample rate")
            return
        }
        
        guard let outputSampleRate = try? readDeviceSampleRate(for: systemOutputID) else {
            print("failed to read input sample rate")
            return
        }
        
        let masterDeviceUID = inputSampleRate <= outputSampleRate ? inputUID : outputUID

        // Generate a unique ID for our aggregate device
        let aggregateUID = UUID().uuidString

        // Configure the aggregate device that combines the system output with our tap
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Tap-global",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: masterDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: false,
            kAudioAggregateDeviceSubDeviceListKey: [
                [
                    kAudioSubDeviceUIDKey: outputUID,
                    kAudioSubDeviceDriftCompensationKey: true
                ],
                [
                    kAudioSubDeviceUIDKey: inputUID,
                    kAudioSubDeviceDriftCompensationKey: false
                ]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString
                ]
            ]
        ]

        // Create the aggregate device
        aggregateDeviceID = kAudioObjectUnknown
        err = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateDeviceID)
        guard err == noErr else {
            print("Failed to create aggregate device: \(err)")
            return
        }

        // Get the audio format from the tap
        guard var streamDescription = try? readDeviceStreamBasicDescription(for: aggregateDeviceID, scope: kAudioObjectPropertyScopeInput) else {
            print("Tap stream description not available.")
            return
        }

        // Create an AVAudioFormat for the file
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            print("Failed to create AVAudioFormat.")
            return
        }
        print("Using audio format: \(format)")
        
        // Configure audio file settings
        let numOutputChannels = 2
        let settings: [String: Any] = [
            AVFormatIDKey: streamDescription.mFormatID,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: numOutputChannels
        ]
        
        // Generate unique filename based on current timestamp
        let filename = "\(Int(Date.now.timeIntervalSinceReferenceDate))"
        let fileURL = URL.applicationSupport.appendingPathComponent(filename, conformingTo: .wav)
        
        // Create the audio file for writing
        guard let file = try? AVAudioFile(forWriting: fileURL, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false) else {
            print("failed to create avaudiofile")
            return
        }
        currentFile = file
        print("Writing to \(fileURL.absoluteString)")
        
        // Create an I/O proc that writes audio data to our file
        let procErr = AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, aggregateDeviceID, queue) { [weak self] inNow, inInputData, inInputTime, outOutputData, inOutputTime in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
            var monoBuffers: [AudioBuffer] = []
            
            // Downmix buffers to mono
            for i in 0..<inInputData.pointee.mNumberBuffers {
                let buf = buffers[Int(i)]
                if buf.mNumberChannels == 1 {
                    monoBuffers.append(buf)
                    continue
                }
                // Convert to mono
                let floatSize = UInt32(MemoryLayout<Float32>.size)
                let numChannels = buf.mNumberChannels
                let numFrames = buf.mDataByteSize / floatSize / numChannels
                
                let monoBuff = UnsafeMutablePointer<Float32>.allocate(capacity: Int(numFrames))
                monoBuff.initialize(repeating: 0.0, count: Int(numFrames))
                
                guard let data = buf.mData else {
                    continue
                }
                
                let arr = data.assumingMemoryBound(to: Float32.self)
                for i in 0..<numFrames {
                    var sum: Float32 = 0.0
                    for ch in 0..<numChannels {
                        sum += arr[Int(i * numChannels + ch)]
                    }
                    monoBuff[Int(i)] = sum / Float(numChannels)
                }
                monoBuffers.append(AudioBuffer(mNumberChannels: 1, mDataByteSize: numFrames * floatSize, mData: monoBuff))
            }
            let bufferCount = monoBuffers.count
            assert(bufferCount == buffers.count, "downmixing from stereo to mono failed")
            let bufferList = AudioBufferList.allocate(maximumBuffers: numOutputChannels)
            bufferList[0] = monoBuffers[0]
            bufferList[1] = monoBuffers[1]

            guard let bufFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: format.sampleRate, channels: UInt32(numOutputChannels), interleaved: false) else {
                print("failed to create buf format")
                return
            }

            guard let self, let currentFile = self.currentFile else { return }
            do {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: bufFormat, bufferListNoCopy: bufferList.unsafePointer, deallocator: nil) else {
                    throw "Failed to create PCM buffer"
                }

                try currentFile.write(from: buffer)
            } catch {
                print("Failed to write to file: \(error)")
            }
        }


        guard procErr == noErr else {
            print("Failed to create device I/O proc: \(err)")
            return
        }

        // Start the audio device to begin recording
        let startErr = AudioDeviceStart(aggregateDeviceID, deviceProcID)
        guard startErr == noErr else {
            print("Failed to start audio device: \(err)")
            return
        }
    }
    
    private func stopRecording() {
        if let deviceProcID = deviceProcID {
            var err = AudioDeviceStop(aggregateDeviceID, deviceProcID)
            if err != noErr {
                print("Failed to stop aggregate device: \(err)")
            }

            err = AudioDeviceDestroyIOProcID(aggregateDeviceID, deviceProcID)
            if err != noErr {
                print("Failed to destroy device I/O proc: \(err)")
            }
            self.deviceProcID = nil
        }
        
        var err = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        if err != noErr {
            print("Failed to destroy aggregate device: \(err)")
        }
        aggregateDeviceID = kAudioObjectUnknown

        err = AudioHardwareDestroyProcessTap(tapID)
        if err != noErr {
            print("Failed to destroy process tap: \(err)")
        }
        tapID = kAudioObjectUnknown

        recordingButton.title = "Record"
        if let file = currentFile {
            filePathField.stringValue = "Saved to: \(file.url.path)"
        }
        isRecording.toggle()
    }
}

