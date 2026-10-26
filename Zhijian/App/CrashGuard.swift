// CrashGuard.swift — 崩溃防护：全局异常/信号捕获，写崩溃日志辅助诊断
// 修复：signal handler 只做 async-signal-safe 的 write(2)，不做 FileManager/JSON 等非安全调用。
import Foundation

enum CrashGuard {
    private static var installed = false
    /// 安装时预打开的日志 fd（signal handler 只 write 到这个 fd）
    private static var logFD: Int32 = -1
    private static let logPath = "crash-logs.txt"

    static func install() {
        guard !installed else { return }
        installed = true

        // 预创建目录 + 打开日志文件（主线程、安全上下文完成，handler 内不重复做）
        let dir = AppData.root
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(logPath)
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: nil)
        }
        logFD = open(file.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)

        NSSetUncaughtExceptionHandler { exception in
            let reason = exception.reason ?? "未知"
            let line = "时间: \(Date()) | 异常: \(exception.name.rawValue) | 原因: \(reason)"
            CrashGuard.safeWrite(line)
            let stack = exception.callStackSymbols.prefix(20).joined(separator: "\n")
            CrashGuard.safeWrite(stack)
        }

        // SIG 信号：只做 async-signal-safe 写入（write(2)），然后恢复默认 handler 让系统产出崩溃报告
        let signals: [Int32] = [SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGSEGV, SIGTRAP]
        for sig in signals {
            signal(sig, { signum in
                CrashGuard.safeWrite("信号崩溃: signal \(signum)")
                // 恢复默认 handler 并重发，让系统生成标准 crash report
                signal(signum, SIG_DFL)
                raise(signum)
            })
        }
    }

    /// async-signal-safe 写入：仅 write(2) 到预打开 fd（无 malloc / FileManager / String 分配以外的开销）
    private static func safeWrite(_ message: String) {
        guard logFD >= 0 else { return }
        let bytes = Array(message.utf8)
        bytes.withUnsafeBufferPointer { buffer in
            _ = write(logFD, buffer.baseAddress, buffer.count)
        }
        // 分隔符
        let sep = Array("\n---\n".utf8)
        sep.withUnsafeBufferPointer { buffer in
            _ = write(logFD, buffer.baseAddress, buffer.count)
        }
    }
}
