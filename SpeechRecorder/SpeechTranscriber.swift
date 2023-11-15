//
//  SpeechTranscriber.swift
//  SpeechRecorder
//
//  Created by Ian Dundas on 15/11/2023.
//

import Foundation
import Speech
import AVFAudio

/*
 Press start recording, it should begin recording and streaming the results.

 - Needs to be able to switch languages
 - Needs to be able to switch devices (airpods)
 */

@Observable
class SpeechTranscriber {

    enum State: Equatable, CustomStringConvertible {
        case idle
        case requiresPermission
        case recording(partial: SFTranscription?)
        case error(_: Error)

        var description: String {
            switch self {
            case .idle: return "Idle"
            case .requiresPermission: return "Requires Permission"
            case .recording: return "Recording"
            case .error(let error): return "Error: \(error.localizedDescription)"
            }
        }

        static func == (lhs: SpeechTranscriber.State, rhs: SpeechTranscriber.State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle): return true
            case (.requiresPermission, .requiresPermission): return true
            case (.recording, .recording): return true
            case (.error, .error): return true
            default: return false
            }
        }

        var isIdle: Bool {
            if case .idle = self {
                return true
            }
            return false
        }
        var isRecording: Bool {
            if case .recording = self {
                return true
            }
            return false
        }
    }

    enum Error: Swift.Error, LocalizedError {
        case failedToGetPermission(status: SFSpeechRecognizerAuthorizationStatus)
        case recordingError(Swift.Error)

        var errorDescription: String? {
            switch self {
            case .failedToGetPermission(let status):
                switch status {
                case .notDetermined:
                    return "Speech permission status was not determined."
                case .denied:
                    return "Permission was not granted to use Speech."
                case .restricted:
                    return "The system is preventing Speech being used."
                case .authorized:
                    return nil
                default:
                    return "Unknown error with Speech"
                }
            case .recordingError(let error):
                return error.localizedDescription
            }
        }
    }

    private(set) var state: State = .idle
    private(set) var hasPermission: Bool? = nil
    private var recordingTask: Task<Void, Never>?

    init() {
        hasPermission = SFSpeechRecognizer.authorizationStatus().hasPermission
    }

    func requestPermission() async throws {
        try await withCheckedThrowingContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                self.hasPermission = status.hasPermission // also update self.

                if case .authorized = status {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SpeechTranscriber.Error.failedToGetPermission(status: status))
                }
            }
        }
    }

    func startRecording(locale: Locale) {
        guard hasPermission == true else { return }

        self.state = .recording(partial: nil)
        self.recordingTask = Task<Void, Never>() {
            do {
                for try await value in ActiveTranscription.record(locale: locale) {
                    print("Received value: \(value.formattedString)")
                    self.state = .recording(partial: value)
                }
                self.state = .idle // .finishedRecording(complete: latest)
            } catch {
                print("Stream encountered an error: \(error)")
                self.state = .error(.recordingError(error))
            }
        }
    }

    func stopRecording() {
        recordingTask?.cancel()
        recordingTask = nil
    }
}


fileprivate struct ActiveTranscription {
    enum Error: Swift.Error {
        case couldNotCreateRecogniserForGivenLocale(locale: Locale)
    }

    static func record(locale: Locale) -> AsyncThrowingStream<SFTranscription, Swift.Error> {
        AsyncThrowingStream<SFTranscription, Swift.Error> { continuation in

            let task = Task {
                do {
                    guard let speechRecogniser = SFSpeechRecognizer(locale: locale) else {
                        throw ActiveTranscription.Error.couldNotCreateRecogniserForGivenLocale(locale: locale)
                    }

                    let audioSession = AVAudioSession.sharedInstance()

                    // TODO: work out how to allow airpods
                    try audioSession.setCategory(AVAudioSession.Category.record, mode: .default)
                    try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

                    let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
                    recognitionRequest.shouldReportPartialResults = true
                    recognitionRequest.requiresOnDeviceRecognition = false // TODO: Defaults[.useOnDeviceDictation]

                    // Configure the microphone input.
                    let audioEngine = AVAudioEngine()
                    let inputNode = audioEngine.inputNode
                    let recordingFormat = inputNode.outputFormat(forBus: 0)
                    inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in

                        // Possibly needed r.e. airpods? https://developer.apple.com/forums/thread/705706
                        recognitionRequest.append(buffer)
                    }

                    audioEngine.prepare()
                    try audioEngine.start()

                    defer {
                        recognitionRequest.endAudio()
                        audioEngine.stop()
                        audioEngine.inputNode.removeTap(onBus: 0)
                        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                    }

                    for try await result in speechRecogniser.recognition(with: recognitionRequest) {
                        continuation.yield(result.bestTranscription)
                    }

                    continuation.finish()
                } catch {
                    print("Error: ", error.localizedDescription)
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

extension SFSpeechRecognizer {

    func recognition(with recognitionRequest: SFSpeechAudioBufferRecognitionRequest) -> AsyncThrowingStream<SFSpeechRecognitionResult, Swift.Error> {

        return AsyncThrowingStream<SFSpeechRecognitionResult, Swift.Error> { continuation in
            let task = self.recognitionTask(with: recognitionRequest) { (result: SFSpeechRecognitionResult?, error: Error?) in
                if let error {
                    continuation.finish(throwing: error)
                } else if let result {
                    continuation.yield(result)

                    if result.isFinal {
                        continuation.finish()
                    }
                }
            }

            continuation.onTermination = { reason in
                task.cancel()
            }
        }
    }
}
