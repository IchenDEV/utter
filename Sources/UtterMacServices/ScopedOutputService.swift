import Foundation
import UtterContracts

struct DeliveryCompletion {
    let disposition: DeliveryDisposition
    var reason: String? = nil
    var anchor: (any OutputAnchor)? = nil
    var confirmation: DeliveryConfirmation = .none
}

@MainActor
final class ScopedOutputService: OutputService {
    typealias Execute = (DeliveryRequest, @escaping () -> Bool, @escaping (DeliveryEffect) -> Bool) async -> DeliveryCompletion
    private let isCurrent: () -> Bool
    private let execute: Execute
    private var closed = false
    private var active: OwnedDelivery?
    private var receipts: [UUID: DeliveryReceipt] = [:]

    init(isCurrent: @escaping () -> Bool, execute: @escaping Execute) {
        self.isCurrent = isCurrent
        self.execute = execute
    }

    func prepare(_ request: DeliveryRequest, isSessionCurrent: @escaping () -> Bool) throws -> any PreparedDelivery {
        guard !closed, isCurrent(), !Task.isCancelled else { throw DeliveryError.closed }
        if let receipt = receipts[request.id] { return ReplayedDelivery(receipt: receipt) }
        if let active {
            guard active.id == request.id else { throw DeliveryError.busy }
            return active
        }
        let delivery = OwnedDelivery(
            request: request, execute: execute,
            isCurrent: { [weak self] in
                guard let self else { return false }
                return !self.closed && self.isCurrent() && isSessionCurrent()
            },
            settle: { [weak self] receipt in
                // Idempotence retains no target, field, text, or observation source.
                self?.receipts[receipt.operationID] = DeliveryReceipt(
                    operationID: receipt.operationID, disposition: receipt.disposition,
                    effect: receipt.effect, reason: receipt.reason,
                    effects: receipt.effects, confirmation: receipt.confirmation
                )
            },
            release: { [weak self] in self?.active = nil }
        )
        active = delivery
        return delivery
    }

    func revoke() {
        guard !closed else { return }
        closed = true
        active?.revoke()
    }

    func close() async {
        revoke()
        await active?.close()
        receipts.removeAll()
    }
}

@MainActor
private final class OwnedDelivery: PreparedDelivery {
    let id: UUID
    private let request: DeliveryRequest
    private let execute: ScopedOutputService.Execute
    private let isCurrent: () -> Bool
    private let settle: (DeliveryReceipt) -> Void
    private let release: () -> Void
    private var committedEffects: Set<DeliveryEffect> = []
    private var revoked = false
    private var task: Task<DeliveryReceipt, Never>?
    private var closeTask: Task<Void, Never>?
    private(set) var receipt: DeliveryReceipt?

    init(request: DeliveryRequest, execute: @escaping ScopedOutputService.Execute,
         isCurrent: @escaping () -> Bool, settle: @escaping (DeliveryReceipt) -> Void, release: @escaping () -> Void) {
        id = request.id
        self.request = request
        self.execute = execute
        self.isCurrent = isCurrent
        self.settle = settle
        self.release = release
    }

    func commit() async -> DeliveryReceipt {
        if let receipt { return receipt }
        if Task.isCancelled { revoke() }
        if task == nil {
            task = Task {
                let completion: DeliveryCompletion
                if canCommit {
                    completion = await execute(request, { self.canCommit }, { self.markCommitted($0) })
                } else {
                    completion = DeliveryCompletion(disposition: .notCommitted)
                }
                let disposition: DeliveryDisposition
                if committedEffects.isEmpty {
                    disposition = .notCommitted
                } else {
                    disposition = completion.disposition == .accepted ? .accepted : .uncertain
                }
                let result = DeliveryReceipt(
                    operationID: id, disposition: disposition, effect: .none,
                    reason: completion.reason,
                    anchor: completion.anchor,
                    effects: committedEffects, confirmation: completion.confirmation
                )
                receipt = result
                settle(result)
                return result
            }
        }
        let task = task!
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private var canCommit: Bool { !revoked && !Task.isCancelled && isCurrent() }

    private func markCommitted(_ effect: DeliveryEffect) -> Bool {
        guard effect != .none, !committedEffects.contains(effect), canCommit else { return false }
        committedEffects.insert(effect)
        return true
    }

    func revoke() {
        revoked = true
        task?.cancel()
    }

    func close() async {
        if let closeTask { return await closeTask.value }
        revoke()
        let close = Task {
            if let task { _ = await task.value }
            release()
        }
        closeTask = close
        await close.value
    }
}

@MainActor
private final class ReplayedDelivery: PreparedDelivery {
    let receipt: DeliveryReceipt?
    init(receipt: DeliveryReceipt) { self.receipt = receipt }
    func commit() async -> DeliveryReceipt { receipt! }
    func close() async {}
}
