import Foundation

package struct InputRecord: Codable, Identifiable {
    package let id: UUID
    package let date: Date
    package let rawText: String
    package let processedText: String
    package let rawCharCount: Int
    package let processedCharCount: Int
    package let wasProcessed: Bool
    package let context: InputContext?
    package let userFinalText: String?
    package let formatKind: TextFormatKind?
    package let deliveryStatus: DeliveryStatus?

    package var displayText: String {
        userFinalText ?? processedText
    }

    package init(
        rawText: String,
        processedText: String,
        wasProcessed: Bool,
        context: InputContext? = nil,
        userFinalText: String? = nil,
        formatKind: TextFormatKind? = nil,
        deliveryStatus: DeliveryStatus? = nil
    ) {
        self.init(
            id: UUID(),
            date: Date(),
            rawText: rawText,
            processedText: processedText,
            wasProcessed: wasProcessed,
            context: context,
            userFinalText: userFinalText,
            formatKind: formatKind,
            deliveryStatus: deliveryStatus
        )
    }

    package init(
        id: UUID,
        date: Date,
        rawText: String,
        processedText: String,
        wasProcessed: Bool,
        context: InputContext? = nil,
        userFinalText: String? = nil,
        formatKind: TextFormatKind? = nil,
        deliveryStatus: DeliveryStatus? = nil
    ) {
        self.id = id
        self.date = date
        self.rawText = rawText
        self.processedText = processedText
        self.rawCharCount = rawText.count
        self.processedCharCount = processedText.count
        self.wasProcessed = wasProcessed
        self.context = context
        self.userFinalText = userFinalText
        self.formatKind = formatKind
        self.deliveryStatus = deliveryStatus
    }

    package enum CodingKeys: String, CodingKey {
        case id, date, rawText, processedText, rawCharCount, processedCharCount, wasProcessed, context
        case userFinalText, formatKind, deliveryStatus
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        rawText = try container.decode(String.self, forKey: .rawText)
        processedText = try container.decode(String.self, forKey: .processedText)
        rawCharCount = try container.decodeIfPresent(Int.self, forKey: .rawCharCount) ?? rawText.count
        processedCharCount = try container.decodeIfPresent(Int.self, forKey: .processedCharCount) ?? processedText.count
        wasProcessed = try container.decode(Bool.self, forKey: .wasProcessed)
        context = try container.decodeIfPresent(InputContext.self, forKey: .context)
        userFinalText = try container.decodeIfPresent(String.self, forKey: .userFinalText)
        formatKind = try container.decodeIfPresent(TextFormatKind.self, forKey: .formatKind)
        deliveryStatus = try container.decodeIfPresent(DeliveryStatus.self, forKey: .deliveryStatus)
    }

    package func matchesSearch(_ query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return true }

        return [
            rawText,
            processedText,
            userFinalText,
            context?.appName,
            context?.bundleIdentifier,
            context?.windowTitle,
            context?.screenContext,
        ].contains { value in
            value?.lowercased().contains(normalized) == true
        }
    }
}

package struct InputStats {
    package let totalInputs: Int
    package let totalRawChars: Int
    package let totalProcessedChars: Int
    package let charsSaved: Int
    package let todayInputs: Int
    package let todayChars: Int
    package let streakDays: Int

    package var efficiencyRatio: Double {
        guard totalRawChars > 0 else { return 0 }
        return Double(charsSaved) / Double(totalRawChars)
    }

    package init(totalInputs: Int, totalRawChars: Int, totalProcessedChars: Int, charsSaved: Int, todayInputs: Int, todayChars: Int, streakDays: Int) {
        self.totalInputs = totalInputs
        self.totalRawChars = totalRawChars
        self.totalProcessedChars = totalProcessedChars
        self.charsSaved = charsSaved
        self.todayInputs = todayInputs
        self.todayChars = todayChars
        self.streakDays = streakDays
    }
}
