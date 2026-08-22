import Foundation
import SwiftUI
import Translation

// MARK: - LiveTranslationError

public enum LiveTranslationError: LocalizedError {
  case unsupportedOS
  case sessionNotAvailable

  public var errorDescription: String? {
    switch self {
    case .unsupportedOS:
      return "Live translation requires iOS 18.0 or later."
    case .sessionNotAvailable:
      return "The translation session is not available yet."
    }
  }
}

// MARK: - TranslationBridge

/// Bridges the SwiftUI-managed `TranslationSession` to the rest of the app so
/// that translations can be triggered from anywhere (e.g. from the
/// `TranscriptionStream` actor) without needing a view context.
@available(iOS 18.0, *)
public final class TranslationBridge: ObservableObject {
  public static let shared = TranslationBridge()

  /// The active translation configuration. Set this to start translation,
  /// set it to `nil` (or call `reset`) to stop.
  @Published public var configuration: TranslationSession.Configuration? {
    didSet {
      // A new configuration invalidates the previous session.
      Task { @MainActor in
        self.invalidateSession()
      }
    }
  }

  @MainActor private var session: TranslationSession?
  @MainActor private var waiters: [CheckedContinuation<TranslationSession, Error>] = []

  private init() {}

  /// Called from `TranslationHostView` whenever a session becomes available.
  @MainActor
  public func updateSession(_ newSession: TranslationSession) {
    session = newSession
    let waiters = self.waiters
    self.waiters.removeAll()
    for waiter in waiters {
      waiter.resume(returning: newSession)
    }
  }

  @MainActor
  private func invalidateSession() {
    session = nil
    let waiters = self.waiters
    self.waiters.removeAll()
    for waiter in waiters {
      waiter.resume(throwing: LiveTranslationError.sessionNotAvailable)
    }
  }

  @MainActor
  public func reset() {
    configuration = nil
    invalidateSession()
  }

  /// Pre-downloads the required language packs.
  @MainActor
  public func prepare() async throws {
    guard configuration != nil else { throw LiveTranslationError.sessionNotAvailable }
    let session = try await currentSession()
    try await session.prepareTranslation()
  }

  /// Translates a single string to the configured target language.
  @MainActor
  public func translate(_ text: String) async throws -> String {
    let session = try await currentSession()
    let response = try await session.translate(text)
    return response.targetText
  }

  @MainActor
  private func currentSession() async throws -> TranslationSession {
    if let session { return session }
    return try await withCheckedThrowingContinuation { continuation in
      waiters.append(continuation)
    }
  }
}

// MARK: - TranslationHostView

/// An invisible view that hosts the `TranslationSession` for the whole app.
/// Attach it somewhere always visible, e.g. as a background of `AppView`.
@available(iOS 18.0, *)
public struct TranslationHostView: View {
  @ObservedObject private var bridge: TranslationBridge

  public init(bridge: TranslationBridge = .shared) {
    self.bridge = bridge
  }

  public var body: some View {
    Color.clear
      .frame(width: 0, height: 0)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
      .translationTask(bridge.configuration) { session in
        bridge.updateSession(session)
      }
  }
}

// MARK: - TranslationLanguage

/// A language that Apple's on-device translation supports (iOS 18+).
public struct TranslationLanguage: Identifiable, Equatable, Sendable {
  public let code: String
  public let displayName: String

  public var id: String { code }

  public init(code: String, displayName: String) {
    self.code = code
    self.displayName = displayName
  }
}

public extension TranslationLanguage {
  /// The languages supported by Apple's on-device Translation framework.
  static let appleSupported: [TranslationLanguage] = [
    TranslationLanguage(code: "ar", displayName: "Arabic"),
    TranslationLanguage(code: "zh-Hans", displayName: "Chinese (Simplified)"),
    TranslationLanguage(code: "zh-Hant", displayName: "Chinese (Traditional)"),
    TranslationLanguage(code: "nl", displayName: "Dutch"),
    TranslationLanguage(code: "en", displayName: "English"),
    TranslationLanguage(code: "fr", displayName: "French"),
    TranslationLanguage(code: "de", displayName: "German"),
    TranslationLanguage(code: "id", displayName: "Indonesian"),
    TranslationLanguage(code: "it", displayName: "Italian"),
    TranslationLanguage(code: "ja", displayName: "Japanese"),
    TranslationLanguage(code: "ko", displayName: "Korean"),
    TranslationLanguage(code: "pl", displayName: "Polish"),
    TranslationLanguage(code: "pt", displayName: "Portuguese"),
    TranslationLanguage(code: "ru", displayName: "Russian"),
    TranslationLanguage(code: "es", displayName: "Spanish"),
    TranslationLanguage(code: "th", displayName: "Thai"),
    TranslationLanguage(code: "tr", displayName: "Turkish"),
    TranslationLanguage(code: "uk", displayName: "Ukrainian"),
    TranslationLanguage(code: "vi", displayName: "Vietnamese"),
  ]
}
