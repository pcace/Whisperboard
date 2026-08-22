import ComposableArchitecture
import Foundation

// MARK: - FilePersistenceKey

/// A simple file-based persistence key that avoids TCA's generic `fileStorage`
/// machinery, which is miscompiled / crashes at runtime with newer Swift
/// toolchains (SIGSEGV during concrete-type metadata instantiation).
public struct FilePersistenceKey<Value: Codable & Sendable>: PersistenceKey, Sendable {
  private let url: URL

  public init(url: URL) {
    self.url = url
  }

  public var id: AnyHashable {
    url
  }

  public func load(initialValue: Value?) -> Value? {
    do {
      let data = try Data(contentsOf: url)
      return try JSONDecoder().decode(Value.self, from: data)
    } catch {
      return initialValue
    }
  }

  public func save(_ value: Value) {
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try JSONEncoder().encode(value).write(to: url, options: .atomic)
    } catch {
      // Best-effort persistence; ignore write errors.
    }
  }

  public func subscribe(
    initialValue: Value?,
    didSet: @Sendable @escaping (Value?) -> Void
  ) -> Shared<Value>.Subscription {
    // No external change notifications; all mutations flow through `save`.
    Shared.Subscription {}
  }
}
