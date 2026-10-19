import Foundation
import os

/// Per-module settings namespace: keys are stored as `module.<id>.<key>`.
@MainActor
public struct ModuleSettings {
    public let defaults: UserDefaults
    public let moduleID: String

    public init(defaults: UserDefaults, moduleID: String) {
        self.defaults = defaults
        self.moduleID = moduleID
    }

    public func key(_ name: String) -> String { "module.\(moduleID).\(name)" }

    public func value<T>(_ name: String, default fallback: T) -> T {
        defaults.object(forKey: key(name)) as? T ?? fallback
    }

    public func set(_ value: Any?, for name: String) {
        defaults.set(value, forKey: key(name))
    }
}

public struct ModuleLog: Sendable {
    public let logger: Logger

    public init(category: String) {
        logger = Logger(subsystem: "com.taegyu.tutilities", category: category)
    }
}

/// Persists which modules are enabled and the popover order.
@MainActor
public struct ModuleStateStore {
    static let enabledKey = "modules.enabled"
    static let orderKey = "modules.order"

    public let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func enabledIDs(descriptors: [ModuleDescriptor]) -> Set<String> {
        if let saved = defaults.stringArray(forKey: Self.enabledKey) {
            return Set(saved)
        }
        return Set(descriptors.filter(\.enabledByDefault).map(\.id))
    }

    public func saveEnabled(_ ids: Set<String>) {
        defaults.set(ids.sorted(), forKey: Self.enabledKey)
    }

    /// Saved order, with unknown IDs dropped and newly added modules appended in registration order.
    public func order(descriptors: [ModuleDescriptor]) -> [String] {
        let known = descriptors.map(\.id)
        let saved = (defaults.stringArray(forKey: Self.orderKey) ?? []).filter(known.contains)
        return saved + known.filter { !saved.contains($0) }
    }

    public func saveOrder(_ ids: [String]) {
        defaults.set(ids, forKey: Self.orderKey)
    }
}
