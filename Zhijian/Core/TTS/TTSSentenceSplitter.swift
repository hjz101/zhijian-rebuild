// TTSSentenceSplitter.swift — 中文/英文句子切分 + 旁白/对话多角色切分
import Foundation

/// 朗读角色（MVP：旁白 / 对话；角色名仅用于展示，不参与音色映射键）
enum TTSRole: String, Codable, Hashable, Sendable {
    case narrator
    case dialogue

    var displayName: String {
        switch self {
        case .narrator: return "旁白"
        case .dialogue: return "对话"
        }
    }
}

/// 一个可朗读片段：句子 + 角色 + 可选角色名。
struct TTSSegment: Identifiable, Hashable, Sendable {
    var id: Int
    var text: String
    var role: TTSRole
    var characterName: String?

    var displayRole: String {
        if let characterName, !characterName.isEmpty { return characterName }
        return role.displayName
    }
}

/// 文本 → 朗读片段。
///
/// 句子边界：中文 `。！？；…`、英文 `.?!;`、换行；引号/括号会跟随前一句。
/// 单句上限默认 300 字，超长时优先在逗号/空白处硬切。
/// 多角色：成对引号（“”、「」、『』、""、''）内的内容标为对话；
/// 无引号但出现「说：/道：/问：/答：」等提示语时，把冒号后的内容标为对话；
/// 并从提示语前的 1–6 个汉字中猜一个角色名（如「阿禾说」→ 阿禾）。
enum TTSScriptSegmenter {

    static let defaultMaxSentenceLength = 300

    // MARK: 对外接口

    /// 只切句，不区分角色。
    static func sentences(_ text: String, maxLength: Int = defaultMaxSentenceLength) -> [String] {
        guard !text.isEmpty else { return [] }
        var result = splitSentences(text)
        if maxLength > 0 {
            result = result.flatMap { hardSplit($0, maxLength: maxLength) }
        }
        return result
    }

    /// 切句并标注旁白/对话。
    static func segments(
        _ text: String,
        maxLength: Int = defaultMaxSentenceLength,
        splitRoles: Bool = true
    ) -> [TTSSegment] {
        let sentences = sentences(text, maxLength: maxLength)
        guard splitRoles else {
            return sentences.enumerated().map {
                TTSSegment(id: $0.offset, text: $0.element, role: .narrator, characterName: nil)
            }
        }

        var output: [TTSSegment] = []
        var previousNarration = ""
        for sentence in sentences {
            let pieces = roleSplit(sentence, context: previousNarration)
            for piece in pieces where !piece.text.isEmpty {
                guard !isPunctuationOnly(piece.text) else { continue }
                output.append(TTSSegment(
                    id: output.count,
                    text: piece.text,
                    role: piece.role,
                    characterName: piece.characterName
                ))
            }
            if let tail = pieces.last, tail.role == .narrator {
                previousNarration = tail.text
            }
        }
        return output
    }

    // MARK: 句子切分

    private static func splitSentences(_ text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let chars = Array(normalized)
        let enders: Set<Character> = ["。", "！", "？", "!", "?", "；", ";", "…"]
        let closers: Set<Character> = ["”", "」", "』", "’", "\"", "）", ")", "】", "]", "》", "〉"]
        var result: [String] = []
        var buffer = ""

        func flush() {
            let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { result.append(trimmed) }
            buffer.removeAll(keepingCapacity: true)
        }

        var index = 0
        while index < chars.count {
            let character = chars[index]
            if character == "\n" {
                flush()
                index += 1
                continue
            }

            buffer.append(character)

            if enders.contains(character) {
                // 连续标点（如「……」「？！」）并入同一句
                while index + 1 < chars.count, enders.contains(chars[index + 1]) {
                    index += 1
                    buffer.append(chars[index])
                }
                // 句末右引号/右括号跟随本句
                while index + 1 < chars.count, closers.contains(chars[index + 1]) {
                    index += 1
                    buffer.append(chars[index])
                }
                flush()
            } else if character == "." {
                let next = index + 1 < chars.count ? chars[index + 1] : nil
                if next == nil || next == " " || next == "\t" || next == "\n" || (next.map { closers.contains($0) } ?? false) {
                    while index + 1 < chars.count, closers.contains(chars[index + 1]) {
                        index += 1
                        buffer.append(chars[index])
                    }
                    flush()
                }
            }
            index += 1
        }
        flush()
        return result
    }

