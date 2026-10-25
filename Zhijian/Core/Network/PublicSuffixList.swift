// PublicSuffixList.swift — 精简 PSL（eTLD+1），避免 a.example.com 与 b.example.com 串 Cookie
import Foundation

enum PublicSuffixList {
    /// 常见公共后缀（不含单字母国家码，那些由系统 NSURL 处理；这里覆盖多段后缀与知名组合）
    private static let multiSuffixes: [String] = [
        "com.cn", "net.cn", "org.cn", "gov.cn", "edu.cn", "ac.cn",
        "com.hk", "com.tw", "com.sg", "com.my", "com.au", "com.br", "com.mx",
        "co.jp", "ne.jp", "or.jp", "co.kr", "or.kr", "co.uk", "org.uk", "me.uk",
        "com.sa", "com.tr", "com.eg", "com.ng", "com.ua", "com.pl", "com.ro",
        "com.gr", "com.vn", "com.th", "com.ph", "com.pk", "com.bd", "com.np",
        "co.in", "net.in", "org.in", "com.ar", "com.co", "com.pe", "com.ve",
        "com.ec", "com.bo", "com.py", "com.uy", "com.cl", "com.mx",
        "com.kz", "com.uz", "com.by", "com.ge", "com.am", "com.az", "com.md"
    ]
    private static let plainSuffixes: Set<String> = [
        "com", "net", "org", "edu", "gov", "mil", "int", "info", "biz", "name",
        "mobi", "pro", "asia", "xyz", "top", "club", "online", "site", "live",
        "app", "dev", "tech", "store", "news", "vip", "cloud", "link", "red",
        "pro", "wang", "ren", "icu", "work", "fun", "lol", "shop", "group"
    ]

    /// 返回 eTLD+1；`www.example.com` → `example.com`；`a.b.example.co.uk` → `example.co.uk`
    static func eTLDPlusOne(host: String) -> String {
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return host }
        let last = labels[labels.count - 1].lowercased()
        let second = labels[labels.count - 2].lowercased()

        // 多段后缀：末两段在表内 → 取末三段
        let lastTwo = second + "." + last
        if multiSuffixes.contains(lastTwo), labels.count >= 3 {
            return labels[labels.count - 3] + "." + lastTwo
        }
        // 单段公共后缀
        if plainSuffixes.contains(last) {
            return second + "." + last
        }
        // 默认：最后两段
        return lastTwo
    }

    /// 判断是否应共享 Cookie：两个 host 的 eTLD+1 相同。
    static func shouldShare(_ hostA: String, _ hostB: String) -> Bool {
        eTLDPlusOne(host: hostA) == eTLDPlusOne(host: hostB)
    }
}
