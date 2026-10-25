// JSExecutionLimit.swift — JSC 执行超时中断（P2-07：Release 不使用私有 API）
// - DEBUG：dlsym 弱链接私有 C API `JSContextGroupSetExecutionTimeLimit` 中断死循环；
// - Release：不加载私有符号（上架合规），改用「事后看门狗」——脚本返回后若耗时超上限
//   仍抛超时错误，并在诊断中标记「JS 执行超限（Release 无中断）」，提示禁用可疑源。
//   极端死循环在 Release 下无法中断，文档化该限制（Backlog P2-07 验收）。
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
        #if DEBUG
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
        #else
        // Release：不触碰私有符号（App Store 合规）。
        // 用看门狗：超长脚本在返回后抛超时（无法中断纯死循环，文档化）。
        appendLog("JS.timeout", "Release 模式：未安装 JSC 中断（死循环不可中断，见 BACKLOG P2-07）")
        return false
        #endif
    }
}
