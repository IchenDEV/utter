import UtterRuntime

@MainActor
package protocol RemoteConnectionService: AnyObject {
    func test(configuration: RemoteGenerationConfiguration, modelID: String) async throws
}

extension GenerationServices {
    package static let connection = ServiceKey<any RemoteConnectionService>("generation.connection")
}
