import Foundation

package enum GenerationModelLocation: Equatable, Sendable { case directory, bundle, remote }
package enum RecognitionVocabulary: Equatable, Sendable { case all, personal }

package enum FrozenGenerationLocations: Equatable, Sendable {
    case unresolved
    case frozen(bundle: URL?, directory: URL?)
}

extension TextProcessingOptions {
    package func selecting(_ provider: ProviderDescriptor) -> Self {
        var resolved = self
        resolved.textProviderID = provider.id
        resolved.useRemoteLLM = provider.modelLocation == .remote
        resolved.localLLMBackend = provider.modelLocation == .bundle ? .espresso : .mlx
        return resolved
    }

    package func freezingModelLocations(using files: any ModelFilesService) -> Self {
        var frozen = self
        let directory = files.installedTextModelURL(llmModel)
        let bundle = espressoModelPath.isEmpty ? nil
            : URL(fileURLWithPath: NSString(string: espressoModelPath).expandingTildeInPath)
        frozen.modelLocations = .frozen(bundle: bundle, directory: directory)
        return frozen
    }
}
