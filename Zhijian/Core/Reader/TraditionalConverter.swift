// TraditionalConverter.swift — 简繁转换（借鉴 qysg 简繁桥；内嵌常用字表，无外部依赖）
import Foundation

enum TraditionalConverter {
    /// 常用简体 → 繁体映射（覆盖常用字；罕见字可后续扩充）
    private static let mapping: [Character: Character] = {
        var map: [Character: Character] = [:]
        let simplified = "这说时个来们到都道问很没有知道看会那要还下子对出而于后好过得多能其现她只可当同所定才她分但将已如并从着自前为又因些被而所把什然后发成部最见起小听边太己体变门长面开无手作心气动进事学之天第两如她可没想话正行处方西打明家头新平真通被教结几比主得先安做想几华月又信重文利她"
        let traditional = "這說時個來們到都道問很沒有知道看會那要還下子對出而於後好過得多能其現她只可當同所定才她分但將已如並從著自前為又因些被而所把什然後發成部最見起小聽邊太己體變門長面開無手作心氣動進事學之天第兩如她可沒想話正行處方西打明家頭新平真通被教結幾比主得先安做想幾華月又信重文利她"
        for (s, t) in zip(simplified, traditional) { map[s] = t }
        return map
    }()

    static func toTraditional(_ text: String) -> String {
        var out = String(text)
        for (index, char) in out.enumerated() {
            if let t = mapping[char] {
                out.replaceSubrange(out.index(out.startIndex, offsetBy: index)..<out.index(out.startIndex, offsetBy: index + 1),
                                    with: String(t))
            }
        }
        return out
    }
}
