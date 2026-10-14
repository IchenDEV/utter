import Foundation

extension TranscriptFidelityGuard {
    private static let candidateListMarker = try! NSRegularExpression(
        pattern: #"^[ \t]*(\d{1,2})(?:\.[ \t]+|[、)）][ \t]*)"#,
        options: [.anchorsMatchLines]
    )

    private static let spokenOrdinalCues = [
        #"第[一二三四五六七八九十两]+(?![一二三四五六七八九十两次天年月周週名人])(?:个|個|条|條|点|點|项|項|件|步)?"#,
        #"(?<![一-龥])[一二三四五六七八九十]+、"#,
        #"[问問]题[一二三四五六七八九十]+"#,
        #"(?<![一-龥])[一二三四五六七八九十]是"#,
        #"其[一二三四五六七八九十]"#,
    ].map { try! NSRegularExpression(pattern: $0) }

    /// Numbered-list rendering turns spoken ordinals into `1. 2. 3.` line markers.
    /// Both sides drop that scaffolding so the ordinals are not read as new facts.
    static func strippingListMarkers(
        source: String,
        candidate: String
    ) -> (source: String, candidate: String)? {
        let nsCandidate = candidate as NSString
        let matches = candidateListMarker.matches(
            in: candidate,
            range: NSRange(location: 0, length: nsCandidate.length)
        )
        guard matches.count >= 2 else { return nil }
        for (offset, match) in matches.enumerated() {
            guard Int(nsCandidate.substring(with: match.range(at: 1))) == offset + 1 else {
                return nil
            }
        }

        var strippedCandidate = candidate
        for match in matches.reversed() {
            guard let range = Range(match.range, in: strippedCandidate) else { continue }
            strippedCandidate.replaceSubrange(range, with: "")
        }
        let strippedSource = spokenOrdinalCues.reduce(source) { text, cue in
            cue.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: ""
            )
        }
        return (strippedSource, strippedCandidate)
    }
}
