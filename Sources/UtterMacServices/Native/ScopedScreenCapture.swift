import Foundation
import UtterContracts
import UtterMediaContracts
import UtterRuntime

@MainActor
extension MacPlugins {
    package static func screen() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: "mac.screen", requires: [IntegrationServices.diagnostics.required], provides: [MacServices.screen.reference]
        )) { context, _ in
            let log = Log(service: try context.require(IntegrationServices.diagnostics))
            let service = ScopedScreenCapture(isCurrent: { context.isReady },
                capture: { await ScreenOCR.capture(mode: $0, excludedWindowIDs: $1, log: log) },
                checkPermission: { await ScreenOCR.checkScreenCapturePermission() },
                requestPermission: { ScreenOCR.requestPermissionIfNeeded() }
            )
            try context.scope.onRevoke { service.revoke() }
            try context.scope.onDispose { await service.close() }
            try context.provide(MacServices.screen, value: service)
        }
    }
}

@MainActor
final class ScopedScreenCapture: ScreenCaptureService {
    private let isCurrent: () -> Bool
    private let captureScreen: (ScreenContextMode, Set<UInt32>) async -> ScreenContextSnapshot
    private var excludedWindowIDs: Set<UInt32> = []
    private let permission: () async -> Bool
    private let request: () -> Void
    private var closed = false
    private var operations: [UUID: () async -> Void] = [:]
    private var cancellations: [UUID: () -> Void] = [:]

    init(isCurrent: @escaping () -> Bool, capture: @escaping (ScreenContextMode, Set<UInt32>) async -> ScreenContextSnapshot,
         checkPermission: @escaping () async -> Bool, requestPermission: @escaping () -> Void) {
        self.isCurrent = isCurrent
        captureScreen = capture
        permission = checkPermission
        request = requestPermission
    }

    func capture(mode: ScreenContextMode) async throws -> ScreenContextSnapshot {
        let exclusions = excludedWindowIDs
        return try await run { await self.captureScreen(mode, exclusions) }
    }

    func excludeWindow(_ id: UInt32) {
        guard !closed, isCurrent() else { return }
        excludedWindowIDs.insert(id)
    }

    func includeWindow(_ id: UInt32) { excludedWindowIDs.remove(id) }

    func checkPermission() async throws -> Bool { try await run(permission) }

    func requestPermission() {
        guard !closed, isCurrent(), !Task.isCancelled else { return }
        request()
    }

    private func run<Value>(_ operation: @escaping () async -> Value) async throws -> Value {
        guard !closed, isCurrent(), !Task.isCancelled else { throw CancellationError() }
        let id = UUID()
        let task = Task { await operation() }
        operations[id] = { _ = await task.value }
        cancellations[id] = { task.cancel() }
        defer { operations[id] = nil; cancellations[id] = nil }
        return try await withTaskCancellationHandler {
            let value = await task.value
            guard !closed, isCurrent(), !Task.isCancelled else { throw CancellationError() }
            return value
        } onCancel: {
            task.cancel()
        }
    }

    func revoke() {
        guard !closed else { return }
        closed = true
        excludedWindowIDs.removeAll()
        for cancel in cancellations.values { cancel() }
    }

    func close() async {
        revoke()
        for drain in Array(operations.values) { await drain() }
    }
}
