package actor EvaluationTokenBudget {
    package let limit: Int
    package private(set) var reserved = 0
    package init(limit: Int) { self.limit = limit }
    package func reserve(_ requested: Int) throws -> Int {
        guard requested > 0, reserved < limit else { throw VoiceEvaluationError.tokenBudgetExceeded }
        let allowed = min(requested, limit - reserved)
        reserved += allowed
        return allowed
    }
}
