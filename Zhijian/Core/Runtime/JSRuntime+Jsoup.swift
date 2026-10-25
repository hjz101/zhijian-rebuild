// JSRuntime+Jsoup.swift —— jsoup_bridge.js 的原生 DOM store 与 `_jsoup*` 函数
//
// 设计对齐 QiReader 的「native 持有 DOM、JS 只持 handle」模型：
// - HTMLParser.parse 生成独立文档（不走 HTMLDocument.parse 的 LRU 缓存，避免规则间互相污染）；
// - docId 标识文档，handle 标识节点；JS 侧对象只保存 (docId, handle)；
// - 选择器用现有 CSSSelector / XPathQuery；修改能力由 HTMLNode 的 jsoup 扩展提供。
import Foundation
import JavaScriptCore

// MARK: - DOM Store

final class JsoupDOMStore {

    struct DocumentEntry {
        var root: HTMLNode
        var baseURI: String
        var title: String
    }

    private var documents: [Int: DocumentEntry] = [:]
    private var handles: [Int: HTMLNode] = [:]
    private var reverseHandles: [ObjectIdentifier: Int] = [:]
    private var nextDocId: Int = 1
    private var nextHandle: Int = 1
    private let lock = NSLock()

    func parse(_ html: String, baseURI: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let root = HTMLParser.parse(html)
        var title = ""
        if let titleNode = root.descendantElements.first(where: { $0.tag == "title" }) {
            title = titleNode.text()
        }
        let docId = nextDocId
        nextDocId += 1
        documents[docId] = DocumentEntry(root: root, baseURI: baseURI, title: title)
        return docId
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        documents.removeAll()
        handles.removeAll()
        reverseHandles.removeAll()
        nextDocId = 1
        nextHandle = 1
    }

    func document(_ docId: Int) -> DocumentEntry? {
        lock.lock()
        defer { lock.unlock() }
        return documents[docId]
    }

    func baseURI(_ docId: Int) -> String {
        document(docId)?.baseURI ?? ""
    }

    func root(_ docId: Int) -> HTMLNode? {
        document(docId)?.root
    }

    func handle(for node: HTMLNode) -> Int {
        lock.lock()
        defer { lock.unlock() }
        if let existing = reverseHandles[ObjectIdentifier(node)] { return existing }
        let handle = nextHandle
        nextHandle += 1
        handles[handle] = node
        reverseHandles[ObjectIdentifier(node)] = handle
        return handle
    }

    func node(_ handle: Int) -> HTMLNode? {
        lock.lock()
        defer { lock.unlock() }
        return handles[handle]
    }

    func node(_ docId: Int, _ handle: Int) -> HTMLNode? {
        guard let entry = document(docId) else { return nil }
        if handle == 0 { return entry.root }
        return node(handle)
    }

    func handles(for nodes: [HTMLNode]) -> [Int] {
        nodes.map { handle(for: $0) }
    }

    func rootHandle(_ docId: Int) -> Int? {
        guard let root = root(docId) else { return nil }
        return handle(for: root)
    }

    func firstElement(_ docId: Int, tag: String) -> Int? {
        guard let root = root(docId) else { return nil }
        guard let node = root.descendantElements.first(where: { $0.tag == tag }) else { return nil }
        return handle(for: node)
    }

    /// 用一段 HTML 生成节点列表（用于 append/prepend/before/after）
    func fragmentNodes(_ html: String) -> [HTMLNode] {
        let root = HTMLParser.parse(html)
        let body = root.descendantElements.first { $0.tag == "body" } ?? root
        return body.children
    }
}

// MARK: - 原生函数安装

extension JSRuntime {

