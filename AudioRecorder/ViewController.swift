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

        // Generate a unique ID for our aggregate device
        let aggregateUID = UUID().uuidString

        // Configure the aggregate device that combines the system output with our tap
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Tap-global",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [
                    kAudioSubDeviceUIDKey: outputUID
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
        guard var streamDescription = try? readAudioTapStreamBasicDescription(for: tapID) else {
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
        let settings: [String: Any] = [
            AVFormatIDKey: streamDescription.mFormatID,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount
        ]
        
        // Generate unique filename based on current timestamp
        let filename = "\(Int(Date.now.timeIntervalSinceReferenceDate))"
        let fileURL = URL.applicationSupport.appendingPathComponent(filename, conformingTo: .wav)
        
        // Create the audio file for writing
        guard let file = try? AVAudioFile(forWriting: fileURL, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: format.isInterleaved) else {
            print("failed to create avaudiofile")
            return
        }
        currentFile = file
        print("Writing to \(fileURL.absoluteString)")
        filePathField.stringValue = "Recording to: \(fileURL.path)"

        // Create an I/O proc that writes audio data to our file
        let procErr = AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, aggregateDeviceID, queue) { [weak self] inNow, inInputData, inInputTime, outOutputData, inOutputTime in
            guard let self, let currentFile = self.currentFile else { return }
            do {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inInputData, deallocator: nil) else {
                    throw "Failed to create PCM buffer"
                }
                
                try currentFile.write(from: buffer)
            } catch {
                print("Failed to write buffer")
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

