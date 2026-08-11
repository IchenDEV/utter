import Foundation

enum PromptStylePrompts {
    static func customStyleSection(stylePrompt: String, inputLanguage: InputLanguage) -> String? {
        guard !stylePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        switch inputLanguage {
        case .auto, .chinese, .cantonese:
            return "自定义风格：\(stylePrompt)"
        case .english:
            return "Custom style: \(stylePrompt)"
        case .japanese:
            return "カスタムスタイル：\(stylePrompt)"
        case .korean:
            return "사용자 지정 스타일: \(stylePrompt)"
        }
    }

    static func section(style: LanguageStyle, inputLanguage: InputLanguage) -> String {
        switch (inputLanguage, style) {
        case (.auto, .casual):
            return "风格：自动语言、自然直接。先判断原文主要语言并保持；保留自然混排。主动修正明显误识别、同音词、断句和语序小问题，但不要过度书面化，也不要无故翻译。"
        case (.chinese, .casual):
            return "风格：自然、直接。保留口语感，但仍要主动修正明显错别字、同音词、断句和语序小问题；不要把明显识别错误原样留下，也不要过度书面化。"
        case (.cantonese, .casual):
            return "风格：自然粤语、直接。保留粤语口语感和必要语气词，主动修正明显粤语误识别、断句和专有名词；不要默认改成普通话书面中文。"
        case (.auto, .professional):
            return "风格：自动语言专业整理。先判断原文主要语言和混排方式，再做纠错和表达整理。保持原语言；中文、英文、日文、韩文、粤语和中英日韩混排都要自然。无序清单用项目符号，只有明确顺序或步骤时才使用 1. 2. 3.。"
        case (.chinese, .professional):
            return "风格：专业整理。先做忠实纠错，再整理表达。对有明确上下文依据的同音错字、近音错字、专有名词大小写和中英混排要主动修正；把已完整表达的口语整理成自然书面句子，没说完的片段仍保持未完。结构清楚；无序清单用项目符号，只有明确顺序或步骤时才使用 1. 2. 3.。"
        case (.cantonese, .professional):
            return "风格：粤语专业整理。先做粤语误识别纠错，再整理表达。保留自然粤语书面表达、必要语气词和中英混排；对专有名词、技术词和英文大小写要更主动。无序清单用项目符号，只有明确顺序或步骤时才使用 1. 2. 3.。"
        case (.auto, .custom), (.chinese, .custom), (.cantonese, .custom):
            return ""
        case (.english, .professional):
            return "Style: professional cleanup. Apply faithful correction before polishing. Actively fix homophones, ASR substitutions, proper nouns, capitalization, and mixed-language terms when context clearly supports the change. Turn fully expressed speech into natural written sentences, but keep unfinished fragments unfinished. Keep the structure crisp. Use bullets for unordered collections and 1. 2. 3. only for explicit sequences or steps."
        case (.english, .casual):
            return "Style: natural and direct. Keep an easy spoken tone, but still actively fix obvious typos, homophones, sentence breaks, and small wording mistakes. Do not leave clear ASR errors in place."
        case (.japanese, .professional):
            return "スタイル：専門的に整理。忠実な補正を先に行い、その後で表現を整える。文脈に明確な根拠がある固有名詞、英字表記、誤認識、言い直しを補正し、最後まで述べられた内容だけを自然で明確な日本語にする。言いかけは未完のまま残す。順序のないリストは箇条書き、明確な手順だけ 1. 2. 3. を使う。"
        case (.japanese, .casual):
            return "スタイル：自然で直接的。話し言葉の軽さは残しつつ、明らかな誤認識、同音語、句読点、文の区切りは積極的に直す。"
        case (.korean, .professional):
            return "스타일: 전문적으로 정리. 먼저 충실하게 보정하고 그다음 표현을 다듬는다. 문맥에 분명한 근거가 있는 고유명사, 영문 표기, 오인식, 말 바꿈을 바로잡고 끝까지 표현된 내용만 자연스럽고 명확한 한국어로 만든다. 미완성 발화는 그대로 미완성으로 둔다. 순서 없는 목록은 글머리표로, 명확한 단계만 1. 2. 3.으로 쓴다."
        case (.korean, .casual):
            return "스타일: 자연스럽고 직접적으로. 말의 편안함은 유지하되 명백한 오인식, 동음이의어, 문장 부호, 문장 경계는 적극적으로 바로잡는다."
        case (.english, .custom), (.japanese, .custom), (.korean, .custom):
            return ""
        }
    }