    func installJsoupBridge(_ ctx: JSContext) {
        // 文档
        let parse: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] htmlValue, baseValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let docId = self.jsoupStore.parse(Self.stringArg(htmlValue), baseURI: Self.stringArg(baseValue))
            return JSValue(int32: Int32(docId), in: self.context)
        }
        setNative("_jsoupParse", parse, in: ctx)

        let clear: @convention(block) () -> Void = { [weak self] in
            self?.jsoupStore.clear()
        }
        setNative("_jsoupClearDomStore", clear, in: ctx)

        let rootHandle: @convention(block) (JSValue) -> JSValue = { [weak self] docValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let docId = Self.intArg(docValue)
            guard let handle = self.jsoupStore.rootHandle(docId) else { return JSValue(nullIn: self.context) }
            return JSValue(int32: Int32(handle), in: self.context)
        }
        setNative("_jsoupRootHandle", rootHandle, in: ctx)

        let bodyHandle: @convention(block) (JSValue) -> JSValue = { [weak self] docValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let docId = Self.intArg(docValue)
            guard let handle = self.jsoupStore.firstElement(docId, tag: "body") else { return JSValue(nullIn: self.context) }
            return JSValue(int32: Int32(handle), in: self.context)
        }
        setNative("_jsoupBodyHandle", bodyHandle, in: ctx)

        let headHandle: @convention(block) (JSValue) -> JSValue = { [weak self] docValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let docId = Self.intArg(docValue)
            guard let handle = self.jsoupStore.firstElement(docId, tag: "head") else { return JSValue(nullIn: self.context) }
            return JSValue(int32: Int32(handle), in: self.context)
        }
        setNative("_jsoupHeadHandle", headHandle, in: ctx)

        let documentText: @convention(block) (JSValue) -> JSValue = { [weak self] docValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let text = self.jsoupStore.root(Self.intArg(docValue))?.text() ?? ""
            return JSValue(object: text, in: self.context)
        }
        setNative("_jsoupDocumentText", documentText, in: ctx)

        let documentHtml: @convention(block) (JSValue) -> JSValue = { [weak self] docValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let html = self.jsoupStore.root(Self.intArg(docValue))?.innerHTML() ?? ""
            return JSValue(object: html, in: self.context)
        }
        setNative("_jsoupDocumentHtml", documentHtml, in: ctx)

        let documentTitle: @convention(block) (JSValue) -> JSValue = { [weak self] docValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let title = self.jsoupStore.document(Self.intArg(docValue))?.title ?? ""
            return JSValue(object: title, in: self.context)
        }
        setNative("_jsoupDocumentTitle", documentTitle, in: ctx)

        let documentBaseUri: @convention(block) (JSValue) -> JSValue = { [weak self] docValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            return JSValue(object: self.jsoupStore.baseURI(Self.intArg(docValue)), in: self.context)
        }
        setNative("_jsoupDocumentBaseUri", documentBaseUri, in: ctx)

        // 选择器 / XPath
        let selectHandles: @convention(block) (JSValue, JSValue, JSValue) -> JSValue = { [weak self] docValue, rootValue, selectorValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let docId = Self.intArg(docValue)
            guard let root = self.jsoupStore.node(docId, Self.intArg(rootValue)) else { return self.emptyArray() }
            let selector = Self.stringArg(selectorValue)
            let nodes = CSSSelector.select(selector, in: root)
            return self.numberArray(self.jsoupStore.handles(for: nodes))
        }
        setNative("_jsoupSelectHandles", selectHandles, in: ctx)

        let xpathResults: @convention(block) (JSValue, JSValue, JSValue) -> JSValue = { [weak self] docValue, rootValue, expressionValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let docId = Self.intArg(docValue)
            guard let root = self.jsoupStore.node(docId, Self.intArg(rootValue)) else { return self.emptyArray() }
            let expression = Self.stringArg(expressionValue)
            let values = XPathQuery.evaluate(expression, in: [root])
            let array = JSValue(newArrayIn: self.context)!
            for (index, value) in values.enumerated() {
                let object = JSValue(newObjectIn: self.context)!
                if let node = value as? HTMLNode {
                    object.setObject(JSValue(object: "node", in: self.context), forKeyedSubscript: "kind" as NSString)
                    object.setObject(JSValue(int32: Int32(self.jsoupStore.handle(for: node)), in: self.context), forKeyedSubscript: "handle" as NSString)
                } else {
                    object.setObject(JSValue(object: "value", in: self.context), forKeyedSubscript: "kind" as NSString)
                    object.setObject(self.toJS(JSONValueUtil.normalize(value)), forKeyedSubscript: "value" as NSString)
                }
                array.setObject(object, atIndexedSubscript: index)
            }
            return array
        }
        setNative("_jsoupXPathResults", xpathResults, in: ctx)

        // 树导航
        let childrenHandles: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] docValue, handleValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            guard let node = self.jsoupStore.node(Self.intArg(docValue), Self.intArg(handleValue)) else { return self.emptyArray() }
            return self.numberArray(self.jsoupStore.handles(for: node.elementChildren))
        }
        setNative("_jsoupChildrenHandles", childrenHandles, in: ctx)

        let parentHandle: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] docValue, handleValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            guard let node = self.jsoupStore.node(Self.intArg(docValue), Self.intArg(handleValue)),
                  let parent = node.parent, !parent.isDocument else { return JSValue(nullIn: self.context) }
            return JSValue(int32: Int32(self.jsoupStore.handle(for: parent)), in: self.context)
        }
        setNative("_jsoupParentHandle", parentHandle, in: ctx)

        let nextSibling: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] docValue, handleValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            guard let node = self.jsoupStore.node(Self.intArg(docValue), Self.intArg(handleValue)),
                  let sibling = node.nextElementSibling else { return JSValue(nullIn: self.context) }
            return JSValue(int32: Int32(self.jsoupStore.handle(for: sibling)), in: self.context)
        }
        setNative("_jsoupNextSiblingHandle", nextSibling, in: ctx)

        let previousSibling: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] docValue, handleValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            guard let node = self.jsoupStore.node(Self.intArg(docValue), Self.intArg(handleValue)),
                  let sibling = node.previousElementSibling else { return JSValue(nullIn: self.context) }
            return JSValue(int32: Int32(self.jsoupStore.handle(for: sibling)), in: self.context)
        }
        setNative("_jsoupPreviousSiblingHandle", previousSibling, in: ctx)

        // 节点读取
        registerNodeRead("_jsoupNodeText", in: ctx) { $0.text() }
        registerNodeRead("_jsoupNodeOwnText", in: ctx) { $0.ownText() }
        registerNodeRead("_jsoupNodeOuterHtml", in: ctx) { $0.html() }
        registerNodeRead("_jsoupNodeHtml", in: ctx) { $0.innerHTML() }
        registerNodeRead("_jsoupNodeTagName", in: ctx) { $0.tag }
        registerNodeRead("_jsoupNodeData", in: ctx) { $0.rawText() }
        registerNodeRead("_jsoupNodeNormalName", in: ctx) { $0.tag.lowercased() }

        let textNodes: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] docValue, handleValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            guard let node = self.jsoupStore.node(Self.intArg(docValue), Self.intArg(handleValue)) else { return self.emptyArray() }
            let values = node.textNodes()
            let array = JSValue(newArrayIn: self.context)!
            for (index, value) in values.enumerated() {
                array.setObject(JSValue(object: value, in: self.context), atIndexedSubscript: index)
            }
            return array
        }
        setNative("_jsoupNodeTextNodes", textNodes, in: ctx)

        let attr: @convention(block) (JSValue, JSValue, JSValue) -> JSValue = { [weak self] docValue, handleValue, nameValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            guard let node = self.jsoupStore.node(Self.intArg(docValue), Self.intArg(handleValue)) else { return JSValue(nullIn: self.context) }
            guard let value = node.attribute(Self.stringArg(nameValue)) else { return JSValue(nullIn: self.context) }
            return JSValue(object: value, in: self.context)
        }
        setNative("_jsoupNodeAttr", attr, in: ctx)

        let hasAttr: @convention(block) (JSValue, JSValue, JSValue) -> JSValue = { [weak self] docValue, handleValue, nameValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            guard let node = self.jsoupStore.node(Self.intArg(docValue), Self.intArg(handleValue)) else { return JSValue(bool: false, in: self.context) }
            return JSValue(bool: node.hasAttribute(Self.stringArg(nameValue)), in: self.context)
        }
        setNative("_jsoupNodeHasAttr", hasAttr, in: ctx)

        let hasClass: @convention(block) (JSValue, JSValue, JSValue) -> JSValue = { [weak self] docValue, handleValue, nameValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            guard let node = self.jsoupStore.node(Self.intArg(docValue), Self.intArg(handleValue)) else { return JSValue(bool: false, in: self.context) }
            return JSValue(bool: node.classList.contains(Self.stringArg(nameValue)), in: self.context)
        }
        setNative("_jsoupNodeHasClass", hasClass, in: ctx)

        let attributes: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] docValue, handleValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            guard let node = self.jsoupStore.node(Self.intArg(docValue), Self.intArg(handleValue)) else { return JSValue(newObjectIn: self.context) }
            return self.toJS(node.attributes)
        }
        setNative("_jsoupNodeAttributes", attributes, in: ctx)

        let absUrl: @convention(block) (JSValue, JSValue, JSValue, JSValue) -> JSValue = { [weak self] docValue, handleValue, nameValue, baseValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            guard let node = self.jsoupStore.node(Self.intArg(docValue), Self.intArg(handleValue)) else { return JSValue(object: "", in: self.context) }
            let name = Self.stringArg(nameValue)
            let raw = node.attribute(name) ?? name
            let base = Self.stringArg(baseValue)
            let baseURL = base.isEmpty ? self.jsoupStore.baseURI(Self.intArg(docValue)) : base
            return JSValue(object: RuleURLResolver.resolve(base: baseURL, relative: raw), in: self.context)
        }
        setNative("_jsoupNodeAbsUrl", absUrl, in: ctx)

        // 节点写入
        let setTag: @convention(block) (JSValue, JSValue, JSValue) -> Void = { [weak self] docValue, handleValue, nameValue in
            self?.jsoupStore.node(Self.intArg(docValue), Self.intArg(handleValue))?.jsoupSetTagName(Self.stringArg(nameValue))
        }
        setNative("_jsoupSetTagName", setTag, in: ctx)

        let setAttr: @convention(block) (JSValue, JSValue, JSValue, JSValue) -> Void = { [weak self] docValue, handleValue, nameValue, valueValue in
            self?.jsoupStore.node(Self.intArg(docValue), Self.intArg(handleValue))?
                .jsoupSetAttribute(Self.stringArg(nameValue), Self.stringArg(valueValue))
        }
        setNative("_jsoupSetAttr", setAttr, in: ctx)

        let removeAttr: @convention(block) (JSValue, JSValue, JSValue) -> Void = { [weak self] docValue, handleValue, nameValue in
            self?.jsoupStore.node(Self.intArg(docValue), Self.intArg(handleValue))?
                .jsoupRemoveAttribute(Self.stringArg(nameValue))
        }
        setNative("_jsoupRemoveAttr", removeAttr, in: ctx)

        let setText: @convention(block) (JSValue, JSValue, JSValue) -> Void = { [weak self] docValue, handleValue, textValue in
            self?.jsoupStore.node(Self.intArg(docValue), Self.intArg(handleValue))?
                .jsoupSetText(Self.stringArg(textValue))
        }
        setNative("_jsoupSetText", setText, in: ctx)

        let setHtml: @convention(block) (JSValue, JSValue, JSValue) -> Void = { [weak self] docValue, handleValue, htmlValue in
            self?.jsoupStore.node(Self.intArg(docValue), Self.intArg(handleValue))?
                .jsoupSetInnerHTML(Self.stringArg(htmlValue))
        }
        setNative("_jsoupSetHtml", setHtml, in: ctx)

        // 结构修改
        let empty: @convention(block) (JSValue, JSValue) -> Void = { [weak self] docValue, handleValue in
            self?.jsoupStore.node(Self.intArg(docValue), Self.intArg(handleValue))?.jsoupEmpty()
        }
        setNative("_jsoupEmpty", empty, in: ctx)

        let remove: @convention(block) (JSValue, JSValue) -> Void = { [weak self] docValue, handleValue in
            self?.jsoupStore.node(Self.intArg(docValue), Self.intArg(handleValue))?.jsoupRemoveFromParent()
        }
        setNative("_jsoupRemove", remove, in: ctx)

        let append: @convention(block) (JSValue, JSValue, JSValue) -> Void = { [weak self] docValue, handleValue, htmlValue in
            guard let self, let node = self.jsoupStore.node(Self.intArg(docValue), Self.intArg(handleValue)) else { return }
            node.jsoupAppendNodes(self.jsoupStore.fragmentNodes(Self.stringArg(htmlValue)))
        }
        setNative("_jsoupAppend", append, in: ctx)

        let prepend: @convention(block) (JSValue, JSValue, JSValue) -> Void = { [weak self] docValue, handleValue, htmlValue in
            guard let self, let node = self.jsoupStore.node(Self.intArg(docValue), Self.intArg(handleValue)) else { return }
            node.jsoupPrependNodes(self.jsoupStore.fragmentNodes(Self.stringArg(htmlValue)))
        }
        setNative("_jsoupPrepend", prepend, in: ctx)

        let before: @convention(block) (JSValue, JSValue, JSValue) -> Void = { [weak self] docValue, handleValue, htmlValue in
            guard let self, let node = self.jsoupStore.node(Self.intArg(docValue), Self.intArg(handleValue)) else { return }
            node.parent?.jsoupInsertNodes(self.jsoupStore.fragmentNodes(Self.stringArg(htmlValue)), before: node)
        }
        setNative("_jsoupBefore", before, in: ctx)

        let after: @convention(block) (JSValue, JSValue, JSValue) -> Void = { [weak self] docValue, handleValue, htmlValue in
            guard let self, let node = self.jsoupStore.node(Self.intArg(docValue), Self.intArg(handleValue)) else { return }
            node.parent?.jsoupInsertNodes(self.jsoupStore.fragmentNodes(Self.stringArg(htmlValue)), after: node)
        }
        setNative("_jsoupAfter", after, in: ctx)

        let cloneHandle: @convention(block) (JSValue, JSValue, JSValue) -> JSValue = { [weak self] docValue, handleValue, deepValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            guard let node = self.jsoupStore.node(Self.intArg(docValue), Self.intArg(handleValue)) else {
                return JSValue(nullIn: self.context)
            }
            let clone = node.jsoupClone(deep: deepValue.toBool())
            return JSValue(int32: Int32(self.jsoupStore.handle(for: clone)), in: self.context)
        }
        setNative("_jsoupCloneHandle", cloneHandle, in: ctx)

        // Connection.execute 的真实 HTTP
        let connectFetch: @convention(block) (JSValue, JSValue, JSValue, JSValue, JSValue) -> JSValue = { [weak self] urlValue, methodValue, bodyValue, headersValue, timeoutValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            let url = Self.stringArg(urlValue)
            let method = Self.stringArg(methodValue).isEmpty ? "GET" : Self.stringArg(methodValue).uppercased()
            let body = Self.stringArg(bodyValue)
            var headers: [String: String] = [:]
            if let json = LenientJSON.parse(Self.stringArg(headersValue)) as? [String: Any] {
                for (key, value) in json { headers[key] = JSONValueUtil.text(value) }
            }
            let timeout = timeoutValue.isUndefined || timeoutValue.isNull ? 15.0 : max(1, timeoutValue.toDouble())
            do {
                let response = try self.http.requestSync(url, method: method, headers: headers, body: method == "GET" || method == "HEAD" ? nil : body, timeout: timeout)
                let object = JSValue(newObjectIn: self.context)!
                object.setObject(JSValue(object: response.body, in: self.context), forKeyedSubscript: "bodyText" as NSString)
                object.setObject(JSValue(int32: Int32(response.status), in: self.context), forKeyedSubscript: "status" as NSString)
                object.setObject(JSValue(object: response.finalURL, in: self.context), forKeyedSubscript: "urlText" as NSString)
                object.setObject(self.toJS(response.headers), forKeyedSubscript: "headerMap" as NSString)
                return object
            } catch {
                self.appendLog("_jsoupConnectFetch", "失败：\(error.localizedDescription) \(url)")
                return JSValue(nullIn: self.context)
            }
        }
        setNative("_jsoupConnectFetch", connectFetch, in: ctx)
    }

    // MARK: 注册辅助

    private func setNative(_ name: String, _ value: Any, in ctx: JSContext) {
        ctx.setObject(value, forKeyedSubscript: name as NSString)
    }

    private func registerNodeRead(_ name: String, in ctx: JSContext, _ transform: @escaping (HTMLNode) -> String) {
        let fn: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] docValue, handleValue in
            guard let self else { return JSValue(undefinedIn: JSContext.current()) }
            guard let node = self.jsoupStore.node(Self.intArg(docValue), Self.intArg(handleValue)) else {
                return JSValue(object: "", in: self.context)
            }
            return JSValue(object: transform(node), in: self.context)
        }
        setNative(name, fn, in: ctx)
    }

    func emptyArray() -> JSValue {
        JSValue(newArrayIn: context) ?? JSValue(undefinedIn: context)
    }

    func numberArray(_ values: [Int]) -> JSValue {
        let array = JSValue(newArrayIn: context)!
        for (index, value) in values.enumerated() {
            array.setObject(JSValue(int32: Int32(value), in: context), atIndexedSubscript: index)
        }
        return array
    }
}
