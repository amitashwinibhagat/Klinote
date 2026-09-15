//
// KlinoteError.swift
//
// The error type for the core boundary. It lives in Domain rather than beside
// the FFI so that anything which needs to describe an engine failure can name
// one without linking the C ABI — which is what lets the note-writing path be
// exercised headlessly, outside the app.
//

import Foundation

enum KlinoteCoreError: LocalizedError {
    case engine(String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .engine(let message): message
        case .malformedResponse: "The engine returned a response Klinote could not read."
        }
    }
}
