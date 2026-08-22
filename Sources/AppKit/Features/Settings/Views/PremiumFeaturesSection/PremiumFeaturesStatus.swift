import Common
import ComposableArchitecture

// MARK: - PremiumFeaturesStatus

public struct PremiumFeaturesStatus: Codable, Hashable {
  public var liveTranscriptionIsPurchased: Bool? = nil
  public var isProductFound: Bool? = nil
}

// MARK: - PremiumFeaturesProductID

public enum PremiumFeaturesProductID {
  public static let liveTranscription = "me.igortarasenko.Whisperboard.LiveTranscription"
}

public extension PersistenceReaderKey where Self == PersistenceKeyDefault<FilePersistenceKey<PremiumFeaturesStatus>> {
  static var premiumFeatures: Self {
    PersistenceKeyDefault(
      FilePersistenceKey(url: .documentsDirectory.appending(component: "premiumFeatures.json")),
      PremiumFeaturesStatus()
    )
  }
}
