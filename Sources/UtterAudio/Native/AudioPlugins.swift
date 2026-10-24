import UtterContracts
import UtterMediaContracts
import UtterRuntime

@MainActor
package enum AudioPlugins {
    package static func capture() -> PluginRegistration {
        capture { request, remote, log in
            switch request.source {
            case .local: return LocalCaptureDriver(log: log)
            case .remote:
                guard let remote else { throw CaptureError.remoteUnavailable }
                return RemoteCaptureDriver(source: remote)
            }
        }
    }

    static func capture(
        makeDriver: @escaping (CaptureRequest, (any RemoteCaptureSource)?, Log) throws -> any CaptureDriver
    ) -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: "audio.capture",
            requires: [RemoteMicServices.capture.optional, IntegrationServices.diagnostics.required],
            provides: [AudioServices.capture.reference]
        )) { context, _ in
            let remote = try context.optional(RemoteMicServices.capture)
            let log = Log(service: try context.require(IntegrationServices.diagnostics))
            let service = ScopedCaptureService(isCurrent: { context.isCurrent }) { try makeDriver($0, remote, log) }
            try context.scope.onRevoke { service.revoke() }
            try context.scope.onDispose { await service.close() }
            try context.provide(AudioServices.capture, value: service)
        }
    }
}
