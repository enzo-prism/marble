import Foundation

/// A render-time memoization box for expensive view-derived data.
///
/// SwiftUI re-evaluates `body` on every state change — including volatile UI
/// state like chart scrubbing or a toast appearing — which would otherwise
/// re-run costly derivations (filtering, grouping, and sorting thousands of
/// SwiftData models) on every frame. Holding a `RenderMemo` in `@State` lets a
/// view rebuild its derived data only when the real inputs change, keyed by a
/// cheap `Equatable` signature.
///
/// It is intentionally a *reference type* held in `@State`: mutating the cached
/// value from inside `body` is safe because the `@State`-stored reference never
/// changes (so SwiftUI doesn't treat it as a state mutation during the view
/// update), and the box is not `Observable`, so writes don't schedule another
/// render. Only the most recent key is retained — this is a single-slot cache,
/// which matches how a view re-derives one current snapshot at a time.
final class RenderMemo<Key: Equatable, Value> {
    private var key: Key?
    private var value: Value?

    init() {}

    /// Returns the cached value when `key` matches the last build, otherwise
    /// rebuilds via `build`, stores it under `key`, and returns it.
    func value(for key: Key, _ build: () -> Value) -> Value {
        if let value, self.key == key {
            return value
        }
        let rebuilt = build()
        self.key = key
        self.value = rebuilt
        return rebuilt
    }
}
