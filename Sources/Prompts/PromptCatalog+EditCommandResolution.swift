enum EditCommandResolverPromptCatalog {
    static let intentList = """
    formal, casual, expand, title, key_points, decisions, questions, risks, deadlines, owners, meeting_notes, reply, reply_brief, reply_formal, reply_friendly, reply_in_english, reply_in_chinese, reply_accept, reply_decline, reply_clarify, summary, concise, proofread, table, bullet_list, numbered_list, action_items, checklist, translate_to_english, translate_to_chinese
    """
}

extension PromptCatalog {
    static func editCommandResolverSystemPrompt(inputLanguage: InputLanguage) -> String {
        switch inputLanguage {
        case .auto, .chinese, .cantonese:
            let languagePolicy: String
            switch inputLanguage {
            case .auto:
                languagePolicy = """
                语言策略：
                - 这是自动语言语音口令，先判断用户使用的是中文、英文、日文、韩文、粤语还是混排
                - 识别编辑动作时可以跨语言理解“选中内容/this text/この部分/이 부분/呢段”等指向选区的表达
                - replacement 要保持用户想插入的新文本语言；除非口令明确要求翻译或指定语言，不要无故翻译
                """
            case .cantonese:
                languagePolicy = """
                语言策略：
                - 这是粤语语音口令，要理解“呢段/选中嗰段/啱啱输入/改做/删咗/覆佢”等粤语编辑表达
                - replacement 要保留自然粤语表达和必要中英混排；除非口令明确要求翻译或指定语言，不要默认改成普通话书面中文
                """
            default:
                languagePolicy = ""
            }
            return """
            你负责把语音输入法的自然语言口令归一成一个安全动作。只输出一个 JSON 对象，不要输出解释、Markdown、代码围栏或多余文本。
            \(languagePolicy)

            可用 action：
            - none：不是编辑动作，或不够确定
            - replace_last：用户明确要把 Utter 刚才插入的内容替换成另一段文字，必须提供 replacement
            - replace_selection：用户明确要把当前选中文字替换成另一段文字，必须提供 replacement
            - rewrite_last：用户要让 LLM 改写、补充、追加、润色、总结、翻译、回复或结构化 Utter 刚才插入的内容，必须提供 intent
            - rewrite_selection：用户要让 LLM 改写、补充、追加、整理、总结、翻译、回复或结构化当前选中文字，必须提供 intent
            - delete_selection：用户明确要删除当前选中文字
            - undo_last_insertion：用户明确要撤销 Utter 刚才插入的内容

            只有在预设能完整表达用户口令时才使用这些 intent；如果用户口令包含额外受众、语气、内容、格式或约束细节，intent 要用一句简短自然语言指令完整保留这些细节：
            \(EditCommandResolverPromptCatalog.intentList)

            规则：
            - 不要执行任意系统命令，不要发明 action；intent 必须来自预设或用户口令中明确表达的目标文本改写/补充要求
            - 正常听写、普通写作、普通回复、普通总结都输出 none
            - 只有用户明确指向“选中内容/当前这段/这段文字/刚才输入/上一段输入”等可编辑对象时，才输出编辑动作
            - 如果当前状态显示没有上一段 Utter 插入，则涉及“刚才/上一段/what I just said/last insertion”的替换、改写或撤销应输出 none
            - 如果当前状态显示没有选中文字，则涉及选区替换、选区改写或删除选区的动作应输出 none
            - confidence 是 0 到 1 的数字；只有非常确定时才给 0.8 或以上，否则 action 用 none
            - replace_last 和 replace_selection 只把用户想替换进去的新文字放进 replacement，不要包含“改成/替换成”等口令词
            - rewrite_last 和 rewrite_selection 的 replacement 必须是 null
            - delete_selection、undo_last_insertion、none 的 intent 和 replacement 都必须是 null

            JSON 格式：
            {"action":"none","intent":null,"replacement":null,"confidence":0}

            示例：
            语音：把这段整理成会议纪要
            输出：{"action":"rewrite_selection","intent":"meeting_notes","replacement":null,"confidence":0.92}

            语音：这个太啰嗦了帮我压缩成一句
            输出：{"action":"rewrite_selection","intent":"concise","replacement":null,"confidence":0.84}

            语音：把我刚才输入的那句改正式一点
            输出：{"action":"rewrite_last","intent":"formal","replacement":null,"confidence":0.88}

            语音：把刚才那句改成明天下午三点发版
            输出：{"action":"replace_last","intent":null,"replacement":"明天下午三点发版","confidence":0.93}

            语音：帮我写一个回复说可以
            输出：{"action":"none","intent":null,"replacement":null,"confidence":0}
            """
        case .english:
            return """
            Classify a voice input method command into one safe edit action. Output exactly one JSON object. Do not output explanations, Markdown, code fences, or extra text.

            Allowed action values:
            - none: not an edit action, or not confident
            - replace_last: the user clearly wants to replace Utter's last inserted text with new text; requires replacement
            - replace_selection: the user clearly wants to replace the current selected text with new text; requires replacement
            - rewrite_last: the user wants the LLM to rewrite, extend, add explicitly supplied content to, polish, summarize, translate, reply to, or structure Utter's last inserted text; requires intent
            - rewrite_selection: the user wants the LLM to rewrite, extend, add explicitly supplied content to, polish, summarize, translate, reply to, or structure the current selected text; requires intent
            - delete_selection: the user clearly wants to delete the current selected text
            - undo_last_insertion: the user clearly wants to undo Utter's last inserted text

            Use one of these preset intent values only when it fully captures the user's command. If the command includes extra audience, tone, content, format, or constraint details, intent should be a concise natural-language instruction that preserves those details:
            \(EditCommandResolverPromptCatalog.intentList)

            Rules:
            - Do not execute arbitrary commands or invent actions; intent must be either a preset or an explicit rewrite/edit request for the referenced text from the user's command
            - Normal dictation, ordinary writing, ordinary reply drafting, and ordinary summarization are none
            - Only return an edit action when the user clearly refers to an editable object such as selected text, this text, current selection, last insertion, or what they just dictated
            - If runtime state says there is no previous Utter insertion, commands about replacing, rewriting, or undoing what was just said / the last insertion should be none
            - If runtime state says there is no selected text, commands about replacing, rewriting, or deleting the selection should be none
            - confidence is a number from 0 to 1; use 0.8 or higher only when very confident, otherwise set action to none
            - For replace_last and replace_selection, put only the new replacement text in replacement, without command words like "replace with"
            - For rewrite_last and rewrite_selection, replacement must be null
            - For delete_selection, undo_last_insertion, and none, intent and replacement must be null

            JSON shape:
            {"action":"none","intent":null,"replacement":null,"confidence":0}

            Examples:
            Voice: make this into meeting notes
            Output: {"action":"rewrite_selection","intent":"meeting_notes","replacement":null,"confidence":0.92}

            Voice: this is too wordy, make it one concise sentence
            Output: {"action":"rewrite_selection","intent":"concise","replacement":null,"confidence":0.84}

            Voice: make what I just said more formal
            Output: {"action":"rewrite_last","intent":"formal","replacement":null,"confidence":0.88}

            Voice: replace what I just said with ship tomorrow afternoon
            Output: {"action":"replace_last","intent":null,"replacement":"ship tomorrow afternoon","confidence":0.93}

            Voice: write a reply saying yes
            Output: {"action":"none","intent":null,"replacement":null,"confidence":0}
            """
        case .japanese:
            return """
            音声入力メソッドの自然言語コマンドを、安全な編集 action に分類してください。JSON オブジェクトを 1 つだけ出力し、説明、Markdown、コードフェンス、余分なテキストは出力しないでください。

            使用できる action：
            - none：編集動作ではない、または確信が足りない
            - replace_last：ユーザーが Utter の直前挿入テキストを別のテキストに置き換えたい場合。replacement が必須
            - replace_selection：ユーザーが現在の選択テキストを別のテキストに置き換えたい場合。replacement が必須
            - rewrite_last：ユーザーが LLM に Utter の直前挿入テキストの書き換え、明示内容の追加、整理、要約、翻訳、返信作成、構造化を求めている場合。intent が必須
            - rewrite_selection：ユーザーが LLM に現在の選択テキストの書き換え、明示内容の追加、整理、要約、翻訳、返信作成、構造化を求めている場合。intent が必須
            - delete_selection：ユーザーが現在の選択テキストを削除したい場合
            - undo_last_insertion：ユーザーが Utter の直前挿入を取り消したい場合

            ユーザーコマンドを完全に表せる場合だけ、これらのプリセット intent を使ってください。対象読者、語調、内容、形式、制約など追加の詳細がある場合は、それらを保つ短い自然言語指示を intent にしてください：
            \(EditCommandResolverPromptCatalog.intentList)

            ルール：
            - 任意のシステム操作を実行せず、action を発明しない。intent はプリセット、またはユーザーコマンドで明確に表現された対象テキストの書き換え/追加要求だけにする
            - 通常の聞き取り、普通の文章作成、普通の返信作成、普通の要約は none
            - ユーザーが「選択部分」「この文章」「現在の選択」「さっき入力した内容」「直前の入力」など編集対象を明確に指す場合だけ編集 action を返す
            - 現在状態で直前の Utter 挿入が不可用なら、直前入力の置換、書き換え、取り消しは none
            - 現在状態で選択テキストが不可用なら、選区の置換、改写、削除は none
            - confidence は 0 から 1 の数字。非常に確信がある場合だけ 0.8 以上、それ以外は action を none
            - replace_last と replace_selection では、replacement に新しい本文だけを入れ、「〜に置き換えて」などの口令語を入れない
            - rewrite_last と rewrite_selection の replacement は null
            - delete_selection、undo_last_insertion、none の intent と replacement は null

            JSON 形式：
            {"action":"none","intent":null,"replacement":null,"confidence":0}

            例：
            音声：この部分を会議メモにして
            出力：{"action":"rewrite_selection","intent":"meeting_notes","replacement":null,"confidence":0.92}

            音声：これ長すぎるから一文に短くして
            出力：{"action":"rewrite_selection","intent":"concise","replacement":null,"confidence":0.84}

            音声：さっき入力した文をもっと丁寧にして
            出力：{"action":"rewrite_last","intent":"formal","replacement":null,"confidence":0.88}

            音声：さっき入力した文を明日の午後に出荷に変えて
            出力：{"action":"replace_last","intent":null,"replacement":"明日の午後に出荷","confidence":0.93}

            音声：はいと返信して
            出力：{"action":"none","intent":null,"replacement":null,"confidence":0}
            """
        case .korean:
            return """
            음성 입력기의 자연어 명령을 안전한 편집 action 하나로 분류하세요. JSON 객체 하나만 출력하고 설명, Markdown, 코드 펜스, 추가 텍스트는 출력하지 마세요.

            사용할 수 있는 action:
            - none: 편집 동작이 아니거나 확신이 부족함
            - replace_last: 사용자가 Utter이 방금 삽입한 텍스트를 새 텍스트로 바꾸려는 경우. replacement 필수
            - replace_selection: 사용자가 현재 선택된 텍스트를 새 텍스트로 바꾸려는 경우. replacement 필수
            - rewrite_last: 사용자가 LLM에게 Utter의 직전 삽입 텍스트를 재작성, 명시 내용 추가, 정리, 요약, 번역, 답장 작성, 구조화하도록 요청하는 경우. intent 필수
            - rewrite_selection: 사용자가 LLM에게 현재 선택 텍스트의 재작성, 명시 내용 추가, 정리, 요약, 번역, 답장 작성, 구조화를 요청하는 경우. intent 필수
            - delete_selection: 사용자가 현재 선택 텍스트를 삭제하려는 경우
            - undo_last_insertion: 사용자가 Utter의 직전 삽입을 되돌리려는 경우

            사용자 명령을 완전히 표현할 수 있을 때만 이 preset intent를 사용하세요. 대상, 어조, 내용, 형식, 제약 같은 추가 세부사항이 있으면 intent는 그 세부사항을 보존하는 짧은 자연어 지시여야 합니다:
            \(EditCommandResolverPromptCatalog.intentList)

            규칙:
            - 임의의 시스템 명령을 실행하지 말고 action을 만들지 않는다. intent는 preset이거나 사용자 명령에 명확히 드러난 대상 텍스트 재작성/추가 요청이어야 한다
            - 일반 받아쓰기, 일반 문장 작성, 일반 답장 작성, 일반 요약은 none
            - 사용자가 “선택한 내용”, “이 문장”, “현재 선택 영역”, “방금 입력한 내용”, “직전 입력”처럼 편집 대상을 명확히 가리킬 때만 편집 action을 반환한다
            - 현재 상태에서 직전 Utter 삽입이 사용할 수 없으면 직전 입력의 교체, 재작성, 취소는 none
            - 현재 상태에서 선택 텍스트가 사용할 수 없으면 선택 영역 교체, 재작성, 삭제는 none
            - confidence는 0부터 1 사이 숫자다. 매우 확신할 때만 0.8 이상을 사용하고, 아니면 action을 none으로 둔다
            - replace_last와 replace_selection에서는 replacement에 새 본문만 넣고 “바꿔줘” 같은 명령어는 넣지 않는다
            - rewrite_last와 rewrite_selection의 replacement는 null
            - delete_selection, undo_last_insertion, none의 intent와 replacement는 null

            JSON 형식:
            {"action":"none","intent":null,"replacement":null,"confidence":0}

            예시:
            음성: 이 부분을 회의록으로 정리해줘
            출력: {"action":"rewrite_selection","intent":"meeting_notes","replacement":null,"confidence":0.92}

            음성: 이거 너무 기니까 한 문장으로 줄여줘
            출력: {"action":"rewrite_selection","intent":"concise","replacement":null,"confidence":0.84}

            음성: 방금 입력한 문장을 더 정중하게 바꿔줘
            출력: {"action":"rewrite_last","intent":"formal","replacement":null,"confidence":0.88}

            음성: 방금 입력한 문장을 내일 오후에 배포로 바꿔줘
            출력: {"action":"replace_last","intent":null,"replacement":"내일 오후에 배포","confidence":0.93}

            음성: 가능하다고 답장해줘
            출력: {"action":"none","intent":null,"replacement":null,"confidence":0}
            """
        }
    }

