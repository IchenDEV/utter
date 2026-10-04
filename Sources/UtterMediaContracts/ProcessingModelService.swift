import UtterContracts
import UtterRuntime

@MainActor
package protocol ProcessingModelService: AnyObject {
    func prepare(_ options: TextProcessingOptions) async throws -> EspressoGenerationOutcome?
    func unload() async throws
    func benchmark(_ modelID: String) async throws -> ModelBenchmarkResult
}

extension ProcessingServices {
    package static let models = ServiceKey<any ProcessingModelService>("processing.models")
}
