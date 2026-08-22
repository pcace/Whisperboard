import Common
import ComposableArchitecture

// MARK: - DebugSettings

public struct DebugSettings: Codable, Hashable {
  public var shouldOverridePurchaseStatus = false
  public var liveTranscriptionIsPurchasedOverride = false
}

public extension PersistenceReaderKey where Self == PersistenceKeyDefault<FilePersistenceKey<DebugSettings>> {
  static var debugSettings: Self {
    PersistenceKeyDefault(
      FilePersistenceKey(url: .documentsDirectory.appending(component: "debugSettings.json")),
      DebugSettings()
    )
  }
}
