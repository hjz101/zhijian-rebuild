// JSExecutionLimit.swift — JSC 执行超时中断（JavaScriptCore 私有 C API，dlsym 弱链接）
import Foundation
import JavaScriptCore

private typealias JSContextGetGroupFn = @convention(c) (JSGlobalContextRef?) -> JSContextGroupRef?
private typealias JSShouldTerminateFn = @convention(c) (JSContextRef?) -> Bool
private typealias JSSetExecutionTimeLimitFn = @convention(c) (JSContextGroupRef?, Double, JSShouldTerminateFn?, UnsafeMutableRawPointer?) -> Void

extension JSRuntime {
    /// 为当前 JSContextGroup 安装执行时间上限；超时后 JavaScriptCore 会中断脚本并抛异常。
    /// 该 API 在 JavaScriptCore 中为私有接口，使用 dlsym 弱链接，取不到时静默跳过。
    @discardableResult
    func installExecutionTimeLimit(seconds: TimeInterval) -> Bool {
        guard let getGroupSym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "JSContextGetGroup"),
              let setLimitSym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "JSContextGroupSetExecutionTimeLimit") else {
            appendLog("JS.timeout", "JavaScriptCore 超时 API 不可用（已跳过）")
            return false
        }
        let getGroup = unsafeBitCast(getGroupSym, to: JSContextGetGroupFn.self)
        let setLimit = unsafeBitCast(setLimitSym, to: JSSetExecutionTimeLimitFn.self)
        guard let group = getGroup(context.jsGlobalContextRef) else {
            appendLog("JS.timeout", "无法获取 JSContextGroup")
            return false
        }
        let terminate: JSShouldTerminateFn = { _ in true }
        setLimit(group, max(0.1, seconds), terminate, nil)
        return true
    }
}
