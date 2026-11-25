import UtterContracts
import UtterMediaContracts
import UtterPresentationContracts
import UtterRuntime

@MainActor
extension ModelPlugins {
    package static func catalog() -> PluginRegistration {
        PluginRegistration(descriptor: PluginDescriptor(
            id: "models.catalog",
            requires: [DataServices.settings.required, ModelServices.resourceAccess.required,
                       ModelServices.textDownloads.required, IntegrationServices.diagnostics.required,
                       ModelServices.artifacts.required, SpeechServices.providers.optional],
            provides: [ModelServices.catalog.reference]
        )) { context, _ in
            let artifacts = try context.require(ModelServices.artifacts)
            let speech = try context.optional(SpeechServices.providers)
            let downloads = try context.require(ModelServices.textDownloads)
            let catalog = ModelCatalog(
                settings: AppSettings(service: try context.require(DataServices.settings)),
                log: Log(service: try context.require(IntegrationServices.diagnostics)),
                access: try context.require(ModelServices.resourceAccess),
                textDownloads: TextModelDownloadOperations(
                    download: { id, source, staging, progress in
                        try await downloads.download(id, source: source, downloadBase: staging.downloadBase,
                                                     cacheDirectory: staging.hubCache.cacheDirectory, progress: progress)
                    }, validate: { try await downloads.validate($0) },
                    downloadModelScope: { id, files, revision, staging, progress in
                        try await ModelScopeDownloads.download(
                            modelID: id,
                            revision: revision,
                            files: files,
                            to: ModelStorage.hubModelRepoDir(id, downloadBase: staging.downloadBase),
                            progress: progress
                        )
                    },
                    validateRequiredFiles: { directory, files in
                        guard ModelAssets.filesAreComplete(at: directory, requiredFiles: files) else {
                            let missing = files.filter {
                                let url = directory.appendingPathComponent($0)
                                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                                return size <= 0
                            }
                            throw ModelScopeError.missingFiles(missing)
                        }
                    }
                ), speechDescriptors: { speech?.descriptors ?? [] }
            )
            try context.scope.onReady { catalog.loadArtifacts(artifacts.artifacts); catalog.start() }
            try context.scope.onRevoke { catalog.revoke() }
            try context.scope.onDispose { await catalog.close() }
            try context.provide(ModelServices.catalog, value: catalog)
        }
    }
}
