import Foundation

package enum SpokenEditEvidence {
    package static func allows(_ command: SpokenEditCommand, transcript: String,
                               context: SpokenEditCommandResolutionContext) -> Bool {
        let target: Bool
        let operation: String
        switch command {
        case .replaceLast:
            target = context.lastInsertion == .available && matches(last, transcript)
            operation = replace
        case .rewriteLast:
            target = context.lastInsertion == .available && matches(last, transcript)
            operation = rewrite
        case .replaceSelection:
            target = context.selectedText == .available && matches(selection, transcript)
            operation = replace
        case .rewriteSelection:
            target = context.selectedText == .available && matches(selection, transcript)
            operation = rewrite + "|回复|回覆|返信|답장|\\breply\\b"
        case .deleteSelection:
            target = context.selectedText == .available && matches(selection, transcript)
            operation = "删除|删掉|刪除|刪咗|削除|消して|삭제|지워|\\b(delete|remove)\\b"
        case .undoLastInsertion:
            target = context.lastInsertion == .available && matches(last, transcript)
            operation = "撤销|撤回|撤銷|取り消|戻して|취소|되돌|\\bundo\\b"
        }
        return target && matches(operation, transcript)
    }

    private static let last = "(刚才|剛才|上一段|上一次|上次|之前|啱啱)(的)?(输入|輸入|插入|口述|输出|輸出)|さっき入力|直前の(入力|挿入)|방금\\s*(입력|삽입)|직전\\s*(입력|삽입)|\\b(last|previous)\\s+(insertion|input|output|inserted text)\\b|\\bwhat I just (said|typed|inserted)\\b"
    private static let selection = "选中|選中|选区|選區|这段(文字|内容|文本)?|這段|当前这段|この(文章|部分)|選択|선택|이\\s*(문장|부분)|\\b(selected text|selection|this text|this passage|this paragraph)\\b"
    private static let replace = "替换|替換|换成|換成|改成|改为|改為|置き換|바꿔|교체|\\breplace\\b"
    private static let rewrite = "改写|改寫|改得|改成|改为|改為|润色|潤色|整理|总结|總結|翻译|翻譯|缩短|縮短|精简|精簡|补充|補充|写成|寫成|書き換|短く|丁寧|要約|翻訳|재작성|짧게|정리|번역|\\b(rewrite|rephrase|polish|summarize|translate|shorten|make|turn)\\b"

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
