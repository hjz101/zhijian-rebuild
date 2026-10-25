// CrashGuard.swift — 崩溃防护：全局异常/信号捕获，写崩溃日志辅助诊断
import Foundation

enum CrashGuard {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        NSSetUncaughtExceptionHandler { exception in
            let reason = exception.reason ?? "未知"
            let stack = exception.callStackSymbols.prefix(20).joined(separator: "\n")
            let log = "时间: \(Date())\n异常: \(exception.name.rawValue)\n原因: \(reason)\n堆栈:\n\(stack)"
            CrashGuard.write(log)
        }
        // SIG 信号（EXC_BAD_ACCESS 等）写入日志后恢复默认 handler 避免二次崩溃
        let signals: [Int32] = [SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGSEGV, SIGTRAP]
        for sig in signals {
            signal(sig, { signum in
                CrashGuard.write("信号崩溃: signal \(signum)")
                signal(signum, SIG_DFL)
                raise(signum)
            })
        }
    }

    static func write(_ log: String) {
        let dir = AppData.root
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("crash-logs.txt")
        if var existing = try? String(contentsOf: file, encoding: .utf8) {
            existing = existing.suffix(4000) + "\n---\n" + log + "\n"
            try? existing.write(to: file, atomically: true, encoding: .utf8)
        } else {
            try? log.write(to: file, atomically: true, encoding: .utf8)
        }
    }
}