    static func fewShotSection(style: LanguageStyle, inputLanguage: InputLanguage) -> String {
        switch (inputLanguage, style) {
        case (.auto, .professional):
            return """
            自动语言专业整理补充示例：
            原文：um we're meeting Thursday sorry Friday afternoon
            Output: We're meeting Friday afternoon.

            原文：えっと木曜じゃなくて金曜の午後に会議
            出力：金曜の午後に会議します。

            原文：啱啱講錯咗唔係星期四係星期五下晝開會
            输出：啱啱講錯咗，唔係星期四，係星期五下晝開會。

            原文：把 open type 的 hot key 文案改一下不要影响菜单蓝
            输出：把 OpenType 的 hotkey 文案改一下，不要影响菜单栏。
            """
        case (.chinese, .professional):
            return """
            专业整理补充示例：
            原文：今天有三件事第一把需求对齐第二把排期确认第三把预算更新一下
            输出：
            1. 把需求对齐。
            2. 确认排期。
            3. 更新预算。

            原文：今天主要是把登录问题修掉然后回归一遍没问题的话明天发版
            输出：今天主要是把登录问题修掉，然后回归一遍，没问题的话明天发版。

            原文：这周重点一个是稳定注册流程一个是补完埋点最后把文档更新掉
            输出：
            - 稳定注册流程。
            - 补完埋点。
            - 更新文档。

            专业整理强纠错示例：
            原文：把 open type 的 hot key 文案改一下不要影响菜单蓝
            输出：把 OpenType 的 hotkey 文案改一下，不要影响菜单栏。

            原文：这次发版先看登录留成有没有问题再看数据库前一有没有慢查询
            输出：这次发版先看登录流程有没有问题，再看数据库迁移有没有慢查询。
            """
        case (.cantonese, .professional):
            return """
            粤语专业整理补充示例：
            原文：啱啱講錯咗唔係星期四係星期五下晝開會
            输出：啱啱講錯咗，唔係星期四，係星期五下晝開會。

            原文：第一先對需求第二 confirm 個時間第三 update budget
            输出：
            1. 先對需求。
            2. Confirm 個時間。
            3. Update budget。

            粤语强纠错示例：
            原文：幫我將 open type 個 hot key 文案改一改唔好影響 menu bar
            输出：幫我將 OpenType 個 hotkey 文案改一改，唔好影響 menu bar。
            """
        case (.english, .professional):
            return """
            Professional cleanup examples:
            Raw: there are three things today first align the requirements second confirm the schedule third update the budget
            Output:
            1. Align the requirements.
            2. Confirm the schedule.
            3. Update the budget.

            Raw: today the main thing is fixing the login issue and then running regression and if that looks fine we'll ship tomorrow
            Output: Today the main thing is fixing the login issue, then running regression, and if that looks fine, we'll ship tomorrow.

            Raw: this week the priorities are stabilizing signup finishing the tracking work and updating the docs
            Output:
            - Stabilize signup.
            - Finish the tracking work.
            - Update the docs.

            Strong correction examples:
            Raw: update the open type hot key copy and do not affect the menu bore
            Output: Update the OpenType hotkey copy, and do not affect the menu bar.

            Raw: check the log in floor before release and then check whether the database migration has slow queries
            Output: Check the login flow before release, then check whether the database migration has slow queries.
            """
        case (.japanese, .professional):
            return """
            専門整理の補足例：
            原文：今日やることは第一に仕様確認第二に日程調整第三に予算更新
            出力：
            1. 仕様を確認する。
            2. 日程を調整する。
            3. 予算を更新する。

            強い誤認識補正の例：
            原文：オープンタイプのホットキー文言を直してメニューバーに影響しないように
            出力：OpenType の hotkey 文言を直して、メニューバーに影響しないようにする。
            """
        case (.korean, .professional):
            return """
            전문 정리 보충 예시:
            원문：오늘 할 일은 첫째 요구사항 확인 둘째 일정 조율 셋째 예산 업데이트
            출력：
            1. 요구사항을 확인한다.
            2. 일정을 조율한다.
            3. 예산을 업데이트한다.

            강한 오인식 보정 예시:
            원문：오픈 타입 핫키 문구를 고치고 메뉴 바에는 영향 없게 해줘
            출력：OpenType hotkey 문구를 고치고, 메뉴 바에는 영향이 없게 해줘.
            """
        case (.auto, .casual), (.chinese, .casual), (.cantonese, .casual),
             (.auto, .custom), (.chinese, .custom), (.cantonese, .custom),
             (.english, .casual), (.japanese, .casual), (.korean, .casual),
             (.english, .custom), (.japanese, .custom), (.korean, .custom):
            return ""
        }
    }
}
