import Foundation
import ComposableArchitecture

public extension PersistenceReaderKey where Self == PersistenceKeyDefault<FilePersistenceKey<IdentifiedArrayOf<RecordingInfo>>> {
  static var recordings: Self {
    PersistenceKeyDefault(
      FilePersistenceKey(url: .documentsDirectory.appending(component: "recordings.json")),
      []
    )
  }
}

public extension PersistenceReaderKey where Self == PersistenceKeyDefault<FilePersistenceKey<Settings>> {
  static var settings: Self {
    PersistenceKeyDefault(
      FilePersistenceKey(url: .documentsDirectory.appending(component: "settings.json")),
      Settings()
    )
  }
}

public extension PersistenceReaderKey where Self == PersistenceKeyDefault<InMemoryKey<IdentifiedArrayOf<TranscriptionTask>>> {
  static var transcriptionTasks: Self {
    PersistenceKeyDefault(.inMemory(#function), [])
  }
}

public extension PersistenceReaderKey where Self == PersistenceKeyDefault<InMemoryKey<Bool>> {
  static var isICloudSyncInProgress: Self {
    PersistenceKeyDefault(.inMemory(#function), false)
  }
}
