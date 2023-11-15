//
//  Helper.swift
//  SpeechRecorder
//
//  Created by Ian Dundas on 15/11/2023.
//

import Foundation
import Speech

extension SFSpeechRecognizerAuthorizationStatus {

    var hasPermission: Bool? {
        switch self {
        case .authorized: return true
        case .denied: return false
        case .restricted: return false
        case .notDetermined: return nil
        default: return nil
        }
    }
}
