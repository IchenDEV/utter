import Foundation

struct PlannedPlugin {
    let registration: PluginRegistration
    let selection: PluginSelection
}

extension PluginCatalog {
    func orderedRegistrations(_ selections: [PluginSelection]) throws -> [PlannedPlugin] {
        var selected: [String: PlannedPlugin] = [:]
        var suppliers: [String: (String, ServiceReference)] = [:]
        for selection in selections {
            guard selected[selection.id] == nil else { throw PluginRuntimeError.duplicatePlugin(selection.id) }
            let registration = try registration(selection.id)
            try registration.validateConfiguration(selection.configuration)
            selected[selection.id] = PlannedPlugin(registration: registration, selection: selection)
            for service in registration.descriptor.provides {
                guard suppliers[service.name] == nil else { throw PluginRuntimeError.duplicateService(service.name) }
                suppliers[service.name] = (selection.id, service)
            }
        }

        var dependencies: [String: Set<String>] = [:]
        for id in selected.keys.sorted() {
            guard let plugin = selected[id] else { continue }
            var names: Set<String> = []
            dependencies[id] = []
            for requirement in plugin.registration.descriptor.requires {
                let service = requirement.service
                guard names.insert(service.name).inserted else {
                    throw PluginRuntimeError.duplicateDependency(plugin: id, service: service.name)
                }
                guard let (owner, supplied) = suppliers[service.name] else {
                    if requirement.isOptional { continue }
                    throw PluginRuntimeError.missingService(plugin: id, service: service.name)
                }
                guard supplied == service else { throw PluginRuntimeError.serviceTypeMismatch(service.name) }
                guard owner != id else {
                    throw PluginRuntimeError.dependencyCycle([id, id])
                }
                dependencies[id, default: []].insert(owner)
            }
        }

        var ordered: [PlannedPlugin] = []
        while !dependencies.isEmpty {
            guard let id = dependencies.keys.sorted().first(where: { dependencies[$0]?.isEmpty == true }) else {
                throw PluginRuntimeError.dependencyCycle(cycle(in: dependencies))
            }
            if let plugin = selected[id] { ordered.append(plugin) }
            dependencies.removeValue(forKey: id)
            for key in dependencies.keys { dependencies[key]?.remove(id) }
        }
        return ordered
    }

    private func cycle(in dependencies: [String: Set<String>]) -> [String] {
        var path: [String] = []
        var current = dependencies.keys.sorted().first ?? ""
        while let next = dependencies[current]?.sorted().first {
            if let index = path.firstIndex(of: current) { return Array(path[index...]) + [current] }
            path.append(current)
            current = next
        }
        return path
    }
}
