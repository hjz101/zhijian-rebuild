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
            guard let vm = JSVirtualMachine() else { fatalError("JSVirtualMachine init failed") }
            vms.append(vm)
            lastUsed.append(Date())
            return vm
        }
        var oldestIndex = 0
        var oldestDate = lastUsed[0]
        for index in 1..<vms.count where lastUsed[index] < oldestDate {
            oldestIndex = index
            oldestDate = lastUsed[index]
        }
        if vms.count < limit {
            lastUsed[oldestIndex] = Date()
            return vms[oldestIndex]
        }
        guard let replacement = JSVirtualMachine() else { return vms[oldestIndex] }
        vms[oldestIndex] = replacement
        lastUsed[oldestIndex] = Date()
        return replacement
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        vms.removeAll()
        lastUsed.removeAll()
    }
}
