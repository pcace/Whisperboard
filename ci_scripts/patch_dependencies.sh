#!/bin/sh
# Applies compatibility patches to SPM package checkouts so the project
# builds with Xcode 26.x / Swift 6.2 (the pinned packages are from 2024).
# Re-run after any `tuist install` / `tuist clean` (which restores the checkouts).
#
# Patches:
#  1. Pow 1.0.4            – `.pi` ambiguity in Anvil.swift -> `CGFloat.pi`
#  2. swift-dependencies-additions 1.0.2 – SPI `wrappedValue` no longer usable in
#     synthesized property-wrapper accessors -> make `wrappedValue` public
#  3. swift-dependencies-additions 1.0.2 – stub unused `UserNotificationsDependency`
#     (uses the same SPI wrappers)

set -e
cd "$(dirname "$0")/.."

checkouts=Tuist/.build/checkouts
POW="$checkouts/Pow/Sources/Pow/Transitions/Anvil.swift"
SDADD_BASICS="$checkouts/swift-dependencies-additions/Sources/DependenciesAdditionsBasics/Proxies.swift"
SDADD_UN="$checkouts/swift-dependencies-additions/Sources/UserNotificationsDependency/UserNotificationsDependency.swift"

echo "Patching Pow..."
if [ -f "$POW" ]; then
  perl -0pi -e 's/2 \* sin\(shakeT \* 3 \* \.pi\)/2 * sin(shakeT * 3 * CGFloat.pi)/g; s/4 \* sin\(shakeT \* 4 \* \.pi\)/4 * sin(shakeT * 4 * CGFloat.pi)/g; s/pow\(sin\(relativeX \* \.pi\), 0\.4\)/pow(sin(relativeX * CGFloat.pi), 0.4)/g; s/sin\(speckT \* \.pi\)/sin(speckT * CGFloat.pi)/g' "$POW"
  echo "  OK: Anvil.swift"
else
  echo "  SKIP: $POW not found (run tuist install first)"
fi

echo "Patching swift-dependencies-additions (SPI wrappedValue)..."
if [ -f "$SDADD_BASICS" ]; then
  perl -0pi -e 's/@_spi\(Internals\)\n(\s*)public var wrappedValue:/$1public var wrappedValue:/g' "$SDADD_BASICS"
  # clean up the broken "@_spi  public var wrappedValue" variant if the first pass left one
  perl -0pi -e 's/@_spi\s+public var wrappedValue:/public var wrappedValue:/g' "$SDADD_BASICS"
  echo "  OK: Proxies.swift"
else
  echo "  SKIP: $SDADD_BASICS not found"
fi

echo "Stubbing UserNotificationsDependency..."
if [ -f "$SDADD_UN" ]; then
  cat > "$SDADD_UN" <<'EOF'
#if os(iOS) || os(watchOS) || os(macOS)
  import Dependencies
  import UserNotifications

  extension DependencyValues {
    public var userNotificationCenter: UserNotificationCenter {
      get { self[UserNotificationCenter.self] }
      set { self[UserNotificationCenter.self] = newValue }
    }
  }

  public struct UserNotificationCenter: Sendable {
    public init() {}
  }

  extension UserNotificationCenter: DependencyKey {
    public static var liveValue: UserNotificationCenter { UserNotificationCenter() }
    public static var testValue: UserNotificationCenter { UserNotificationCenter() }
    public static var previewValue: UserNotificationCenter { UserNotificationCenter() }
  }
#endif
EOF
  echo "  OK: UserNotificationsDependency.swift (stubbed)"
else
  echo "  SKIP: $SDADD_UN not found"
fi

echo "Done."
