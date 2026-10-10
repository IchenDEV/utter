import Foundation

extension XiaomiRemoteMicBridge {
    func ownedTask(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            defer { self?.ownedTasks.removeValue(forKey: id) }
            await operation()
        }
        ownedTasks[id] = task
        return task
    }

    package func revoke() {
        guard !isClosed else { return }
        isClosed = true
        onSamples = nil
        onStreamStopped = nil
        onVoiceKeyPressed = nil
        onVoiceKeyReleased = nil
        deactivate()
        for task in ownedTasks.values { task.cancel() }
    }

    @MainActor
    package func close() async {
        revoke()
        for task in Array(ownedTasks.values) { await task.value }
        if pendingCentralRetirement != nil {
            await withCheckedContinuation { retirementWaiters.append($0) }
        }
    }
}
