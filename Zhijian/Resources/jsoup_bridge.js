// jsoup_bridge.js —— org.jsoup / JXDocument 兼容层（指尖阅读 2.0 自研实现）
//
// 设计：native 持有真实 DOM（JsoupDOMStore），JS 侧对象只保存 (docId, handle)。
// 这样 Element/Elements 的读写都直接落到 Swift 的 HTMLNode，不会出现「JS 里改完
// native 看不到」的问题。原生函数见 JSRuntime+Jsoup.swift。
(function (global) {
'use strict';

if (global.__zhijianJsoupBridgeInstalled) { return; }
global.__zhijianJsoupBridgeInstalled = true;

function _isNil(v) { return v === undefined || v === null; }
function _str(v) { return _isNil(v) ? '' : String(v); }
function _err(message) { var e = new Error(message); e.javaException = true; return e; }
function _define(target, name, value) {
    Object.defineProperty(target, name, { value: value, writable: true, configurable: true, enumerable: false });
}
function _defineAll(target, methods) {
    for (var key in methods) {
        if (Object.prototype.hasOwnProperty.call(methods, key)) { _define(target, key, methods[key]); }
    }
}

function _call(name) {
    var fn = global[name];
    if (typeof fn !== 'function') { throw _err('jsoup native 函数缺失：' + name); }
    return fn.apply(null, arguments.length > 1 ? Array.prototype.slice.call(arguments, 1) : []);
}

// ---------------------------------------------------------------------------
// 基础包装
// ---------------------------------------------------------------------------

var _elementMethods = {};
var _documentMethods = {};
var _textNodeMethods = {};

function Element(docId, handle, tag) {
    this._docId = docId;
    this._handle = handle;
    this._tag = tag || '';
    this._isDocument = false;
}
Element.__javaClassName = 'Element';
Element.prototype = Object.create(Object.prototype);
Element.prototype.constructor = Element;

function Document(docId) {
    this._docId = docId;
    this._handle = _call('_jsoupRootHandle', docId);
    this._tag = 'document';
    this._isDocument = true;
}
Document.__javaClassName = 'Document';
Document.prototype = Object.create(Element.prototype);
Document.prototype.constructor = Document;

function TextNode(text) {
    this._value = _str(text);
}
TextNode.__javaClassName = 'TextNode';

function _wrapElement(docId, handle) {
    if (handle === null || handle === undefined) { return null; }
    var tag = _call('_jsoupNodeTagName', docId, handle);
    return new Element(docId, handle, tag);
}

function _wrapNodeResult(docId, result) {
    if (!result) { return null; }
    if (result.kind === 'node') { return new JXNode(docId, result.handle, null); }
    return new JXNode(docId, null, result.value);
}

// ---------------------------------------------------------------------------
// Elements：真实 JS 数组（天然支持索引/for-of），附加 jsoup 方法
// ---------------------------------------------------------------------------

function _wrapElements(docId, handles) {
    var array = [];
    for (var i = 0; i < handles.length; i++) { array.push(_wrapElement(docId, handles[i])); }
    _decorateElements(array, docId);
    return array;
}

function _decorateElements(array, docId) {
    var methods = {
        size: function () { return array.length; },
        isEmpty: function () { return array.length === 0; },
        get: function (index) { return array[index] || null; },
        first: function () { return array.length ? array[0] : null; },
        last: function () { return array.length ? array[array.length - 1] : null; },
        eq: function (index) { return _wrapElements(docId, array[index] && array[index]._handle !== undefined ? [array[index]._handle] : []); },
        toArray: function () { return array.slice(); },
        subList: function (from, to) { return _wrapElements(docId, array.slice(from, to).map(function (e) { return e._handle; })); },
        not: function (selector) {
            var excluded = {};
            var matched = _call('_jsoupSelectHandles', docId, _call('_jsoupRootHandle', docId), _str(selector));
            for (var i = 0; i < matched.length; i++) { excluded[matched[i]] = true; }
            var kept = array.filter(function (e) { return !excluded[e._handle]; });
            return _wrapElements(docId, kept.map(function (e) { return e._handle; }));
        },
        select: function (selector) {
            var handles = [];
            for (var i = 0; i < array.length; i++) {
                var found = _call('_jsoupSelectHandles', docId, array[i]._handle, _str(selector));
                for (var j = 0; j < found.length; j++) { handles.push(found[j]); }
            }
            return _wrapElements(docId, handles);
        },
        selectFirst: function (selector) {
            var selected = methods.select(selector);
            return selected.length ? selected[0] : null;
        },
        text: function () {
            var parts = [];
            for (var i = 0; i < array.length; i++) { parts.push(_call('_jsoupNodeText', docId, array[i]._handle)); }
            return parts.join('\n');
        },
        eachText: function () {
            var parts = [];
            for (var i = 0; i < array.length; i++) { parts.push(_call('_jsoupNodeText', docId, array[i]._handle)); }
            return parts;
        },
        attr: function (name) {
            for (var i = 0; i < array.length; i++) {
                var value = _call('_jsoupNodeAttr', docId, array[i]._handle, _str(name));
                if (value !== null && value !== '') { return value; }
            }
            return '';
        },
        eachAttr: function (name) {
            var out = [];
            for (var i = 0; i < array.length; i++) {
                var value = _call('_jsoupNodeAttr', docId, array[i]._handle, _str(name));
                if (value !== null) { out.push(value); }
            }
            return out;
        },
        hasAttr: function (name) {
            for (var i = 0; i < array.length; i++) {
                if (_call('_jsoupNodeHasAttr', docId, array[i]._handle, _str(name))) { return true; }
            }
            return false;
        },
        html: function () {
            var parts = [];
            for (var i = 0; i < array.length; i++) { parts.push(_call('_jsoupNodeHtml', docId, array[i]._handle)); }
            return parts.join('\n');
        },
        outerHtml: function () {
            var parts = [];
            for (var i = 0; i < array.length; i++) { parts.push(_call('_jsoupNodeOuterHtml', docId, array[i]._handle)); }
            return parts.join('\n');
        },
        toString: function () { return methods.outerHtml(); },
        remove: function () {
            for (var i = 0; i < array.length; i++) { _call('_jsoupRemove', docId, array[i]._handle); }
        },
        empty: function () {
            for (var i = 0; i < array.length; i++) { _call('_jsoupEmpty', docId, array[i]._handle); }
        },
        before: function (html) {
            for (var i = 0; i < array.length; i++) { _call('_jsoupBefore', docId, array[i]._handle, _str(html)); }
        },
        after: function (html) {
            for (var i = 0; i < array.length; i++) { _call('_jsoupAfter', docId, array[i]._handle, _str(html)); }
        },
        append: function (html) {
            for (var i = 0; i < array.length; i++) { _call('_jsoupAppend', docId, array[i]._handle, _str(html)); }
        },
        prepend: function (html) {
            for (var i = 0; i < array.length; i++) { _call('_jsoupPrepend', docId, array[i]._handle, _str(html)); }
        },
        hasClass: function (name) {
            for (var i = 0; i < array.length; i++) {
                if (_call('_jsoupNodeHasClass', docId, array[i]._handle, _str(name))) { return true; }
            }
            return false;
        },
        addClass: function (name) {
            for (var i = 0; i < array.length; i++) {
                var current = _call('_jsoupNodeAttr', docId, array[i]._handle, 'class') || '';
                var classes = current ? current.split(/\s+/) : [];
                if (classes.indexOf(_str(name)) < 0) {
                    classes.push(_str(name));
                    _call('_jsoupSetAttr', docId, array[i]._handle, 'class', classes.join(' '));
                }
            }
            return array;
        },
        removeClass: function (name) {
            for (var i = 0; i < array.length; i++) {
                var current = _call('_jsoupNodeAttr', docId, array[i]._handle, 'class') || '';
                var classes = current ? current.split(/\s+/).filter(function (c) { return c && c !== _str(name); }) : [];
                _call('_jsoupSetAttr', docId, array[i]._handle, 'class', classes.join(' '));
            }
            return array;
        }
    };
    for (var key in methods) {
        if (Object.prototype.hasOwnProperty.call(methods, key)) { _define(array, key, methods[key]); }
    }
    return array;
}

// ---------------------------------------------------------------------------
// Element 方法
// ---------------------------------------------------------------------------

_elementMethods.text = function (value) {
    if (value !== undefined) { _call('_jsoupSetText', this._docId, this._handle, _str(value)); return this; }
    return _call('_jsoupNodeText', this._docId, this._handle);
};
_elementMethods.ownText = function () { return _call('_jsoupNodeOwnText', this._docId, this._handle); };
_elementMethods.textNodes = function () {
    var values = _call('_jsoupNodeTextNodes', this._docId, this._handle);
    var out = [];
    for (var i = 0; i < values.length; i++) { out.push(new TextNode(values[i])); }
    return out;
};
_elementMethods.data = function () { return _call('_jsoupNodeData', this._docId, this._handle); };
_elementMethods.html = function (value) {
    if (value !== undefined) { _call('_jsoupSetHtml', this._docId, this._handle, _str(value)); return this; }
    return _call('_jsoupNodeHtml', this._docId, this._handle);
};
_elementMethods.outerHtml = function () { return _call('_jsoupNodeOuterHtml', this._docId, this._handle); };
_elementMethods.toString = function () { return _call('_jsoupNodeOuterHtml', this._docId, this._handle); };
_elementMethods.attr = function (name, value) {
    if (value !== undefined) {
        _call('_jsoupSetAttr', this._docId, this._handle, _str(name), _str(value));
        return this;
    }
    var result = _call('_jsoupNodeAttr', this._docId, this._handle, _str(name));
    return result === null ? '' : result;
};
_elementMethods.absUrl = function (name) {
    return _call('_jsoupNodeAbsUrl', this._docId, this._handle, _str(name), '');
};
_elementMethods.hasAttr = function (name) {
    return _call('_jsoupNodeHasAttr', this._docId, this._handle, _str(name));
};
_elementMethods.removeAttr = function (name) {
    _call('_jsoupRemoveAttr', this._docId, this._handle, _str(name));
    return this;
};
_elementMethods.attributes = function () {
    return _call('_jsoupNodeAttributes', this._docId, this._handle);
};
_elementMethods.tagName = function () { return _call('_jsoupNodeTagName', this._docId, this._handle); };
_elementMethods.nodeName = function () { return _call('_jsoupNodeTagName', this._docId, this._handle); };
_elementMethods.normalName = function () { return _call('_jsoupNodeNormalName', this._docId, this._handle); };
_elementMethods.parent = function () {
    var handle = _call('_jsoupParentHandle', this._docId, this._handle);
    if (handle === null || handle === undefined) { return null; }
    return _wrapElement(this._docId, handle);
};
_elementMethods.children = function () {
    return _wrapElements(this._docId, _call('_jsoupChildrenHandles', this._docId, this._handle));
};
_elementMethods.child = function (index) {
    var children = _call('_jsoupChildrenHandles', this._docId, this._handle);
    return index < children.length ? _wrapElement(this._docId, children[index]) : null;
};
_elementMethods.childrenSize = function () {
    return _call('_jsoupChildrenHandles', this._docId, this._handle).length;
};
_elementMethods.nextElementSibling = function () {
    var handle = _call('_jsoupNextSiblingHandle', this._docId, this._handle);
    return handle === null || handle === undefined ? null : _wrapElement(this._docId, handle);
};
_elementMethods.previousElementSibling = function () {
    var handle = _call('_jsoupPreviousSiblingHandle', this._docId, this._handle);
    return handle === null || handle === undefined ? null : _wrapElement(this._docId, handle);
};
_elementMethods.select = function (selector) {
    return _wrapElements(this._docId, _call('_jsoupSelectHandles', this._docId, this._handle, _str(selector)));
};
_elementMethods.selectFirst = function (selector) {
    var handles = _call('_jsoupSelectHandles', this._docId, this._handle, _str(selector));
    return handles.length ? _wrapElement(this._docId, handles[0]) : null;
};
_elementMethods.xpath = function (expression) {
    var results = _call('_jsoupXPathResults', this._docId, this._handle, _str(expression));
    var array = [];
    for (var i = 0; i < results.length; i++) {
        if (results[i].kind === 'node') { array.push(_wrapElement(this._docId, results[i].handle)); }
        else { array.push(_str(results[i].value)); }
    }
    _decorateElements(array.filter(function (e) { return typeof e !== 'string'; }), this._docId);
    return array;
};
_elementMethods.selN = function (expression) {
    var results = _call('_jsoupXPathResults', this._docId, this._handle, _str(expression));
    var out = [];
    for (var i = 0; i < results.length; i++) { out.push(_wrapNodeResult(this._docId, results[i])); }
    return out;
};
_elementMethods.sel = function (expression) {
    var nodes = this.selN(expression);
    var out = [];
    for (var i = 0; i < nodes.length; i++) { out.push(nodes[i] ? nodes[i].asString() : ''); }
    return out;
};
_elementMethods.getElementById = function (id) {
    return this.selectFirst('#' + _str(id));
};
_elementMethods.getElementsByClass = function (name) {
    return this.select('.' + _str(name));
};
_elementMethods.getElementsByTag = function (tag) {
    return this.select(_str(tag));
};
_elementMethods.getElementsByAttribute = function (name) {
    return this.select('[' + _str(name) + ']');
};
_elementMethods.id = function () { return this.attr('id'); };
_elementMethods.className = function () { return this.attr('class'); };
_elementMethods.classNames = function () {
    var raw = this.attr('class');
    return raw ? raw.split(/\s+/).filter(function (v) { return v; }) : [];
};
_elementMethods.hasClass = function (name) {
    return _call('_jsoupNodeHasClass', this._docId, this._handle, _str(name));
};
_elementMethods.addClass = function (name) {
    var classes = this.classNames();
    if (classes.indexOf(_str(name)) < 0) {
        classes.push(_str(name));
        _call('_jsoupSetAttr', this._docId, this._handle, 'class', classes.join(' '));
    }
    return this;
};
_elementMethods.removeClass = function (name) {
    var classes = this.classNames().filter(function (c) { return c !== _str(name); });
    _call('_jsoupSetAttr', this._docId, this._handle, 'class', classes.join(' '));
    return this;
};
_elementMethods.val = function () { return this.attr('value'); };
_elementMethods.remove = function () { _call('_jsoupRemove', this._docId, this._handle); };
_elementMethods.empty = function () { _call('_jsoupEmpty', this._docId, this._handle); return this; };
_elementMethods.before = function (html) { _call('_jsoupBefore', this._docId, this._handle, _str(html)); return this; };
_elementMethods.after = function (html) { _call('_jsoupAfter', this._docId, this._handle, _str(html)); return this; };
_elementMethods.append = function (html) { _call('_jsoupAppend', this._docId, this._handle, _str(html)); return this; };
_elementMethods.prepend = function (html) { _call('_jsoupPrepend', this._docId, this._handle, _str(html)); return this; };
_elementMethods.clone = function () {
    var handle = _call('_jsoupCloneHandle', this._docId, this._handle, true);
    return _wrapElement(this._docId, handle);
};
_elementMethods.toJSON = function () {
    return { tagName: this.tagName(), text: this.text(), html: this.html(), attributes: this.attributes() };
};

// ---------------------------------------------------------------------------
// Document 方法
// ---------------------------------------------------------------------------

_documentMethods.select = function (selector) {
    return _wrapElements(this._docId, _call('_jsoupSelectHandles', this._docId, this._handle, _str(selector)));
};
_documentMethods.selectFirst = function (selector) {
    var handles = _call('_jsoupSelectHandles', this._docId, this._handle, _str(selector));
    return handles.length ? _wrapElement(this._docId, handles[0]) : null;
};
_documentMethods.text = function () { return _call('_jsoupDocumentText', this._docId); };
_documentMethods.html = function () { return _call('_jsoupDocumentHtml', this._docId); };
_documentMethods.outerHtml = function () { return _call('_jsoupDocumentHtml', this._docId); };
_documentMethods.title = function () { return _call('_jsoupDocumentTitle', this._docId); };
_documentMethods.body = function () {
    var handle = _call('_jsoupBodyHandle', this._docId);
    return handle === null || handle === undefined ? null : _wrapElement(this._docId, handle);
};
_documentMethods.head = function () {
    var handle = _call('_jsoupHeadHandle', this._docId);
    return handle === null || handle === undefined ? null : _wrapElement(this._docId, handle);
};
_documentMethods.location = function () { return _call('_jsoupDocumentBaseUri', this._docId); };
_documentMethods.baseUri = function () { return _call('_jsoupDocumentBaseUri', this._docId); };
_documentMethods.children = function () {
    return _wrapElements(this._docId, _call('_jsoupChildrenHandles', this._docId, this._handle));
};
_documentMethods.child = function (index) {
    var children = _call('_jsoupChildrenHandles', this._docId, this._handle);
    return index < children.length ? _wrapElement(this._docId, children[index]) : null;
};
_documentMethods.getElementById = function (id) { return this.selectFirst('#' + _str(id)); };
_documentMethods.getElementsByClass = function (name) { return this.select('.' + _str(name)); };
_documentMethods.getElementsByTag = function (tag) { return this.select(_str(tag)); };
_documentMethods.getElementsByAttribute = function (name) { return this.select('[' + _str(name) + ']'); };
_documentMethods.xpath = _elementMethods.xpath;
_documentMethods.selN = _elementMethods.selN;
_documentMethods.sel = _elementMethods.sel;
_documentMethods.toJSON = function () { return { title: this.title(), text: this.text(), html: this.html() }; };
_documentMethods.toString = function () { return this.outerHtml(); };

_textNodeMethods.text = function () { return this._value; };
_textNodeMethods.getWholeText = function () { return this._value; };
_textNodeMethods.toString = function () { return this._value; };
_textNodeMethods.outerHtml = function () { return this._value; };

// ---------------------------------------------------------------------------
// Jsoup / Connection / Response
// ---------------------------------------------------------------------------

var Jsoup = {
    parse: function (html, baseUri) {
        var docId = _call('_jsoupParse', _str(html), _str(baseUri));
        return new Document(docId);
    },
    connect: function (url) { return new Connection(url); },
    __javaClassName: 'Jsoup'
};

function Connection(url) {
    this._url = _str(url);
    this._method = 'GET';
    this._headers = {};
    this._data = {};
    this._body = null;
    this._timeout = 30;
    this._ignoreContentType = false;
    this._ignoreHttpErrors = false;
    this._followRedirects = true;
    this._userAgent = null;
    this._referrer = null;
}
Connection.__javaClassName = 'Connection';

var _connectionChain = [
    'ignoreContentType', 'ignoreHttpErrors', 'followRedirects', 'maxBodySize'
];
for (var ci = 0; ci < _connectionChain.length; ci++) {
    (function (name) {
        Connection.prototype[name] = function () { return this; };
    })(_connectionChain[ci]);
}
Connection.prototype.timeout = function (ms) { this._timeout = Math.max(1, Math.round(ms / 1000)); return this; };
Connection.prototype.userAgent = function (ua) { this._userAgent = _str(ua); return this; };
Connection.prototype.referrer = function (url) { this._referrer = _str(url); return this; };
Connection.prototype.header = function (name, value) { this._headers[_str(name)] = _str(value); return this; };
Connection.prototype.headers = function (map) {
    if (map) { for (var key in map) { if (Object.prototype.hasOwnProperty.call(map, key)) { this._headers[key] = _str(map[key]); } } }
    return this;
};
Connection.prototype.data = function (name, value) {
    if (typeof name === 'object' && name) {
        for (var key in name) { if (Object.prototype.hasOwnProperty.call(name, key)) { this._data[key] = _str(name[key]); } }
    } else {
        this._data[_str(name)] = _str(value);
    }
    return this;
};
Connection.prototype.requestBody = function (body) { this._body = _str(body); return this; };
Connection.prototype.method = function (method) { this._method = _str(method).toUpperCase(); return this; };
Connection.prototype.post = function () { this._method = 'POST'; return this; };
Connection.prototype.get = function () { this._method = 'GET'; return this; };
Connection.prototype.execute = function () {
    var body = this._body || '';
    if (!body) {
        var pairs = [];
        for (var key in this._data) {
            if (Object.prototype.hasOwnProperty.call(this._data, key)) {
                pairs.push(encodeURIComponent(key) + '=' + encodeURIComponent(this._data[key]));
            }
        }
        body = pairs.join('&');
        if (body && this._method === 'GET') {
            this._url += (this._url.indexOf('?') >= 0 ? '&' : '?') + body;
            body = '';
        }
    }
    var headers = {};
    for (var h in this._headers) { if (Object.prototype.hasOwnProperty.call(this._headers, h)) { headers[h] = this._headers[h]; } }
    if (this._userAgent) { headers['User-Agent'] = this._userAgent; }
    if (this._referrer) { headers['Referer'] = this._referrer; }
    var result = _call('_jsoupConnectFetch', this._url, this._method, body, JSON.stringify(headers), this._timeout);
    if (!result) { throw _err('Jsoup.connect.execute 失败：' + this._url); }
    return new JsoupResponse(result, this._url);
};

var ConnectionMethod = {
    GET: { name: function () { return 'GET'; } },
    POST: { name: function () { return 'POST'; } },
    PUT: { name: function () { return 'PUT'; } },
    DELETE: { name: function () { return 'DELETE'; } },
    PATCH: { name: function () { return 'PATCH'; } },
    HEAD: { name: function () { return 'HEAD'; } },
    OPTIONS: { name: function () { return 'OPTIONS'; } },
    TRACE: { name: function () { return 'TRACE'; } }
};

function JsoupResponse(raw, requestURL) {
    this._raw = raw;
    this._requestURL = requestURL;
}
JsoupResponse.__javaClassName = 'JsoupResponse';
JsoupResponse.prototype.body = function () { return _str(this._raw.bodyText); };
JsoupResponse.prototype.text = function () { return _str(this._raw.bodyText); };
JsoupResponse.prototype.bodyAsBytes = function () { return _strToBytes(this.body(), 'UTF-8'); };
JsoupResponse.prototype.statusCode = function () { return this._raw.status || 0; };
JsoupResponse.prototype.code = function () { return this._raw.status || 0; };
JsoupResponse.prototype.statusMessage = function () { return this._raw.status === 200 ? 'OK' : ''; };
JsoupResponse.prototype.url = function () { return this._raw.urlText || this._requestURL; };
JsoupResponse.prototype.header = function (name) {
    var map = this._raw.headerMap || {};
    for (var key in map) {
        if (Object.prototype.hasOwnProperty.call(map, key) && key.toLowerCase() === _str(name).toLowerCase()) { return map[key]; }
    }
    return '';
};
JsoupResponse.prototype.headers = function () { return this._raw.headerMap || {}; };
JsoupResponse.prototype.parse = function () { return Jsoup.parse(this.body(), this.url()); };
JsoupResponse.prototype.charset = function () { return 'UTF-8'; };
JsoupResponse.prototype.toString = function () { return this.body(); };
JsoupResponse.prototype.bodyBytes = function () { return _strToBytes(this.body(), 'UTF-8'); };

// ---------------------------------------------------------------------------
// JXDocument / JXNode（SeimiCrawler 风格）
// ---------------------------------------------------------------------------

function JXDocument(docId, rootHandle) {
    this._docId = docId;
    this._rootHandle = rootHandle;
}
JXDocument.__javaClassName = 'JXDocument';
JXDocument.create = function (input) {
    if (input instanceof Document) { return new JXDocument(input._docId, input._handle); }
    if (input instanceof Element) { return new JXDocument(input._docId, input._handle); }
    var text = _str(input);
    if (/^https?:\/\//i.test(text) && text.indexOf('<') < 0) {
        var response = _call('_jsoupConnectFetch', text, 'GET', '', '{}', 30);
        if (response) { text = _str(response.bodyText); }
    }
    var doc = Jsoup.parse(text, '');
    return new JXDocument(doc._docId, doc._handle);
};
JXDocument.prototype.selN = function (expression) {
    var results = _call('_jsoupXPathResults', this._docId, this._rootHandle, _str(expression));
    var out = [];
    for (var i = 0; i < results.length; i++) { out.push(_wrapNodeResult(this._docId, results[i])); }
    return out;
};
JXDocument.prototype.sel = function (expression) {
    var nodes = this.selN(expression);
    var out = [];
    for (var i = 0; i < nodes.length; i++) { out.push(nodes[i] ? nodes[i].asString() : ''); }
    return out;
};
JXDocument.prototype.toString = function () { return 'JXDocument(' + this._rootHandle + ')'; };

function JXNode(docId, handle, value) {
    this._docId = docId;
    this._handle = handle;
    this._value = value;
}
JXNode.__javaClassName = 'JXNode';
JXNode.prototype.isElement = function () { return this._handle !== null && this._handle !== undefined; };
JXNode.prototype.asString = function () {
    if (!this.isElement()) { return _str(this._value); }
    return _call('_jsoupNodeText', this._docId, this._handle);
};
JXNode.prototype.toString = function () {
    if (!this.isElement()) { return _str(this._value); }
    return _call('_jsoupNodeOuterHtml', this._docId, this._handle);
};
JXNode.prototype.sel = function (expression) {
    if (!this.isElement()) { return []; }
    var results = _call('_jsoupXPathResults', this._docId, this._handle, _str(expression));
    var out = [];
    for (var i = 0; i < results.length; i++) { out.push(_wrapNodeResult(this._docId, results[i]).asString()); }
    return out;
};
JXNode.prototype.getElement = function (expression) {
    if (!this.isElement()) { return null; }
    var results = _call('_jsoupXPathResults', this._docId, this._handle, _str(expression));
    for (var i = 0; i < results.length; i++) {
        if (results[i].kind === 'node') { return _wrapElement(this._docId, results[i].handle); }
    }
    return null;
};
JXNode.prototype.text = function () { return this.asString(); };

// 方法定义完成后统一挂到原型（enumerable:false，避免 for...in 污染）
_defineAll(Element.prototype, _elementMethods);
_defineAll(Document.prototype, _documentMethods);
_defineAll(TextNode.prototype, _textNodeMethods);

// ---------------------------------------------------------------------------
// 绑到 Packages / 全局
// ---------------------------------------------------------------------------

(function attach() {
    var packages = global.Packages || (global.Packages = {});
    var org = packages.org || (packages.org = {});
    var jsoupPkg = org.jsoup || (org.jsoup = {});
    jsoupPkg.Jsoup = Jsoup;
    jsoupPkg.Connection = Connection;
    jsoupPkg.Connection.Method = ConnectionMethod;
    var nodes = jsoupPkg.nodes || (jsoupPkg.nodes = {});
    nodes.Document = Document;
    nodes.Element = Element;
    nodes.TextNode = TextNode;
    var select = jsoupPkg.select || (jsoupPkg.select = {});
    select.Elements = _wrapElements; // 兼容 `org.jsoup.select.Elements` 构造用法（传 docId/handles）
    jsoupPkg.JsoupResponse = JsoupResponse;

    var crawler = org.seimicrawler || (org.seimicrawler = {});
    var xpathPkg = crawler.xpath || (crawler.xpath = {});
    xpathPkg.JXDocument = JXDocument;
    xpathPkg.JXNode = JXNode;

    if (global.java) { global.java.org = org; }

    if (global.Jsoup === undefined) { global.Jsoup = Jsoup; }
    if (global.JXDocument === undefined) { global.JXDocument = JXDocument; }
    if (global.JXNode === undefined) { global.JXNode = JXNode; }
})();

global.__zhijianJsoupBridgeInfo = {
    version: '2.0-engine',
    classes: ['org.jsoup.Jsoup', 'org.jsoup.nodes.Document', 'org.jsoup.nodes.Element', 'org.jsoup.select.Elements', 'org.seimicrawler.xpath.JXDocument', 'org.seimicrawler.xpath.JXNode']
};

})(this);
