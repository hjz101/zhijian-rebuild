// JSVirtualMachinePool.swift — 共享 JSVirtualMachine（P3-05）
import JavaScriptCore

final class JSVirtualMachinePool {
    static let shared = JSVirtualMachinePool()

    private var vms: [JSVirtualMachine] = []
    private var lastUsed: [Date] = []
    private let limit = 3
    private let lock = NSLock()

    func take() -> JSVirtualMachine {
        lock.lock()
        defer { lock.unlock() }
        guard !vms.isEmpty else {
            // 修复：JSVirtualMachine() 失败不应 fatalError（用户设备闪退）。
            // 创建失败极罕见；真失败时抛给上层（JSC 自身有兜底），此处尽力重试一次。
            if let vm = JSVirtualMachine() {
                vms.append(vm)
                lastUsed.append(Date())
                return vm
            }
            return JSVirtualMachine() ?? JSVirtualMachine()
        }
        // 未满时：新建并追加（修复：原逻辑前 3 次都返回 index 0，池化失效）
        if vms.count < limit {
            if let vm = JSVirtualMachine() {
                vms.append(vm)
                lastUsed.append(Date())
                return vm
            }
            // 新建失败：复用最旧（降级）
            let oldestIndex = oldestVMIndex()
            lastUsed[oldestIndex] = Date()
            return vms[oldestIndex]
        }
        let oldestIndex = oldestVMIndex()
        guard let replacement = JSVirtualMachine() else {
            lastUsed[oldestIndex] = Date()
            return vms[oldestIndex]
        }
        vms[oldestIndex] = replacement
        lastUsed[oldestIndex] = Date()
        return replacement
    }

    private func oldestVMIndex() -> Int {
        var oldestIndex = 0
        var oldestDate = lastUsed[0]
        for index in 1..<vms.count where lastUsed[index] < oldestDate {
            oldestIndex = index
            oldestDate = lastUsed[index]
        }
        return oldestIndex
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        vms.removeAll()
        lastUsed.removeAll()
    }
}
