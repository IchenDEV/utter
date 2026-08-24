import Foundation

func L(_ key: String) -> String { key }

enum AppResources {
    static let bundle = Bundle.main
}

@main
enum IndustryLexiconDeterministicTest {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw TestFailure("expected the IndustryLexicons.json path")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let catalog = try IndustryLexiconCatalog.decode(data)
        try require(catalog.packs.count == 4, "expected four industry packs")
        try require(catalog.packs.allSatisfy { $0.terms.count >= 30 }, "each pack needs 30 terms")
        try require(
            catalog.packs.allSatisfy {
                IndustryLexiconSnapshot(pack: $0).recognitionPhrases.count <= 100
            },
            "an industry pack exceeded the 100-phrase ASR context budget"
        )

        let cases = evaluationCases
        let baseline = termRecall(cases, catalog: catalog, enhanced: false)
        let treatment = termRecall(cases, catalog: catalog, enhanced: true)
        let preservation = nonTargetPreservation(catalog: catalog)

        try require(treatment >= 0.90, "treatment term recall below 90%")
        try require(treatment - baseline >= 0.10, "term recall improvement below 10 points")
        try require(preservation == 1, "non-target text changed")
        try verifyPersonalPriority(catalog: catalog)

        print("Industry lexicon deterministic evaluation passed")
        print(String(format: "  baseline term recall: %.2f%%", baseline * 100))
        print(String(format: "  treatment term recall: %.2f%%", treatment * 100))
        print(String(format: "  absolute improvement: %.2f points", (treatment - baseline) * 100))
        print(String(format: "  non-target preservation: %.2f%%", preservation * 100))
    }

    private static let evaluationCases: [EvaluationCase] = [
        .init(.medical, "主愫是心季，糖化血红旦白偏高。", ["主诉", "心悸", "糖化血红蛋白"]),
        .init(.medical, "建议复查估算肾小球虑过率和C反映蛋白。", ["估算肾小球滤过率", "C反应蛋白"]),
        .init(.medical, "给予静脉低注，记录血氧包和度。", ["静脉滴注", "血氧饱和度"]),
        .init(.medical, "患者高血压，心电图已完成。", ["高血压", "心电图"]),
        .init(.legal, "本案超过诉讼实效，举证责认仍有争议。", ["诉讼时效", "举证责任"]),
        .init(.legal, "不可抗利与缔约过时责任需要分别审查。", ["不可抗力", "缔约过失责任"]),
        .init(.legal, "当事人提出管辖权意议并申请行政富议。", ["管辖权异议", "行政复议"]),
        .init(.legal, "法院已经采取财产保全措施。", ["财产保全"]),
        .init(.finance, "资产付债表和现金刘量表需要重编。", ["资产负债表", "现金流量表"]),
        .init(.finance, "按滩余成本计算递延所的税。", ["摊余成本", "递延所得税"]),
        .init(.finance, "流动性复盖率下降，逆回够规模上升。", ["流动性覆盖率", "逆回购"]),
        .init(.finance, "净现值为正，资本充足率保持稳定。", ["净现值", "资本充足率"]),
        .init(.technology, "云原声平台采用服务网各和持续急成。", ["云原生", "服务网格", "持续集成"]),
        .init(.technology, "可观测行依赖分布式追棕和幂等幸。", ["可观测性", "分布式追踪", "幂等性"]),
        .init(.technology, "检索增强生城使用向量数聚库。", ["检索增强生成", "向量数据库"]),
        .init(.technology, "软件物料清单用于供应链安全。", ["软件物料清单", "供应链安全"]),
    ]

    private static func termRecall(
        _ cases: [EvaluationCase],
        catalog: IndustryLexiconCatalog,
        enhanced: Bool
    ) -> Double {
        var matched = 0
        var expected = 0
        for item in cases {
            let output = enhanced
                ? apply(catalog.snapshot(for: item.industry), to: item.transcript)
                : item.transcript
            matched += item.expectedTerms.filter(output.contains).count
            expected += item.expectedTerms.count
        }
        return Double(matched) / Double(expected)
    }

    private static func nonTargetPreservation(catalog: IndustryLexiconCatalog) -> Double {
        let samples: [(IndustryLexiconID, String)] = [
            (.medical, "明天下午三点讨论项目排期。"),
            (.legal, "请把会议纪要发给团队。"),
            (.finance, "本周完成用户访谈和原型。"),
            (.technology, "周末去公园散步。"),
        ]
        let preserved = samples.filter { industry, text in
            apply(catalog.snapshot(for: industry), to: text) == text
        }.count
        return Double(preserved) / Double(samples.count)
    }

    private static func apply(_ snapshot: IndustryLexiconSnapshot, to text: String) -> String {
        let rules = snapshot.corrections.enumerated().map { offset, correction in
            VocabularyReplacementRule(
                original: correction.recognized,
                replacement: correction.preferred,
                sourcePriority: 1,
                insertionOrder: offset
            )
        }
        return VocabularyReplacementEngine.apply(rules, to: text)
    }

    private static func verifyPersonalPriority(catalog: IndustryLexiconCatalog) throws {
        let industry = catalog.snapshot(for: .medical).corrections.enumerated().map {
            VocabularyReplacementRule(
                original: $0.element.recognized,
                replacement: $0.element.preferred,
                sourcePriority: 1,
                insertionOrder: $0.offset
            )
        }
        let personal = VocabularyReplacementRule(
            original: "禁忌症",
            replacement: "禁用情况",
            sourcePriority: 0,
            insertionOrder: 0
        )
        try require(
            VocabularyReplacementEngine.apply([personal] + industry, to: "记录禁忌症")
                == "记录禁用情况",
            "personal correction did not outrank the industry pack"
        )
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw TestFailure(message) }
    }
}

private struct EvaluationCase {
    let industry: IndustryLexiconID
    let transcript: String
    let expectedTerms: [String]

    init(_ industry: IndustryLexiconID, _ transcript: String, _ expectedTerms: [String]) {
        self.industry = industry
        self.transcript = transcript
        self.expectedTerms = expectedTerms
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