    /// 超长句硬切：优先在逗号/顿号/空格处切，且切点尽量靠近上限。
    private static func hardSplit(_ sentence: String, maxLength: Int) -> [String] {
        guard maxLength > 0, sentence.count > maxLength else { return [sentence] }
        var remaining = Array(sentence)
        var chunks: [String] = []
        let softBreaks: Set<Character> = ["，", ",", "、", "：", ":", " ", "　", "—", "-"]

        while remaining.count > maxLength {
            let windowStart = min(maxLength, remaining.count)
            var cut = windowStart
            // 在 [上限-60, 上限] 内回找软切点
            let lowerBound = max(1, windowStart - 60)
            var probe = windowStart
            while probe > lowerBound {
                if softBreaks.contains(remaining[probe - 1]) {
                    cut = probe
                    break
                }
                probe -= 1
            }
            if cut <= 0 { cut = windowStart }
            let chunk = String(remaining[0..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty { chunks.append(chunk) }
            remaining.removeFirst(cut)
        }
        let tail = String(remaining).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { chunks.append(tail) }
        return chunks
    }

    // MARK: 角色切分

    private struct Piece {
        var text: String
        var role: TTSRole
        var characterName: String?
    }

    private static func roleSplit(_ sentence: String, context: String) -> [Piece] {
        let quoted = splitQuotes(sentence)
        if quoted.contains(where: { $0.role == .dialogue }) {
            // 名字优先从紧邻引号前的旁白里找，其次从本句/上句上下文找
            var lastNarration = context
            var output: [Piece] = []
            for (offset, piece) in quoted.enumerated() {
                var item = piece
                if piece.role == .dialogue {
                    var name = characterName(in: lastNarration) ?? characterName(in: piece.text)
                    // “……”阿禾说：说话人常在引号之后
                    if name == nil, offset + 1 < quoted.count, quoted[offset + 1].role == .narrator {
                        name = characterName(in: quoted[offset + 1].text)
                    }
                    item.characterName = name
                } else if !piece.text.isEmpty {
                    lastNarration = piece.text
                }
                output.append(item)
            }
            return output
        }

        // 无引号：尝试「提示语：」切分
        if let split = colonDialogueSplit(sentence) {
            let name = characterName(in: split.before) ?? characterName(in: context)
            var pieces: [Piece] = []
            if !split.before.isEmpty {
                pieces.append(Piece(text: split.before, role: .narrator, characterName: nil))
            }
            pieces.append(Piece(text: split.after, role: .dialogue, characterName: name))
            return pieces
        }

        return [Piece(text: sentence, role: .narrator, characterName: nil)]
    }

    /// 成对引号 → 旁白/对话交替片段（引号本身不进入朗读文本）。
    private static func splitQuotes(_ sentence: String) -> [Piece] {
        let pairs: [(open: Character, close: Character)] = [
            ("“", "”"), ("「", "」"), ("『", "』"), ("‘", "’"), ("\"", "\""),
        ]
        let chars = Array(sentence)
        var pieces: [Piece] = []
        var plain = ""
        var inside = false
        var closeChar: Character?

        func flushPlain() {
            let text = plain.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { pieces.append(Piece(text: text, role: .narrator, characterName: nil)) }
            plain.removeAll(keepingCapacity: true)
        }

        var index = 0
        while index < chars.count {
            let character = chars[index]
            if !inside {
                if let pair = pairs.first(where: { $0.open == character }) {
                    flushPlain()
                    inside = true
                    closeChar = pair.close
                } else {
                    plain.append(character)
                }
            } else {
                if character == closeChar {
                    let text = plain.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        pieces.append(Piece(text: text, role: .dialogue, characterName: nil))
                    }
                    plain.removeAll(keepingCapacity: true)
                    inside = false
                    closeChar = nil
                } else {
                    plain.append(character)
                }
            }
            index += 1
        }
        if inside {
            // 引号未闭合：把已读内容当普通旁白，避免丢字
            flushPlain()
        } else {
            flushPlain()
        }
        return pieces
    }

    /// 「他说：走吧。」→ before「他说：」/ after「走吧。」
    private static func colonDialogueSplit(_ sentence: String) -> (before: String, after: String)? {
        let markers = ["说道：", "问道：", "答道：", "笑道：", "喊道：", "叫道：", "低声道：", "轻声道：",
                       "说道:", "问道:", "答道:", "说：", "道：", "问：", "答：", "说:", "道:", "问:", "答:"]
        guard let marker = markers
            .compactMap({ sentence.range(of: $0) })
            .min(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
        let after = String(sentence[marker.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !after.isEmpty else { return nil }
        let before = String(sentence[..<marker.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (before, after.trimmingCharacters(in: CharacterSet(charactersIn: "“”「」『』\"'")))
    }

    /// 从「阿禾说」「老陈问道」这类片段里猜 1–4 字的角色名。
    /// 只认提示语位于片段末尾（允许尾随冒号/引号/标点），避免把叙述中间的「说」当成提示语。
    private static func characterName(in text: String) -> String? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trailing = CharacterSet(charactersIn: "：:，,。.！!？?；;…、“”「」『』\"' \n\t")
        trimmed = trimmed.trimmingCharacters(in: trailing)
        guard !trimmed.isEmpty else { return nil }

        let verbs = ["低声说道", "轻声说道", "笑着说道", "冷冷说道", "回答道", "反问道", "说道", "问道", "答道",
                     "喊道", "叫道", "笑道", "叹道", "说", "道", "问", "答", "喊", "叫"]
        guard let verb = verbs.first(where: { trimmed.hasSuffix($0) }) else { return nil }
        let prefix = String(trimmed.dropLast(verb.count))
        let candidateChars = prefix.reversed().prefix { $0.isChineseCharacter }.reversed()
        let name = String(candidateChars).suffix(4)
        guard !name.isEmpty else { return nil }

        let stopWords: Set<String> = [
            "他", "她", "我", "你", "它", "他们", "她们", "我们", "你们", "众人", "有人",
            "那人", "此人", "朋友", "老人", "大家", "两人", "对方", "自己",
        ]
        guard !stopWords.contains(String(name)) else { return nil }
        // 名字里再出现说话动词，说明截取到了「他问」「我答」这类误判
        let verbChars: Set<Character> = ["说", "道", "问", "答", "喊", "叫", "叹", "笑"]
        guard !name.contains(where: { verbChars.contains($0) }) else { return nil }
        return String(name)
    }

    private static func isPunctuationOnly(_ text: String) -> Bool {
        let meaningful = text.unicodeScalars.contains {
            CharacterSet.alphanumerics.contains($0) || CharacterSet.letters.contains($0)
        }
        return !meaningful
    }
}

private extension Character {
    var isChineseCharacter: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
    }
}