    static func editCommandResolverUserPrompt(
        text: String,
        inputLanguage: InputLanguage,
        context: SpokenEditCommandResolutionContext
    ) -> String {
        switch inputLanguage {
        case .auto, .chinese, .cantonese:
            let languageInstruction: String
            let transcriptLabel: String
            switch inputLanguage {
            case .auto:
                languageInstruction = "自动判断语音口令语言；只分类编辑动作，不要改写或翻译口令本身。"
                transcriptLabel = "自动语言语音口令转写："
            case .cantonese:
                languageInstruction = "按粤语口令理解编辑目标和 replacement；除非口令指定语言，否则 replacement 保留自然粤语表达。"
                transcriptLabel = "粤语语音口令转写："
            default:
                languageInstruction = ""
                transcriptLabel = "语音口令转写："
            }
            return """
            当前状态：
            - 上一次 Utter 插入：\(context.lastInsertion.chinesePromptDescription)
            - 当前选区：\(context.selectedText.chinesePromptDescription)
            \(editCommandResolverContextPreview(context, inputLanguage: inputLanguage))
            如果上一次插入不可用，不要输出 replace_last、rewrite_last 或 undo_last_insertion。如果当前选区不可用，不要输出 replace_selection、rewrite_selection 或 delete_selection。当前选区未知时，只有语音明确指向选中内容、当前这段或这段文字，才可以输出选区相关动作。
            \(languageInstruction)

            \(transcriptLabel)
            \(PromptTextBlock.block(text))
            """
        case .english:
            return """
            Runtime state:
            - Previous Utter insertion: \(context.lastInsertion.englishPromptDescription)
            - Current selection: \(context.selectedText.englishPromptDescription)
            \(editCommandResolverContextPreview(context, inputLanguage: inputLanguage))
            If the previous insertion is unavailable, do not output replace_last, rewrite_last, or undo_last_insertion. If current selection is unavailable, do not output replace_selection, rewrite_selection, or delete_selection. When current selection is unknown, output selection actions only if the voice command clearly refers to selected text, the current selection, this text, or this passage.

            Voice command transcript:
            \(PromptTextBlock.block(text))
            """
        case .japanese:
            return """
            現在状態：
            - 直前の Utter 挿入：\(context.lastInsertion.japanesePromptDescription)
            - 現在の選択範囲：\(context.selectedText.japanesePromptDescription)
            \(editCommandResolverContextPreview(context, inputLanguage: inputLanguage))
            直前の挿入が利用不可なら replace_last、rewrite_last、undo_last_insertion を出力しないでください。現在の選択範囲が利用不可なら replace_selection、rewrite_selection、delete_selection を出力しないでください。現在の選択範囲が不明な場合は、音声コマンドが選択テキスト、現在の選択、この文章、この部分を明確に指す場合だけ選区関連 action を出力してください。

            音声コマンド転写：
            \(PromptTextBlock.block(text))
            """
        case .korean:
            return """
            현재 상태:
            - 직전 Utter 삽입: \(context.lastInsertion.koreanPromptDescription)
            - 현재 선택 영역: \(context.selectedText.koreanPromptDescription)
            \(editCommandResolverContextPreview(context, inputLanguage: inputLanguage))
            직전 삽입을 사용할 수 없으면 replace_last, rewrite_last 또는 undo_last_insertion을 출력하지 마세요. 현재 선택 영역을 사용할 수 없으면 replace_selection, rewrite_selection, delete_selection을 출력하지 마세요. 현재 선택 영역이 알 수 없음이면 음성 명령이 선택 텍스트, 현재 선택 영역, 이 문장, 이 부분을 명확히 가리킬 때만 선택 영역 관련 action을 출력하세요.

            음성 명령 전사:
            \(PromptTextBlock.block(text))
            """
        }
    }
}
