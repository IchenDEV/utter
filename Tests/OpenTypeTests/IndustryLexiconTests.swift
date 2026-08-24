import XCTest
@testable import OpenType

final class IndustryLexiconTests: XCTestCase {
    private let catalog = IndustryLexiconCatalog.shared

    func testBundledCatalogHasFourValidatedIndustryPacks() {
        XCTAssertEqual(Set(catalog.packs.map(\.id)), Set([
            .medical, .legal, .finance, .technology,
        ]))
        XCTAssertFalse(catalog.version.isEmpty)
        XCTAssertFalse(catalog.rights.isEmpty)
        XCTAssertGreaterThanOrEqual(catalog.sources.count, 7)
        for pack in catalog.packs {
            XCTAssertGreaterThanOrEqual(pack.terms.count, 30, pack.id.rawValue)
            XCTAssertFalse(pack.sourceIDs.isEmpty, pack.id.rawValue)
        }
    }

    func testSelectedPackReachesRecognitionContextWithAliases() throws {
        let medical = try XCTUnwrap(catalog.pack(for: .medical))
        let snapshot = PersonalDictionarySnapshot(
            entries: [DictionaryEntry(original: "utter", replacement: "Utter")],
            editRules: [],
            industryLexicon: IndustryLexiconSnapshot(pack: medical)
        )

        XCTAssertEqual(snapshot.recognitionPhrases.first, "Utter")
        XCTAssertTrue(snapshot.recognitionPhrases.contains("糖化血红蛋白"))
        XCTAssertTrue(snapshot.recognitionPhrases.contains("HbA1c"))
        XCTAssertLessThanOrEqual(
            SpeechRecognitionContext(phrases: snapshot.recognitionPhrases).phrases.count,
            SpeechRecognitionContext.maximumPhraseCount
        )
    }

    func testPersonalRecognitionPhrasesKeepPriorityAtContextLimit() throws {
        let technology = try XCTUnwrap(catalog.pack(for: .technology))
        let personalEntries = (0..<95).map {
            DictionaryEntry(original: "spoken-\($0)", replacement: "PersonalTerm\($0)")
        }
        let snapshot = PersonalDictionarySnapshot(
            entries: personalEntries,
            editRules: [],
            industryLexicon: IndustryLexiconSnapshot(pack: technology)
        )

        XCTAssertEqual(snapshot.recognitionPhrases.count, 100)
        for index in 0..<95 {
            XCTAssertTrue(snapshot.recognitionPhrases.contains("PersonalTerm\(index)"))
        }
    }

    func testPersonalCorrectionWinsOverIndustryCorrection() throws {
        let medical = try XCTUnwrap(catalog.pack(for: .medical))
        let snapshot = PersonalDictionarySnapshot(
            entries: [DictionaryEntry(original: "禁忌症", replacement: "禁用情况")],
            editRules: [],
            industryLexicon: IndustryLexiconSnapshot(pack: medical)
        )

        XCTAssertEqual(snapshot.applyReplacements(to: "记录禁忌症"), "记录禁用情况")
    }

    func testIndustrySelectionPersistsAndDefaultsToGeneral() {
        let suiteName = "IndustryLexiconTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.industryLexicon, .general)

        settings.industryLexicon = .legal
        XCTAssertEqual(AppSettings(defaults: defaults).industryLexicon, .legal)
    }

    func testIndustryPromptIsCorrectionOnlyAndContainsCanonicalTerms() throws {
        let technology = try XCTUnwrap(catalog.pack(for: .technology))
        let snapshot = PersonalDictionarySnapshot(
            entries: [],
            editRules: [],
            industryLexicon: IndustryLexiconSnapshot(pack: technology)
        )
        let prompt = TextProcessor().systemPromptWithPersonalContext(
            "基础提示",
            inputLanguage: .chinese,
            dictionarySnapshot: snapshot
        )

        XCTAssertTrue(prompt.contains("软件技术行业词库"))
        XCTAssertTrue(prompt.contains("检索增强生成（RAG）"))
        XCTAssertTrue(prompt.contains("不要据此补充原文没有的信息"))
    }

    func testEvaluationMeetsTermAccuracyAndRegressionGates() {
        let cases = evaluationCases
        let baselineAccuracy = termAccuracy(cases: cases, enhanced: false)
        let enhancedAccuracy = termAccuracy(cases: cases, enhanced: true)

        XCTAssertGreaterThanOrEqual(enhancedAccuracy, 0.95)
        XCTAssertGreaterThanOrEqual(enhancedAccuracy - baselineAccuracy, 0.50)
        XCTAssertEqual(nonTargetPreservationRate, 1.0)
    }

    private var evaluationCases: [EvaluationCase] {
        [
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
    }

    private func termAccuracy(cases: [EvaluationCase], enhanced: Bool) -> Double {
        var hits = 0
        var total = 0
        for item in cases {
            let snapshot = catalog.snapshot(for: item.industry)
            let output = enhanced
                ? PersonalDictionarySnapshot(
                    entries: [],
                    editRules: [],
                    industryLexicon: snapshot
                ).applyReplacements(to: item.transcript)
                : item.transcript
            hits += item.expectedTerms.filter(output.contains).count
            total += item.expectedTerms.count
        }
        return total == 0 ? 0 : Double(hits) / Double(total)
    }

    private var nonTargetPreservationRate: Double {
        let samples: [(IndustryLexiconID, String)] = [
            (.medical, "明天下午三点讨论项目排期。"),
            (.legal, "请把会议纪要发给团队。"),
            (.finance, "本周完成用户访谈和原型。"),
            (.technology, "周末去公园散步。"),
        ]
        let preserved = samples.filter { industry, text in
            PersonalDictionarySnapshot(
                entries: [],
                editRules: [],
                industryLexicon: catalog.snapshot(for: industry)
            ).applyReplacements(to: text) == text
        }.count
        return Double(preserved) / Double(samples.count)
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
