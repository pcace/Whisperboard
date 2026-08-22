import Dependencies
import Foundation
import Translation

// MARK: - LiveTranslationClient

/// A dependency client wrapping Apple's on-device Translation framework
/// (requires iOS 18.0+).
public struct LiveTranslationClient {
  /// Whether live translation is supported on this OS version (iOS 18.0+).
  public var isSupported: @Sendable () -> Bool
  /// Configures the target language and pre-downloads the language packs.
  public var configure: @Sendable (LiveTranslationConfiguration) async throws -> Void
  /// Translates a single string to the configured target language.
  public var translate: @Sendable (String) async throws -> String
  /// Stops translation and clears the session.
  public var reset: @Sendable () -> Void

  public init(
    isSupported: @escaping @Sendable () -> Bool,
    configure: @escaping @Sendable (LiveTranslationConfiguration) async throws -> Void,
    translate: @escaping @Sendable (String) async throws -> String,
    reset: @escaping @Sendable () -> Void
  ) {
    self.isSupported = isSupported
    self.configure = configure
    self.translate = translate
    self.reset = reset
  }
}

// MARK: - LiveTranslationConfiguration

public struct LiveTranslationConfiguration: Equatable, Sendable {
  /// BCP-47 language identifier of the target (output) language, e.g. "de".
  public var targetLanguage: String

  public init(targetLanguage: String) {
    self.targetLanguage = targetLanguage
  }
}

// MARK: DependencyKey

extension LiveTranslationClient: DependencyKey {
  public static let liveValue = LiveTranslationClient(
    isSupported: {
      if #available(iOS 18.0, *) { return true }
      return false
    },
    configure: { configuration in
      guard #available(iOS 18.0, *) else { throw LiveTranslationError.unsupportedOS }
      await MainActor.run {
        TranslationBridge.shared.configuration = .init(
          target: Locale.Language(identifier: configuration.targetLanguage)
        )
      }
      // Pre-download language packs; ignore failures (first translate() will retry).
      try? await TranslationBridge.shared.prepare()
    },
    translate: { text in
      guard #available(iOS 18.0, *) else { throw LiveTranslationError.unsupportedOS }
      return try await TranslationBridge.shared.translate(text)
    },
    reset: {
      if #available(iOS 18.0, *) {
        Task { @MainActor in
          TranslationBridge.shared.reset()
        }
      }
    }
  )
}
