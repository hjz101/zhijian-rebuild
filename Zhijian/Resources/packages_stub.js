// packages_stub.js —— Legado / Rhino + Java 兼容层（指尖阅读 2.0 自研实现）
//
// 目标：让 Android Legado 书源里常见的 `java.*` / `Packages.*` / `javax.crypto.*`
// 写法在 JavaScriptCore 里「不因缺 Java API 直接 TypeError」。重算法全部委托 native：
//   _nativeStrToBytes / _nativeBytesToStr / _nativeBase64Encode / _nativeBase64DecodeToBytes
//   _nativeCipherProcess / _nativeGzip / _nativeGunzip / _nativeJsonPathRead
//   _nativeSleepMillis / _nativeDigestBase64 / _nativeHMacBase64 / _nativeRandomUUID
//
// 本文件为独立实现（未复制 QiReader 资源），只参考 Legado 的公开 API 语义。
(function (global) {
'use strict';

if (global.__zhijianPackagesStubInstalled) { return; }
global.__zhijianPackagesStubInstalled = true;

// ---------------------------------------------------------------------------
// 0. 基础工具
// ---------------------------------------------------------------------------

function _isNil(v) { return v === undefined || v === null; }
function _str(v) { return _isNil(v) ? '' : String(v); }
function _err(message) { var e = new Error(message); e.javaException = true; return e; }
function _hasNative(name) { return typeof global[name] === 'function'; }

var _b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function _fallbackBase64Encode(bytes) {
    var out = '';
    for (var i = 0; i < bytes.length; i += 3) {
        var b0 = bytes[i] & 255;
        var b1 = i + 1 < bytes.length ? bytes[i + 1] & 255 : 0;
        var b2 = i + 2 < bytes.length ? bytes[i + 2] & 255 : 0;
        out += _b64chars.charAt(b0 >> 2);
        out += _b64chars.charAt(((b0 & 3) << 4) | (b1 >> 4));
        out += i + 1 < bytes.length ? _b64chars.charAt(((b1 & 15) << 2) | (b2 >> 6)) : '=';
        out += i + 2 < bytes.length ? _b64chars.charAt(b2 & 63) : '=';
    }
    return out;
}

function _fallbackBase64Decode(text) {
    var clean = _str(text).replace(/[^A-Za-z0-9+/=]/g, '');
    var out = [];
    for (var i = 0; i < clean.length; i += 4) {
        var c0 = _b64chars.indexOf(clean.charAt(i));
        var c1 = _b64chars.indexOf(clean.charAt(i + 1));
        var c2 = _b64chars.indexOf(clean.charAt(i + 2));
        var c3 = _b64chars.indexOf(clean.charAt(i + 3));
        if (c0 < 0 || c1 < 0) { break; }
        out.push(((c0 << 2) | (c1 >> 4)) & 255);
        if (c2 >= 0) { out.push(((c1 & 15) << 4) | (c2 >> 2)); }
        if (c3 >= 0) { out.push(((c2 & 3) << 6) | c3); }
    }
    return out;
}

function _fallbackUtf8Bytes(text) {
    var out = [];
    for (var i = 0; i < text.length; i++) {
        var code = text.charCodeAt(i);
        if (code >= 0xD800 && code <= 0xDBFF && i + 1 < text.length) {
            var low = text.charCodeAt(i + 1);
            if (low >= 0xDC00 && low <= 0xDFFF) {
                code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
                i++;
            }
        }
        if (code < 0x80) { out.push(code); }
        else if (code < 0x800) { out.push(0xC0 | (code >> 6), 0x80 | (code & 63)); }
        else if (code < 0x10000) { out.push(0xE0 | (code >> 12), 0x80 | ((code >> 6) & 63), 0x80 | (code & 63)); }
        else { out.push(0xF0 | (code >> 18), 0x80 | ((code >> 12) & 63), 0x80 | ((code >> 6) & 63), 0x80 | (code & 63)); }
    }
    return out;
}

function _fallbackUtf8String(bytes) {
    var out = '';
    for (var i = 0; i < bytes.length;) {
        var b = bytes[i++] & 255;
        if (b < 0x80) { out += String.fromCharCode(b); }
        else if (b < 0xE0) { out += String.fromCharCode(((b & 31) << 6) | (bytes[i++] & 63)); }
        else if (b < 0xF0) { out += String.fromCharCode(((b & 15) << 12) | ((bytes[i++] & 63) << 6) | (bytes[i++] & 63)); }
        else {
            var cp = ((b & 7) << 18) | ((bytes[i++] & 63) << 12) | ((bytes[i++] & 63) << 6) | (bytes[i++] & 63);
            cp -= 0x10000;
            out += String.fromCharCode(0xD800 + (cp >> 10), 0xDC00 + (cp & 1023));
        }
    }
    return out;
}

function _toByteArray(value) {
    if (_isNil(value)) { return []; }
    if (typeof value === 'string') { return _strToBytes(value, 'UTF-8'); }
    if (typeof value === 'number') { return [value & 255]; }
    var out = [];
    var length = value.length || 0;
    for (var i = 0; i < length; i++) { out.push(value[i] & 255); }
    return out;
}

function _strToBytes(text, charset) {
    text = _str(text);
    if (_hasNative('_nativeStrToBytes')) { return _nativeStrToBytes(text, charset || 'UTF-8'); }
    return _fallbackUtf8Bytes(text);
}

function _bytesToStr(bytes, charset) {
    bytes = _toByteArray(bytes);
    if (_hasNative('_nativeBytesToStr')) { return _nativeBytesToStr(bytes, charset || 'UTF-8'); }
    return _fallbackUtf8String(bytes);
}

function _bytesToBase64(bytes) {
    bytes = _toByteArray(bytes);
    if (_hasNative('_nativeBase64Encode')) { return _nativeBase64Encode(bytes); }
    return _fallbackBase64Encode(bytes);
}

function _base64ToBytes(text) {
    if (_hasNative('_nativeBase64DecodeToBytes')) { return _nativeBase64DecodeToBytes(_str(text)); }
    return _fallbackBase64Decode(_str(text));
}

function _hexEncode(bytes) {
    bytes = _toByteArray(bytes);
    var out = '';
    for (var i = 0; i < bytes.length; i++) {
        var h = (bytes[i] & 255).toString(16);
        out += h.length === 1 ? '0' + h : h;
    }
    return out;
}

function _hexDecode(text) {
    text = _str(text).replace(/^0x/i, '');
    var out = [];
    for (var i = 0; i + 1 < text.length; i += 2) {
        out.push(parseInt(text.substr(i, 2), 16));
    }
    return out;
}

function _define(target, name, value) {
    Object.defineProperty(target, name, { value: value, writable: true, configurable: true, enumerable: false });
}

function _defineAll(target, methods) {
    for (var key in methods) {
        if (Object.prototype.hasOwnProperty.call(methods, key)) { _define(target, key, methods[key]); }
    }
}

function _class(name, ctor) {
    ctor.__javaClassName = name;
    return ctor;
}

function _package(path) {
    var parts = path.split('.');
    var object = Packages;
    for (var i = 0; i < parts.length; i++) {
        if (!object[parts[i]]) { object[parts[i]] = {}; }
        object = object[parts[i]];
    }
    return object;
}

function _install(path, name, clazz) {
    _package(path)[name] = clazz;
    var javaRoot = global.java || {};
    var target = javaRoot;
    var parts = path.split('.');
    for (var i = 0; i < parts.length; i++) {
        if (!target[parts[i]]) { target[parts[i]] = {}; }
        target = target[parts[i]];
    }
    target[name] = clazz;
}

// ---------------------------------------------------------------------------
// 1. String / JavaImporter / importPackage
// ---------------------------------------------------------------------------

_define(String.prototype, 'getBytes', function (charset) { return _strToBytes(String(this), charset || 'UTF-8'); });
_define(String.prototype, 'isEmpty', function () { return String(this).length === 0; });
_define(String.prototype, 'contains', function (other) { return String(this).indexOf(_str(other)) >= 0; });
_define(String.prototype, 'equals', function (other) { return String(this) === _str(other); });
_define(String.prototype, 'equalsIgnoreCase', function (other) { return String(this).toLowerCase() === _str(other).toLowerCase(); });
_define(String.prototype, 'replaceAll', function (search, replacement) {
    var re = (search instanceof RegExp) ? new RegExp(search.source, search.flags.indexOf('g') >= 0 ? search.flags : search.flags + 'g') : new RegExp(_str(search), 'g');
    return String(this).replace(re, replacement);
});
_define(String.prototype, 'string', function () { return String(this); });
_define(String.prototype, 'bytes', function () { return _strToBytes(String(this), 'UTF-8'); });
_define(String.prototype, 'replaceFirst', function (search, replacement) {
    return String(this).replace(search instanceof RegExp ? search : new RegExp(_str(search)), replacement);
});
_define(String.prototype, 'matches', function (regex) {
    return new RegExp('^(?:' + _str(regex) + ')$').test(String(this));
});

function JavaImporter() {
    var scope = {};
    for (var i = 0; i < arguments.length; i++) {
        var object = arguments[i];
        if (!object) { continue; }
        for (var key in object) {
            if (Object.prototype.hasOwnProperty.call(object, key)) { scope[key] = object[key]; }
        }
    }
    return scope;
}

function importPackage() { /* Rhino 里把包导入作用域；这里所有常用类已挂到全局 */ }
function importClass() { }
global.JavaImporter = JavaImporter;
global.importPackage = importPackage;
global.importClass = importClass;
global.Packages = global.Packages || {};
var Packages = global.Packages;

// ---------------------------------------------------------------------------
// 2. java.lang
// ---------------------------------------------------------------------------

function JavaString(value, charset) {
    var decoded;
    if (value && typeof value.length === 'number' && typeof value !== 'string') {
        decoded = _bytesToStr(value, charset || 'UTF-8');
    } else {
        decoded = _str(value);
    }
    if (!(this instanceof JavaString)) { return decoded; }
    this._value = decoded;
}
_class('java.lang.String', JavaString);
JavaString.valueOf = function (v) { return _str(v); };
JavaString.prototype.toString = function () { return this._value; };
JavaString.prototype.valueOf = function () { return this._value; };
JavaString.prototype.length = function () { return this._value.length; };
JavaString.prototype.charAt = function (index) { return this._value.charAt(index); };
JavaString.prototype.substring = function (start, end) { return end === undefined ? this._value.substring(start) : this._value.substring(start, end); };
JavaString.prototype.indexOf = function (search) { return this._value.indexOf(_str(search)); };
JavaString.prototype.contains = function (search) { return this._value.indexOf(_str(search)) >= 0; };
JavaString.prototype.equals = function (other) { return this._value === _str(other); };
JavaString.prototype.equalsIgnoreCase = function (other) { return this._value.toLowerCase() === _str(other).toLowerCase(); };
JavaString.prototype.isEmpty = function () { return this._value.length === 0; };
JavaString.prototype.getBytes = function (name) { return _strToBytes(this._value, name || 'UTF-8'); };
JavaString.prototype.replace = function (a, b) { return this._value.replace(a, b); };
JavaString.prototype.replaceAll = function (a, b) { return this._value.replace(a instanceof RegExp ? a : new RegExp(_str(a), 'g'), b); };
JavaString.prototype.split = function (separator) { return this._value.split(separator); };
JavaString.prototype.trim = function () { return this._value.trim(); };

var JavaInteger = _class('java.lang.Integer', function (value) {
    this.value = typeof value === 'string' ? parseInt(value, 10) : (value | 0);
});
JavaInteger.parseInt = function (text, radix) { return parseInt(_str(text), radix || 10); };
JavaInteger.valueOf = function (value) { return new JavaInteger(value); };
JavaInteger.toString = function (value) { return _str(value); };
JavaInteger.MAX_VALUE = 2147483647;
JavaInteger.MIN_VALUE = -2147483648;
JavaInteger.prototype.intValue = function () { return this.value | 0; };
JavaInteger.prototype.longValue = function () { return this.value; };
JavaInteger.prototype.toString = function () { return String(this.value); };

var JavaLong = _class('java.lang.Long', function (value) {
    this.value = typeof value === 'string' ? parseInt(value, 10) : value;
});
JavaLong.parseLong = function (text, radix) { return parseInt(_str(text), radix || 10); };
JavaLong.valueOf = function (value) { return new JavaLong(value); };
JavaLong.MAX_VALUE = 9007199254740991;
JavaLong.MIN_VALUE = -9007199254740991;
JavaLong.prototype.longValue = function () { return this.value; };
JavaLong.prototype.intValue = function () { return this.value | 0; };
JavaLong.prototype.toString = function () { return String(this.value); };

var JavaDouble = _class('java.lang.Double', function (value) { this.value = parseFloat(value); });
JavaDouble.parseDouble = function (text) { return parseFloat(_str(text)); };
JavaDouble.valueOf = function (value) { return new JavaDouble(value); };
JavaDouble.prototype.doubleValue = function () { return this.value; };
JavaDouble.prototype.toString = function () { return String(this.value); };

var JavaBoolean = _class('java.lang.Boolean', function (value) { this.value = !!value; });
JavaBoolean.TRUE = new JavaBoolean(true);
JavaBoolean.FALSE = new JavaBoolean(false);
JavaBoolean.valueOf = function (value) { return value ? JavaBoolean.TRUE : JavaBoolean.FALSE; };
JavaBoolean.prototype.booleanValue = function () { return this.value; };
JavaBoolean.prototype.toString = function () { return String(this.value); };

var JavaMath = {
    abs: Math.abs, max: Math.max, min: Math.min, pow: Math.pow, sqrt: Math.sqrt,
    floor: Math.floor, ceil: Math.ceil, round: Math.round, random: Math.random,
    sin: Math.sin, cos: Math.cos, tan: Math.tan, log: Math.log, exp: Math.exp,
    PI: Math.PI, E: Math.E, toRadians: function (d) { return d * Math.PI / 180; },
    toDegrees: function (r) { return r * 180 / Math.PI; }
};

var JavaSystem = {
    currentTimeMillis: function () { return Date.now(); },
    nanoTime: function () { return Date.now() * 1000000; },
    lineSeparator: function () { return '\n'; },
    getProperty: function (name) {
        if (name === 'http.agent' || name === 'user.agent') {
            try { return global.java && global.java.getWebViewUA ? global.java.getWebViewUA() : 'Mozilla/5.0'; } catch (e) { return 'Mozilla/5.0'; }
        }
        if (name === 'line.separator') { return '\n'; }
        if (name === 'java.version') { return '1.8.0'; }
        return '';
    },
    arraycopy: function (src, srcPos, dest, destPos, length) {
        for (var i = 0; i < length; i++) { dest[destPos + i] = src[srcPos + i]; }
    },
    gc: function () { },
    exit: function () { }
};

var JavaThread = _class('java.lang.Thread', function () { });
JavaThread.sleep = function (milliseconds) {
    var ms = Math.max(0, Math.min(2000, Number(milliseconds) || 0));
    if (ms > 0) {
        if (_hasNative('_nativeSleepMillis')) { _nativeSleepMillis(ms); }
        else { var end = Date.now() + ms; while (Date.now() < end) { /* busy wait（无 native 兜底） */ } }
    }
};
JavaThread.currentThread = function () { return { sleep: JavaThread.sleep, getId: function () { return 1; }, getName: function () { return 'main'; } }; };

function JavaStringBuilder(initial) {
    this._parts = _isNil(initial) ? [] : [_str(initial)];
}
_class('java.lang.StringBuilder', JavaStringBuilder);
JavaStringBuilder.prototype.append = function (value) { this._parts.push(_str(value)); return this; };
JavaStringBuilder.prototype.insert = function (index, value) {
    var text = this.toString();
    this._parts = [text.slice(0, index) + _str(value) + text.slice(index)];
    return this;
};
JavaStringBuilder.prototype.reverse = function () {
    this._parts = [this.toString().split('').reverse().join('')];
    return this;
};
JavaStringBuilder.prototype.toString = function () { return this._parts.join(''); };
JavaStringBuilder.prototype.length = function () { return this.toString().length; };
JavaStringBuilder.prototype.charAt = function (index) { return this.toString().charAt(index); };
JavaStringBuilder.prototype.deleteCharAt = function (index) {
    var text = this.toString();
    this._parts = [text.slice(0, index) + text.slice(index + 1)];
    return this;
};
JavaStringBuilder.prototype.substring = function (start, end) {
    return end === undefined ? this.toString().substring(start) : this.toString().substring(start, end);
};
var JavaStringBuffer = JavaStringBuilder;

function JavaException(message) { this.message = _str(message); this.stack = (new Error()).stack || ''; }
JavaException.prototype.toString = function () { return this.message; };
JavaException.prototype.getMessage = function () { return this.message; };
var JavaRuntimeException = JavaException;

// ---------------------------------------------------------------------------
// 3. java.util 集合
// ---------------------------------------------------------------------------

function ArrayList(items) {
    this._items = [];
    if (items) { this.addAll(items); }
}
_class('java.util.ArrayList', ArrayList);
ArrayList.prototype.add = function (item) { this._items.push(item); return true; };
ArrayList.prototype.addAll = function (list) {
    if (_isNil(list)) { return false; }
    if (typeof list.size === 'function' && typeof list.get === 'function') {
        for (var i = 0; i < list.size(); i++) { this._items.push(list.get(i)); }
    } else {
        for (var j = 0; j < list.length; j++) { this._items.push(list[j]); }
    }
    return true;
};
ArrayList.prototype.get = function (index) {
    if (index < 0) { index = this._items.length + index; }
    return this._items[index];
};
ArrayList.prototype.set = function (index, value) { this._items[index] = value; return value; };
ArrayList.prototype.size = function () { return this._items.length; };
ArrayList.prototype.isEmpty = function () { return this._items.length === 0; };
ArrayList.prototype.contains = function (item) { return this._items.indexOf(item) >= 0; };
ArrayList.prototype.indexOf = function (item) { return this._items.indexOf(item); };
ArrayList.prototype.remove = function (indexOrItem) {
    if (typeof indexOrItem === 'number') {
        var removed = this._items.splice(indexOrItem, 1);
        return removed.length ? removed[0] : null;
    }
    var pos = this._items.indexOf(indexOrItem);
    if (pos >= 0) { this._items.splice(pos, 1); return true; }
    return false;
};
ArrayList.prototype.clear = function () { this._items = []; };
ArrayList.prototype.toArray = function () { return this._items.slice(); };
ArrayList.prototype.iterator = function () {
    var items = this._items, index = 0;
    return {
        hasNext: function () { return index < items.length; },
        next: function () { return items[index++]; },
        remove: function () { }
    };
};
ArrayList.prototype.forEach = function (callback) {
    for (var i = 0; i < this._items.length; i++) { callback(this._items[i], i); }
};
ArrayList.prototype.toString = function () { return '[' + this._items.join(', ') + ']'; };
ArrayList.prototype[Symbol.iterator] = function () { return this._items[Symbol.iterator](); };

function LinkedHashMap(initial) {
    this._keys = [];
    this._map = {};
    if (initial) {
        for (var key in initial) {
            if (Object.prototype.hasOwnProperty.call(initial, key)) { this.put(key, initial[key]); }
        }
    }
}
_class('java.util.LinkedHashMap', LinkedHashMap);
LinkedHashMap.prototype.put = function (key, value) {
    var k = _str(key);
    if (!Object.prototype.hasOwnProperty.call(this._map, k)) { this._keys.push(k); }
    this._map[k] = value;
    return value;
};
LinkedHashMap.prototype.get = function (key) {
    var k = _str(key);
    return Object.prototype.hasOwnProperty.call(this._map, k) ? this._map[k] : null;
};
LinkedHashMap.prototype.getOrDefault = function (key, fallback) {
    var value = this.get(key);
    return _isNil(value) ? fallback : value;
};
LinkedHashMap.prototype.containsKey = function (key) { return Object.prototype.hasOwnProperty.call(this._map, _str(key)); };
LinkedHashMap.prototype.containsValue = function (value) {
    for (var i = 0; i < this._keys.length; i++) { if (this._map[this._keys[i]] === value) { return true; } }
    return false;
};
LinkedHashMap.prototype.remove = function (key) {
    var k = _str(key);
    if (!Object.prototype.hasOwnProperty.call(this._map, k)) { return null; }
    var value = this._map[k];
    delete this._map[k];
    var pos = this._keys.indexOf(k);
    if (pos >= 0) { this._keys.splice(pos, 1); }
    return value;
};
LinkedHashMap.prototype.size = function () { return this._keys.length; };
LinkedHashMap.prototype.isEmpty = function () { return this._keys.length === 0; };
LinkedHashMap.prototype.clear = function () { this._keys = []; this._map = {}; };
LinkedHashMap.prototype.keySet = function () {
    var list = new ArrayList();
    for (var i = 0; i < this._keys.length; i++) { list.add(this._keys[i]); }
    return list;
};
LinkedHashMap.prototype.values = function () {
    var list = new ArrayList();
    for (var i = 0; i < this._keys.length; i++) { list.add(this._map[this._keys[i]]); }
    return list;
};
LinkedHashMap.prototype.entrySet = function () {
    var list = new ArrayList();
    for (var i = 0; i < this._keys.length; i++) {
        list.add({ getKey: (function (k) { return function () { return k; }; })(this._keys[i]),
                   getValue: (function (v) { return function () { return v; }; })(this._map[this._keys[i]]),
                   setValue: function (v) { return v; } });
    }
    return list;
};
LinkedHashMap.prototype.forEach = function (callback) {
    for (var i = 0; i < this._keys.length; i++) { callback(this._keys[i], this._map[this._keys[i]]); }
};
LinkedHashMap.prototype.toString = function () { return '{' + this._keys.join(', ') + '}'; };
LinkedHashMap.prototype.putAll = function (other) {
    if (other && typeof other.entrySet === 'function') {
        var entries = other.entrySet();
        for (var i = 0; i < entries.size(); i++) { this.put(entries.get(i).getKey(), entries.get(i).getValue()); }
    } else if (other) {
        for (var k in other) { if (Object.prototype.hasOwnProperty.call(other, k)) { this.put(k, other[k]); } }
    }
};
var HashMap = LinkedHashMap;

var JavaCollections = {
    emptyList: function () { return new ArrayList(); },
    singletonList: function (item) { var l = new ArrayList(); l.add(item); return l; },
    sort: function (list, comparator) {
        var array = list.toArray ? list.toArray() : Array.prototype.slice.call(list);
        array.sort(comparator ? function (a, b) { return comparator.compare(a, b); } : undefined);
        for (var i = 0; i < array.length; i++) { if (list.set) { list.set(i, array[i]); } else { list[i] = array[i]; } }
    },
    reverse: function (list) {
        var array = list.toArray ? list.toArray() : Array.prototype.slice.call(list);
        array.reverse();
        for (var i = 0; i < array.length; i++) { if (list.set) { list.set(i, array[i]); } else { list[i] = array[i]; } }
    },
    addAll: function (list) {
        for (var i = 1; i < arguments.length; i++) { list.addAll(arguments[i]); }
        return arguments.length > 1;
    }
};

var JavaArrays = {
    copyOf: function (source, length) {
        var out = [];
        for (var i = 0; i < length; i++) { out.push(i < source.length ? source[i] : 0); }
        return out;
    },
    copyOfRange: function (source, from, to) {
        var out = [];
        for (var i = from; i < to; i++) { out.push(source[i] || 0); }
        return out;
    },
    asList: function () {
        var list = new ArrayList();
        if (arguments.length === 1 && arguments[0] && typeof arguments[0].length === 'number') {
            for (var i = 0; i < arguments[0].length; i++) { list.add(arguments[0][i]); }
        } else {
            for (var j = 0; j < arguments.length; j++) { list.add(arguments[j]); }
        }
        return list;
    },
    toString: function (array) { return '[' + Array.prototype.join.call(array || [], ', ') + ']'; },
    sort: function (array, comparator) { Array.prototype.sort.call(array, comparator ? function (a, b) { return comparator.compare(a, b); } : undefined); },
    fill: function (array, value) { for (var i = 0; i < array.length; i++) { array[i] = value; } },
    equals: function (a, b) { return _str(a) === _str(b); }
};

// Base64
var JavaBase64 = {
    getEncoder: function () {
        return {
            encode: function (bytes) { return _strToBytes(_bytesToBase64(bytes), 'UTF-8'); },
            encodeToString: function (bytes) { return _bytesToBase64(bytes); },
            withoutPadding: function () { return this; }
        };
    },
    getDecoder: function () {
        return {
            decode: function (text) { return _base64ToBytes(text); },
            decodeToBytes: function (text) { return _base64ToBytes(text); }
        };
    },
    getUrlEncoder: function () {
        return {
            encodeToString: function (bytes) { return _bytesToBase64(bytes).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, ''); },
            encode: function (bytes) { return _strToBytes(this.encodeToString(bytes), 'UTF-8'); }
        };
    },
    getUrlDecoder: function () {
        return { decode: function (text) { return _base64ToBytes(_str(text).replace(/-/g, '+').replace(/_/g, '/')); } };
    }
};

// UUID
var JavaUUID = {
    randomUUID: function () {
        if (global.java && typeof global.java.randomUUID === 'function') { return String(global.java.randomUUID()); }
        if (_hasNative('_nativeRandomUUID')) { return _nativeRandomUUID(); }
        return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
            var r = Math.random() * 16 | 0;
            return (c === 'x' ? r : ((r & 3) | 8)).toString(16);
        });
    },
    fromString: function (text) { return _str(text); },
    nameUUIDFromBytes: function (bytes) {
        var digest = _base64ToBytes(_nativeDigestBase64(_toByteArray(bytes), 'MD5'));
        digest[6] = (digest[6] & 15) | 0x30;
        digest[8] = (digest[8] & 63) | 0x80;
        var hex = _hexEncode(digest);
        return hex.substr(0, 8) + '-' + hex.substr(8, 4) + '-' + hex.substr(12, 4) + '-' + hex.substr(16, 4) + '-' + hex.substr(20, 12);
    }
};

// 并发
var JavaTimeUnit = {
    NANOSECONDS: { toMillis: function (n) { return n / 1000000; }, sleep: function (n) { JavaThread.sleep(n / 1000000); } },
    MICROSECONDS: { toMillis: function (n) { return n / 1000; }, sleep: function (n) { JavaThread.sleep(n / 1000); } },
    MILLISECONDS: { toMillis: function (n) { return n; }, sleep: function (n) { JavaThread.sleep(n); } },
    SECONDS: { toMillis: function (n) { return n * 1000; }, sleep: function (n) { JavaThread.sleep(n * 1000); } },
    MINUTES: { toMillis: function (n) { return n * 60000; }, sleep: function (n) { JavaThread.sleep(n * 60000); } }
};

// ---------------------------------------------------------------------------
// 4. java.util.regex
// ---------------------------------------------------------------------------

function _javaPatternSource(source) {
    // Java 的 \Q...\E 引用块 → JS 转义
    return _str(source).replace(/\\Q([\s\S]*?)\\E/g, function (_, body) {
        return body.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    });
}

function JavaPattern(source, flags) {
    this._source = _javaPatternSource(source);
    this._flags = flags || 0;
    var jsFlags = 'g';
    if (this._flags & 2) { jsFlags += 'i'; }
    if (this._flags & 8) { jsFlags += 'm'; }
    if (this._flags & 32) { jsFlags += 's'; }
    this._jsFlags = jsFlags;
    this._regexp = new RegExp(this._source, jsFlags);
}
_class('java.util.regex.Pattern', JavaPattern);
JavaPattern.compile = function (source, flags) { return new JavaPattern(source, flags); };
JavaPattern.matches = function (regex, input) { return new RegExp('^(?:' + _javaPatternSource(regex) + ')$').test(_str(input)); };
JavaPattern.quote = function (text) { return '\\Q' + _str(text) + '\\E'; };
JavaPattern.CASE_INSENSITIVE = 2;
JavaPattern.MULTILINE = 8;
JavaPattern.DOTALL = 32;
JavaPattern.prototype.pattern = function () { return this._source; };
JavaPattern.prototype.matcher = function (input) { return new JavaMatcher(this, _str(input)); };
JavaPattern.prototype.split = function (input) { return _str(input).split(this._regexp); };
JavaPattern.prototype.toString = function () { return this._source; };

function JavaMatcher(pattern, input) {
    this._pattern = pattern;
    this._input = input;
    this._matches = [];
    var re = new RegExp(pattern._source, pattern._jsFlags);
    var m;
    while ((m = re.exec(input)) !== null) {
        this._matches.push(m);
        if (m[0] === '') { re.lastIndex++; }
    }
    this._index = -1;
}
_class('java.util.regex.Matcher', JavaMatcher);
JavaMatcher.prototype.find = function () {
    if (this._index + 1 >= this._matches.length) { return false; }
    this._index++;
    return true;
};
JavaMatcher.prototype.matches = function () {
    if (!this._matches.length) { return false; }
    var m = this._matches[0];
    return m.index === 0 && m[0].length === this._input.length;
};
JavaMatcher.prototype.group = function (index) {
    var m = this._matches[this._index];
    if (!m) { return null; }
    var position = index === undefined ? 0 : index;
    return m[position] === undefined ? null : m[position];
};
JavaMatcher.prototype.groupCount = function () { return this._matches.length ? this._matches[0].length - 1 : 0; };
JavaMatcher.prototype.start = function () { var m = this._matches[this._index]; return m ? m.index : -1; };
JavaMatcher.prototype.end = function () { var m = this._matches[this._index]; return m ? m.index + m[0].length : -1; };
JavaMatcher.prototype.reset = function (input) {
    if (input !== undefined) {
        var p = this._pattern;
        return new JavaMatcher(p, _str(input));
    }
    this._index = -1;
    return this;
};
JavaMatcher.prototype.replaceAll = function (replacement) {
    return this._input.replace(new RegExp(this._pattern._source, this._pattern._jsFlags), replacement);
};
JavaMatcher.prototype.replaceFirst = function (replacement) {
    return this._input.replace(new RegExp(this._pattern._source, this._pattern._jsFlags.replace('g', '')), replacement);
};
JavaMatcher.prototype.lookingAt = function () {
    if (!this._matches.length) { return false; }
    return this._matches[0].index === 0;
};

// ---------------------------------------------------------------------------
// 5. 字节流 / GZIP / ByteBuffer
// ---------------------------------------------------------------------------

function ByteArrayOutputStream() { this._bytes = []; }
_class('java.io.ByteArrayOutputStream', ByteArrayOutputStream);
ByteArrayOutputStream.prototype.write = function (value, offset, length) {
    if (typeof value === 'number') { this._bytes.push(value & 255); return; }
    var bytes = _toByteArray(value);
    var start = offset || 0;
    var count = length === undefined ? bytes.length : length;
    for (var i = 0; i < count; i++) { this._bytes.push(bytes[start + i] & 255); }
};
ByteArrayOutputStream.prototype.toByteArray = function () { return this._bytes.slice(); };
ByteArrayOutputStream.prototype.toString = function (charset) { return _bytesToStr(this._bytes, charset || 'UTF-8'); };
ByteArrayOutputStream.prototype.size = function () { return this._bytes.length; };
ByteArrayOutputStream.prototype.reset = function () { this._bytes = []; };
ByteArrayOutputStream.prototype.close = function () { };
ByteArrayOutputStream.prototype.flush = function () { };

function ByteArrayInputStream(bytes) {
    this._bytes = _toByteArray(bytes);
    this._pos = 0;
}
_class('java.io.ByteArrayInputStream', ByteArrayInputStream);
ByteArrayInputStream.prototype.read = function (buffer, offset, length) {
    if (buffer === undefined) {
        return this._pos < this._bytes.length ? this._bytes[this._pos++] : -1;
    }
    var start = offset || 0;
    var count = length === undefined ? 1 : length;
    var read = 0;
    while (read < count && this._pos < this._bytes.length) { buffer[start + read++] = this._bytes[this._pos++]; }
    return read === 0 ? -1 : read;
};
ByteArrayInputStream.prototype.available = function () { return this._bytes.length - this._pos; };
ByteArrayInputStream.prototype.skip = function (n) { this._pos = Math.min(this._bytes.length, this._pos + n); return n; };
ByteArrayInputStream.prototype.close = function () { };
ByteArrayInputStream.prototype.mark = function () { this._mark = this._pos; };
ByteArrayInputStream.prototype.reset = function () { this._pos = this._mark || 0; };
ByteArrayInputStream.prototype.readAllBytes = function () {
    var out = this._bytes.slice(this._pos);
    this._pos = this._bytes.length;
    return out;
};

function BufferedInputStream(input) { this._input = input; }
_class('java.io.BufferedInputStream', BufferedInputStream);
BufferedInputStream.prototype.read = function () { return this._input.read.apply(this._input, arguments); };
BufferedInputStream.prototype.available = function () { return this._input.available ? this._input.available() : 0; };
BufferedInputStream.prototype.close = function () { if (this._input.close) { this._input.close(); } };

function InputStreamReader(input, charset) {
    this._input = input;
    this._charset = charset || 'UTF-8';
    this._text = null;
    this._pos = 0;
}
_class('java.io.InputStreamReader', InputStreamReader);
InputStreamReader.prototype._load = function () {
    if (this._text !== null) { return; }
    var bytes = this._input.readAllBytes ? this._input.readAllBytes() : _toByteArray(this._input);
    this._text = _bytesToStr(bytes, this._charset);
};
InputStreamReader.prototype.read = function () {
    this._load();
    return this._pos < this._text.length ? this._text.charCodeAt(this._pos++) : -1;
};
InputStreamReader.prototype.readAll = function () { this._load(); var s = this._text.slice(this._pos); this._pos = this._text.length; return s; };
InputStreamReader.prototype.ready = function () { return true; };
InputStreamReader.prototype.close = function () { if (this._input.close) { this._input.close(); } };

function JavaGZIPInputStream(input) {
    var bytes = input && input.readAllBytes ? input.readAllBytes() : _toByteArray(input);
    this._stream = new ByteArrayInputStream(_nativeGunzip(bytes));
}
_class('java.util.zip.GZIPInputStream', JavaGZIPInputStream);
JavaGZIPInputStream.prototype.read = function () { return this._stream.read.apply(this._stream, arguments); };
JavaGZIPInputStream.prototype.readAllBytes = function () { return this._stream.readAllBytes(); };
JavaGZIPInputStream.prototype.available = function () { return this._stream.available(); };
JavaGZIPInputStream.prototype.close = function () { };

function JavaByteBuffer(bytes, size) {
    this._bytes = bytes ? _toByteArray(bytes) : new Array(size || 0);
    for (var i = 0; i < this._bytes.length; i++) { if (this._bytes[i] === undefined) { this._bytes[i] = 0; } }
    this._pos = 0;
}
_class('java.nio.ByteBuffer', JavaByteBuffer);
JavaByteBuffer.allocate = function (size) { return new JavaByteBuffer(null, size); };
JavaByteBuffer.wrap = function (bytes) { return new JavaByteBuffer(bytes); };
JavaByteBuffer.prototype.array = function () { return this._bytes.slice(); };
JavaByteBuffer.prototype.put = function (value) {
    if (typeof value === 'number') { this._bytes.push(value & 255); }
    else { this._bytes = this._bytes.concat(_toByteArray(value)); }
    return this;
};
JavaByteBuffer.prototype.get = function (index) { return index === undefined ? this._bytes[this._pos++] : this._bytes[index]; };
JavaByteBuffer.prototype.position = function () { return this._pos; };
JavaByteBuffer.prototype.flip = function () { return this; };
JavaByteBuffer.prototype.remaining = function () { return this._bytes.length - this._pos; };
JavaByteBuffer.prototype.toString = function () { return _bytesToStr(this._bytes, 'UTF-8'); };

// ---------------------------------------------------------------------------
// 6. java.net
// ---------------------------------------------------------------------------

function JavaURL(raw, base) {
    var text = _str(raw);
    if (base && !/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(text)) {
        try { text = new URL(text, base).toString(); } catch (e) { text = _str(base).replace(/\/[^\/]*$/, '/') + text; }
    }
    var match = /^([a-zA-Z][a-zA-Z0-9+.-]*):\/\/([^\/:?#]*)(?::(\d+))?([^?#]*)(\?[^#]*)?(#.*)?/.exec(text);
    if (!match) {
        if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(text)) {
            this.protocol = text.slice(0, text.indexOf(':') + 1);
            this.host = '';
            this.port = -1;
            this.path = text.slice(text.indexOf(':') + 1);
            this.query = '';
            this.hash = '';
            this.href = text;
        } else {
            throw _err('MalformedURLException: ' + text);
        }
    } else {
        this.protocol = match[1] + ':';
        this.host = match[2];
        this.port = match[3] ? parseInt(match[3], 10) : -1;
        this.path = match[4] || '';
        this.query = match[5] || '';
        this.hash = match[6] || '';
        this.href = text;
    }
}
_class('java.net.URL', JavaURL);
JavaURL.prototype.getProtocol = function () { return this.protocol.replace(/:$/, ''); };
JavaURL.prototype.getHost = function () { return this.host; };
JavaURL.prototype.getPort = function () { return this.port; };
JavaURL.prototype.getPath = function () { return this.path; };
JavaURL.prototype.getQuery = function () { return this.query.replace(/^\?/, '') || null; };
JavaURL.prototype.getRef = function () { return this.hash.replace(/^#/, '') || null; };
JavaURL.prototype.getFile = function () { return this.path + this.query; };
JavaURL.prototype.getAuthority = function () { return this.port >= 0 ? this.host + ':' + this.port : this.host; };
JavaURL.prototype.toString = function () { return this.href; };
JavaURL.prototype.toExternalForm = function () { return this.href; };
JavaURL.prototype.openConnection = function () { throw _err('openConnection 未实现'); };

var JavaURLEncoder = {
    encode: function (text, charset) {
        var bytes = _strToBytes(_str(text), charset || 'UTF-8');
        var out = '';
        var safe = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.*';
        for (var i = 0; i < bytes.length; i++) {
            var b = bytes[i] & 255;
            var ch = String.fromCharCode(b);
            if (b === 32) { out += '+'; }
            else if (safe.indexOf(ch) >= 0) { out += ch; }
            else { out += '%' + (b < 16 ? '0' : '') + b.toString(16).toUpperCase(); }
        }
        return out;
    }
};
var JavaURLDecoder = {
    decode: function (text, charset) {
        var raw = _str(text).replace(/\+/g, ' ');
        var bytes = [];
        for (var i = 0; i < raw.length; i++) {
            if (raw.charAt(i) === '%' && i + 2 < raw.length) {
                bytes.push(parseInt(raw.substr(i + 1, 2), 16));
                i += 2;
            } else {
                bytes.push(raw.charCodeAt(i) & 255);
            }
        }
        return _bytesToStr(bytes, charset || 'UTF-8');
    }
};

var JavaURI = _class('java.net.URI', function (raw) { this._url = new JavaURL(raw); });
JavaURI.prototype.toString = function () { return this._url.toString(); };
JavaURI.prototype.getHost = function () { return this._url.getHost(); };
JavaURI.prototype.getPath = function () { return this._url.getPath(); };
JavaURI.prototype.getScheme = function () { return this._url.getProtocol(); };

// ---------------------------------------------------------------------------
// 7. java.math.BigInteger（内部用 BigInt，macOS/iOS 的 JSC 均支持）
// ---------------------------------------------------------------------------

function BigInteger(value, radix) {
    if (typeof value === 'bigint') { this._v = value; }
    else if (typeof value === 'number') { this._v = BigInt(Math.trunc(value)); }
    else {
        var text = _str(value).trim();
        var base = radix || 10;
        if (/^-/.test(text)) { this._v = -BigInt(parseRadix(text.slice(1), base)); }
        else { this._v = BigInt(parseRadix(text, base)); }
    }
}
function parseRadix(text, radix) {
    if (radix === 10) { return text; }
    if (radix === 16) { return '0x' + text; }
    if (radix === 8) { return '0o' + text; }
    if (radix === 2) { return '0b' + text; }
    var value = BigInt(0);
    var big = BigInt(radix);
    for (var i = 0; i < text.length; i++) {
        var digit = parseInt(text.charAt(i), radix);
        if (isNaN(digit)) { throw _err('NumberFormatException: ' + text); }
        value = value * big + BigInt(digit);
    }
    return value;
}
_class('java.math.BigInteger', BigInteger);
BigInteger.ZERO = new BigInteger(0);
BigInteger.ONE = new BigInteger(1);
BigInteger.TEN = new BigInteger(10);
BigInteger.prototype.add = function (other) { return new BigInteger(this._v + toBig(other)); };
BigInteger.prototype.subtract = function (other) { return new BigInteger(this._v - toBig(other)); };
BigInteger.prototype.multiply = function (other) { return new BigInteger(this._v * toBig(other)); };
BigInteger.prototype.divide = function (other) { return new BigInteger(this._v / toBig(other)); };
BigInteger.prototype.remainder = function (other) { return new BigInteger(this._v % toBig(other)); };
BigInteger.prototype.mod = function (other) {
    var m = toBig(other);
    var r = this._v % m;
    return new BigInteger(r < 0 ? r + m : r);
};
BigInteger.prototype.pow = function (exponent) { return new BigInteger(this._v ** BigInt(exponent)); };
BigInteger.prototype.modPow = function (exponent, modulus) {
    var e = toBig(exponent), m = toBig(modulus), result = BigInt(1), base = this._v % m;
    while (e > 0) {
        if (e & BigInt(1)) { result = (result * base) % m; }
        base = (base * base) % m;
        e >>= BigInt(1);
    }
    return new BigInteger(result);
};
BigInteger.prototype.compareTo = function (other) { var o = toBig(other); return this._v < o ? -1 : (this._v > o ? 1 : 0); };
BigInteger.prototype.equals = function (other) { return this._v === toBig(other); };
BigInteger.prototype.intValue = function () { return Number(this._v & BigInt(0xFFFFFFFF)); };
BigInteger.prototype.longValue = function () { return Number(this._v); };
BigInteger.prototype.toString = function (radix) { return this._v.toString(radix || 10); };
BigInteger.prototype.toByteArray = function () {
    var hex = this._v < 0 ? (-this._v).toString(16) : this._v.toString(16);
    if (hex.length % 2) { hex = '0' + hex; }
    var bytes = _hexDecode(hex);
    if (this._v < 0) { bytes.unshift(0x80); } else if (bytes.length && (bytes[0] & 0x80)) { bytes.unshift(0x00); }
    return bytes;
};
BigInteger.prototype.toString = function (radix) { return this._v.toString(radix || 10); };
function toBig(value) {
    if (value instanceof BigInteger) { return value._v; }
    if (typeof value === 'bigint') { return value; }
    return BigInt(Math.trunc(Number(value)));
}

// ---------------------------------------------------------------------------
// 8. javax.crypto / java.security
// ---------------------------------------------------------------------------

function _normalizeTransformation(transformation) {
    var t = _str(transformation);
    if (!t) { t = 'AES/ECB/PKCS5Padding'; }
    if (t.indexOf('/') < 0) { t += '/ECB/PKCS5Padding'; }
    return t;
}

function _keyBytes(key) {
    if (_isNil(key)) { return []; }
    if (key instanceof SecretKeySpec || key instanceof DESKeySpec) { return _toByteArray(key._keyBytes || []); }
    if (typeof key === 'string') { return _strToBytes(key, 'UTF-8'); }
    if (key && typeof key.getEncoded === 'function') { return _toByteArray(key.getEncoded()); }
    return _toByteArray(key);
}

function _ivBytes(value) {
    if (_isNil(value)) { return null; }
    if (value instanceof IvParameterSpec) { return _toByteArray(value._ivBytes || []); }
    if (value && value._ivBytes) { return _toByteArray(value._ivBytes); }
    if (typeof value === 'string') { return _strToBytes(value, 'UTF-8'); }
    return _toByteArray(value);
}

function SecretKeySpec(key, algorithm) {
    this._keyBytes = _keyBytes(key);
    this._algorithm = _str(algorithm);
}
_class('javax.crypto.spec.SecretKeySpec', SecretKeySpec);
SecretKeySpec.prototype.getEncoded = function () { return this._keyBytes.slice(); };
SecretKeySpec.prototype.getAlgorithm = function () { return this._algorithm; };
SecretKeySpec.prototype.getFormat = function () { return 'RAW'; };

function IvParameterSpec(iv) { this._ivBytes = _ivBytes(iv) || []; }
_class('javax.crypto.spec.IvParameterSpec', IvParameterSpec);
IvParameterSpec.prototype.getIV = function () { return this._ivBytes.slice(); };

function DESKeySpec(key) { this._keyBytes = _keyBytes(key); }
_class('javax.crypto.spec.DESKeySpec', DESKeySpec);
DESKeySpec.prototype.getKey = function () { return this._keyBytes.slice(); };

var SecretKeyFactory = _class('javax.crypto.SecretKeyFactory', function (algorithm) { this._algorithm = algorithm; });
SecretKeyFactory.getInstance = function (algorithm) { return new SecretKeyFactory(algorithm); };
SecretKeyFactory.prototype.generateSecret = function (spec) {
    if (spec instanceof SecretKeySpec) { return spec; }
    return new SecretKeySpec(spec && spec.getKey ? spec.getKey() : spec, this._algorithm);
};
SecretKeyFactory.prototype.getKeySpec = function (key) {
    return new SecretKeySpec(key && key.getEncoded ? key.getEncoded() : key, this._algorithm);
};

var KeyGenerator = _class('javax.crypto.KeyGenerator', function (algorithm) { this._algorithm = algorithm; });
KeyGenerator.getInstance = function (algorithm) { return new KeyGenerator(algorithm); };
KeyGenerator.prototype.generateKey = function () {
    var upper = _str(this._algorithm).toUpperCase();
    var size = upper.indexOf('DESEDE') >= 0 ? 24 : (upper.indexOf('DES') >= 0 ? 8 : 16);
    var bytes = [];
    for (var i = 0; i < size; i++) { bytes.push(Math.floor(Math.random() * 256)); }
    return new SecretKeySpec(bytes, this._algorithm);
};

function JavaCipher(transformation) {
    this.transformation = _normalizeTransformation(transformation);
    this._mode = 1;
    this._keyBytes = [];
    this._ivBytes = null;
    this._buffer = [];
}
_class('javax.crypto.Cipher', JavaCipher);
JavaCipher.ENCRYPT_MODE = 1;
JavaCipher.DECRYPT_MODE = 2;
JavaCipher.WRAP_MODE = 3;
JavaCipher.UNWRAP_MODE = 4;
JavaCipher.getInstance = function (transformation) { return new JavaCipher(transformation); };
JavaCipher.prototype.init = function (mode, key, params) {
    this._mode = mode;
    this._keyBytes = _keyBytes(key);
    this._ivBytes = _ivBytes(params);
    this._buffer = [];
    return this;
};
JavaCipher.prototype.update = function (input) {
    this._buffer = this._buffer.concat(_toByteArray(input));
    return [];
};
JavaCipher.prototype.doFinal = function (input) {
    var data = _isNil(input) ? this._buffer : _toByteArray(input);
    this._buffer = [];
    var dataB64 = _bytesToBase64(data);
    var keyB64 = _bytesToBase64(this._keyBytes);
    var ivB64 = this._ivBytes && this._ivBytes.length ? _bytesToBase64(this._ivBytes) : null;
    var decrypt = this._mode === 2;
    var output = _nativeCipherProcess(dataB64, keyB64, this.transformation, ivB64, decrypt);
    if (typeof output !== 'string') { throw _err('Cipher.doFinal: 原生加解密失败（' + this.transformation + '）'); }
    return _base64ToBytes(output);
};
JavaCipher.prototype.getIV = function () { return this._ivBytes ? this._ivBytes.slice() : null; };
JavaCipher.prototype.getAlgorithm = function () { return this.transformation.split('/')[0]; };
JavaCipher.prototype.getBlockSize = function () { return this.transformation.toUpperCase().indexOf('AES') >= 0 ? 16 : 8; };
JavaCipher.prototype.getProvider = function () { return { getName: function () { return 'ZhijianNative'; } }; };
JavaCipher.prototype.updateAAD = function () { };

function MessageDigest(algorithm) {
    this._algorithm = _normalizeDigestName(algorithm);
    this._data = [];
}
_class('java.security.MessageDigest', MessageDigest);
function _normalizeDigestName(algorithm) {
    var upper = _str(algorithm).toUpperCase().replace(/-/g, '');
    if (upper === 'SHA') { return 'SHA-1'; }
    if (upper === 'SHA1') { return 'SHA-1'; }
    if (upper === 'SHA256') { return 'SHA-256'; }
    if (upper === 'SHA384') { return 'SHA-384'; }
    if (upper === 'SHA512') { return 'SHA-512'; }
    if (upper === 'MD5') { return 'MD5'; }
    return _str(algorithm);
}
MessageDigest.getInstance = function (algorithm) { return new MessageDigest(algorithm); };
MessageDigest.isEqual = function (a, b) { return _hexEncode(a) === _hexEncode(b); };
MessageDigest.prototype.update = function (input) {
    this._data = this._data.concat(_toByteArray(input));
    return this;
};
MessageDigest.prototype.digest = function (input) {
    var data = this._data;
    if (input !== undefined) { data = data.concat(_toByteArray(input)); }
    var b64 = _nativeDigestBase64(data, this._algorithm);
    this._data = [];
    return _base64ToBytes(b64);
};
MessageDigest.prototype.reset = function () { this._data = []; return this; };
MessageDigest.prototype.getAlgorithm = function () { return this._algorithm; };
MessageDigest.prototype.getDigestLength = function () {
    var a = this._algorithm.toUpperCase();
    if (a === 'MD5') { return 16; }
    if (a === 'SHA-1') { return 20; }
    if (a === 'SHA-256') { return 32; }
    if (a === 'SHA-384') { return 48; }
    if (a === 'SHA-512') { return 64; }
    return 32;
};

var Mac = _class('javax.crypto.Mac', function (algorithm) { this._algorithm = algorithm; this._key = []; this._data = []; });
Mac.getInstance = function (algorithm) { return new Mac(algorithm); };
Mac.prototype.init = function (key) { this._key = _keyBytes(key); return this; };
Mac.prototype.update = function (input) { this._data = this._data.concat(_toByteArray(input)); return this; };
Mac.prototype.doFinal = function (input) {
    var data = this._data.concat(input === undefined ? [] : _toByteArray(input));
    var b64 = _nativeHMacBase64(this._key, data, this._algorithm);
    this._data = [];
    return _base64ToBytes(b64);
};

// java.security KeyFactory / Signature（KeyFactory 的形状兼容；RSA 签名走 native Security）
function PKCS8EncodedKeySpec(bytes) { this._bytes = _toByteArray(bytes); }
_class('java.security.spec.PKCS8EncodedKeySpec', PKCS8EncodedKeySpec);
PKCS8EncodedKeySpec.prototype.getEncoded = function () { return this._bytes.slice(); };
PKCS8EncodedKeySpec.prototype.getFormat = function () { return 'PKCS#8'; };

function X509EncodedKeySpec(bytes) { this._bytes = _toByteArray(bytes); }
_class('java.security.spec.X509EncodedKeySpec', X509EncodedKeySpec);
X509EncodedKeySpec.prototype.getEncoded = function () { return this._bytes.slice(); };
X509EncodedKeySpec.prototype.getFormat = function () { return 'X.509'; };

function RSAPrivateKeySpec(modulus, exponent) {
    this._modulus = toBig(modulus);
    this._exponent = toBig(exponent);
}
RSAPrivateKeySpec.prototype.getModulus = function () { return new BigInteger(this._modulus); };
RSAPrivateKeySpec.prototype.getPrivateExponent = function () { return new BigInteger(this._exponent); };

function _makeKeyObject(bytes, algorithm, isPrivate) {
    return {
        __javaKey: true,
        _keyBase64: _bytesToBase64(_toByteArray(bytes)),
        _algorithm: _str(algorithm),
        getAlgorithm: function () { return _str(algorithm); },
        getFormat: function () { return isPrivate ? 'PKCS#8' : 'X.509'; },
        getEncoded: function () { return _toByteArray(bytes); }
    };
}

var KeyFactory = _class('java.security.KeyFactory', function (algorithm) { this._algorithm = algorithm; });
KeyFactory.getInstance = function (algorithm) { return new KeyFactory(algorithm); };
KeyFactory.prototype.generatePrivate = function (spec) {
    return _makeKeyObject(spec.getEncoded ? spec.getEncoded() : spec, this._algorithm, true);
};
KeyFactory.prototype.generatePublic = function (spec) {
    return _makeKeyObject(spec.getEncoded ? spec.getEncoded() : spec, this._algorithm, false);
};

function Signature(algorithm) {
    this._algorithm = _str(algorithm);
    this._impl = global.java && typeof global.java.createSign === 'function' ? global.java.createSign(this._algorithm) : null;
}
_class('java.security.Signature', Signature);
Signature.getInstance = function (algorithm) { return new Signature(algorithm); };
Signature.prototype.initSign = function (key) {
    if (!this._impl) { throw _err('Signature: native createSign 不可用'); }
    var bytes = key && key._keyBase64 ? key : _makeKeyObject(_keyBytes(key), this._algorithm, true);
    this._impl.initSign(bytes);
    return this;
};
Signature.prototype.initVerify = function (key) {
    if (!this._impl) { throw _err('Signature: native createSign 不可用'); }
    var bytes = key && key._keyBase64 ? key : _makeKeyObject(_keyBytes(key), this._algorithm, false);
    this._impl.initVerify(bytes);
    return this;
};
Signature.prototype.update = function (data) {
    if (!this._impl) { throw _err('Signature: native createSign 不可用'); }
    if (typeof data === 'string') { this._impl.update(data); }
    else { this._impl.update(_toByteArray(data)); }
    return this;
};
Signature.prototype.sign = function () {
    if (!this._impl) { throw _err('Signature: native createSign 不可用'); }
    return this._impl.sign();
};
Signature.prototype.verify = function (signature) {
    if (!this._impl) { throw _err('Signature: native createSign 不可用'); }
    return this._impl.verify(_toByteArray(signature));
};

var SecureRandom = _class('java.security.SecureRandom', function () {
    this._seed = [];
});
SecureRandom.prototype.nextBytes = function (bytes) {
    for (var i = 0; i < bytes.length; i++) { bytes[i] = Math.floor(Math.random() * 256); }
};
SecureRandom.prototype.nextInt = function (bound) { return Math.floor(Math.random() * (bound || 2147483647)); };
SecureRandom.prototype.generateSeed = function (count) { var b = []; this.nextBytes(b); while (b.length < count) { b.push(0); } return b.slice(0, count); };

// ---------------------------------------------------------------------------
// 9. android.util / android.text / android.graphics
// ---------------------------------------------------------------------------

var AndroidBase64 = {
    DEFAULT: 0,
    NO_PADDING: 1,
    NO_WRAP: 2,
    CRLF: 4,
    URL_SAFE: 8,
    NO_CLOSE: 16,
    decode: function (text, flags) {
        var clean = _str(text).replace(/\s+/g, '');
        if ((flags || 0) & 8) { clean = clean.replace(/-/g, '+').replace(/_/g, '/'); }
        return _base64ToBytes(clean);
    },
    encode: function (bytes, flags) { return _strToBytes(AndroidBase64.encodeToString(bytes, flags), 'UTF-8'); },
    encodeToString: function (bytes, flags) {
        var text = _bytesToBase64(bytes);
        if ((flags || 0) & 8) { text = text.replace(/\+/g, '-').replace(/\//g, '_'); }
        if ((flags || 0) & 1) { text = text.replace(/=+$/, ''); }
        if (!((flags || 0) & (2 | 4))) {
            var lines = [];
            for (var i = 0; i < text.length; i += 76) { lines.push(text.slice(i, i + 76)); }
            return lines.join('\n');
        }
        return text;
    }
};

var AndroidTextUtils = {
    isEmpty: function (text) { return _isNil(text) || _str(text).length === 0; },
    join: function (delimiter, tokens) {
        if (tokens === undefined) { tokens = delimiter; delimiter = ','; }
        var out = [];
        if (tokens && typeof tokens.size === 'function') {
            for (var i = 0; i < tokens.size(); i++) { out.push(_str(tokens.get(i))); }
        } else if (tokens) {
            for (var j = 0; j < tokens.length; j++) { out.push(_str(tokens[j])); }
        }
        return out.join(_str(delimiter));
    }
};

var AndroidBitmapFactory = {
    decodeStream: function () { return null; },
    decodeByteArray: function () { return null; },
    decodeFile: function () { return null; }
};

// ---------------------------------------------------------------------------
// 10. cn.hutool
// ---------------------------------------------------------------------------

var HutoolBase64 = {
    encode: function (data) { return typeof data === 'string' ? _bytesToBase64(_strToBytes(data, 'UTF-8')) : _bytesToBase64(data); },
    decodeStr: function (text) { return _bytesToStr(_base64ToBytes(text), 'UTF-8'); },
    decode: function (text) { return _base64ToBytes(text); }
};

var HutoolStrUtil = {
    isEmpty: function (text) { return _isNil(text) || _str(text).length === 0; },
    isNotEmpty: function (text) { return !HutoolStrUtil.isEmpty(text); },
    isBlank: function (text) { return /^\s*$/.test(_str(text)); },
    isNotBlank: function (text) { return !HutoolStrUtil.isBlank(text); },
    reverse: function (text) { return _str(text).split('').reverse().join(''); },
    cleanBlank: function (text) { return _str(text).replace(/\s+/g, ''); },
    trim: function (text) { return _str(text).trim(); },
    nullToEmpty: function (text) { return _isNil(text) ? '' : _str(text); },
    contains: function (text, search) { return _str(text).indexOf(_str(search)) >= 0; },
    format: function (template) {
        var args = Array.prototype.slice.call(arguments, 1), index = 0;
        return _str(template).replace(/\{\}/g, function () { return _str(args[index++]); });
    },
    split: function (text, separator) { return _str(text).split(_str(separator)); },
    sub: function (text, start, end) { return end === undefined ? _str(text).substring(start) : _str(text).substring(start, end); }
};

var HutoolZipUtil = {
    gzip: function (data) {
        if (typeof data === 'string') { return _nativeGzip(_strToBytes(data, 'UTF-8')); }
        return _nativeGzip(_toByteArray(data));
    },
    unGzip: function (data) {
        if (typeof data === 'string') { return _bytesToStr(_nativeGunzip(_strToBytes(data, 'UTF-8')), 'UTF-8'); }
        return _nativeGunzip(_toByteArray(data));
    }
};

var HutoolDigestUtil = {
    md5: function (data) { return _hexEncode(_base64ToBytes(_nativeDigestBase64(_toByteArray(data), 'MD5'))); },
    md5Hex: function (data) { return HutoolDigestUtil.md5(data); },
    sha1Hex: function (data) { return _hexEncode(_base64ToBytes(_nativeDigestBase64(_toByteArray(data), 'SHA-1'))); },
    sha256Hex: function (data) { return _hexEncode(_base64ToBytes(_nativeDigestBase64(_toByteArray(data), 'SHA-256'))); },
    digestHex: function (data, algorithm) { return _hexEncode(_base64ToBytes(_nativeDigestBase64(_toByteArray(data), algorithm))); }
};

// ---------------------------------------------------------------------------
// 11. com.jayway.jsonpath
// ---------------------------------------------------------------------------

var JsonPathOption = {
    DEFAULT_PATH_LEAF_TO_NULL: 'DEFAULT_PATH_LEAF_TO_NULL',
    ALWAYS_RETURN_LIST: 'ALWAYS_RETURN_LIST',
    SUPPRESS_EXCEPTIONS: 'SUPPRESS_EXCEPTIONS',
    AS_PATH_LIST: 'AS_PATH_LIST'
};

var JsonPathConfiguration = {
    defaultConfiguration: function () { return { options: [] }; },
    builder: function () {
        var config = { options: [] };
        var builder = {
            options: function () {
                for (var i = 0; i < arguments.length; i++) { config.options.push(arguments[i]); }
                return builder;
            },
            build: function () { return config; }
        };
        return builder;
    }
};

function _jsonPathRead(json, path, config) {
    var suppress = !!(config && config.options && config.options.indexOf('SUPPRESS_EXCEPTIONS') >= 0);
    return _nativeJsonPathRead(json, path, suppress);
}

var JaywayJsonPath = {
    read: function (json, path) { return _jsonPathRead(json, path, null); },
    parse: function (json) {
        return {
            read: function (path) { return _jsonPathRead(json, path, null); }
        };
    },
    using: function (config) {
        return {
            parse: function (json) {
                return {
                    read: function (path) { return _jsonPathRead(json, path, config); }
                };
            },
            read: function (json, path) { return _jsonPathRead(json, path, config); }
        };
    },
    compile: function (path) {
        return {
            read: function (json) { return _jsonPathRead(json, path, null); }
        };
    }
};

// ---------------------------------------------------------------------------
// 12. io.legado.app.help.http.StrResponse / okhttp3
// ---------------------------------------------------------------------------

function StrResponse(url, body) {
    this._url = _str(url);
    this._body = _str(body);
}
_class('io.legado.app.help.http.StrResponse', StrResponse);
StrResponse.prototype.body = function () { return this._body; };
StrResponse.prototype.bodyText = function () { return this._body; };
StrResponse.prototype.url = function () { return this._url; };
StrResponse.prototype.code = function () { return 200; };
StrResponse.prototype.message = function () { return 'OK'; };
StrResponse.prototype.headers = function () { return {}; };
StrResponse.prototype.toString = function () { return this._body; };

function MediaType(value) { this._value = _str(value); }
_class('okhttp3.MediaType', MediaType);
MediaType.parse = function (value) { return new MediaType(value); };
MediaType.prototype.toString = function () { return this._value; };

function RequestBody(mediaType, content) {
    this._mediaType = mediaType;
    this._content = content;
}
_class('okhttp3.RequestBody', RequestBody);
RequestBody.create = function (mediaType, content) { return new RequestBody(mediaType, content); };
RequestBody.prototype.contentType = function () { return this._mediaType; };
RequestBody.prototype.toString = function () { return _str(this._content); };
RequestBody.prototype.content = function () { return this._content; };

function RequestBuilder() {
    this._url = '';
    this._method = 'GET';
    this._body = null;
    this._headers = {};
}
RequestBuilder.prototype.url = function (value) { this._url = _str(value); return this; };
RequestBuilder.prototype.method = function (method, body) { this._method = _str(method).toUpperCase(); if (body) { this._body = body; } return this; };
RequestBuilder.prototype.get = function () { this._method = 'GET'; return this; };
RequestBuilder.prototype.post = function (body) { this._method = 'POST'; this._body = body; return this; };
RequestBuilder.prototype.put = function (body) { this._method = 'PUT'; this._body = body; return this; };
RequestBuilder.prototype.delete = function () { this._method = 'DELETE'; return this; };
RequestBuilder.prototype.header = function (key, value) { this._headers[_str(key)] = _str(value); return this; };
RequestBuilder.prototype.addHeader = function (key, value) { this._headers[_str(key)] = _str(value); return this; };
RequestBuilder.prototype.headers = function (headers) {
    if (headers) {
        if (typeof headers.toMap === 'function') { headers = headers.toMap(); }
        for (var key in headers) { if (Object.prototype.hasOwnProperty.call(headers, key)) { this._headers[key] = _str(headers[key]); } }
    }
    return this;
};
RequestBuilder.prototype.build = function () {
    return { __request: true, url: this._url, method: this._method, body: this._body, headers: this._headers };
};

function OkHttpClient() { }
_class('okhttp3.OkHttpClient', OkHttpClient);
OkHttpClient.prototype.newBuilder = function () {
    var client = this;
    return { build: function () { return client; }, connectTimeout: function () { return this; }, readTimeout: function () { return this; }, writeTimeout: function () { return this; } };
};
OkHttpClient.prototype.execute = function (request) {
    var bodyText = request.body && request.body._content !== undefined ? _str(request.body._content) : (request.body ? _str(request.body) : '');
    var headersJson = JSON.stringify(request.headers || {});
    var result = _jsoupConnectFetch(request.url, request.method || 'GET', bodyText, headersJson, 30);
    if (!result) { throw _err('OkHttp execute 失败：' + request.url); }
    return new OkHttpResponse(result, request.url);
};

function OkHttpResponse(raw, url) {
    this._raw = raw;
    this._url = url;
}
_class('okhttp3.Response', OkHttpResponse);
OkHttpResponse.prototype.code = function () { return this._raw.status || 0; };
OkHttpResponse.prototype.message = function () { return this._raw.status === 200 ? 'OK' : ''; };
OkHttpResponse.prototype.isSuccessful = function () { return this.code() >= 200 && this.code() < 300; };
OkHttpResponse.prototype.url = function () { return this._url; };
OkHttpResponse.prototype.body = function () {
    var raw = this._raw;
    return {
        string: function () { return _str(raw.bodyText); },
        bytes: function () { return _strToBytes(_str(raw.bodyText), 'UTF-8'); },
        contentLength: function () { return _str(raw.bodyText).length; },
        contentType: function () { return MediaType.parse('text/html; charset=utf-8'); },
        close: function () { }
    };
};
OkHttpResponse.prototype.headers = function () {
    var map = this._raw.headerMap || {};
    return {
        get: function (name) { return map[name] === undefined ? null : map[name]; },
        toMap: function () { return map; },
        names: function () { return Object.keys(map); }
    };
};

var OkHttpHeaders = {
    of: function () {
        var map = {};
        for (var i = 0; i + 1 < arguments.length; i += 2) { map[_str(arguments[i])] = _str(arguments[i + 1]); }
        return { get: function (name) { return map[name] || null; }, toMap: function () { return map; } };
    }
};

// ---------------------------------------------------------------------------
// 13. 安装到 Packages / 全局
// ---------------------------------------------------------------------------

_install('java.lang', 'String', JavaString);
_install('java.lang', 'Integer', JavaInteger);
_install('java.lang', 'Long', JavaLong);
_install('java.lang', 'Double', JavaDouble);
_install('java.lang', 'Boolean', JavaBoolean);
_install('java.lang', 'Math', JavaMath);
_install('java.lang', 'System', JavaSystem);
_install('java.lang', 'Thread', JavaThread);
_install('java.lang', 'StringBuilder', JavaStringBuilder);
_install('java.lang', 'StringBuffer', JavaStringBuffer);
_install('java.lang', 'Exception', JavaException);
_install('java.lang', 'RuntimeException', JavaRuntimeException);

_install('java.util', 'ArrayList', ArrayList);
_install('java.util', 'LinkedList', ArrayList);
_install('java.util', 'LinkedHashMap', LinkedHashMap);
_install('java.util', 'HashMap', HashMap);
_install('java.util', 'HashSet', ArrayList);
_install('java.util', 'Arrays', JavaArrays);
_install('java.util', 'Collections', JavaCollections);
_install('java.util', 'Base64', JavaBase64);
_install('java.util', 'UUID', JavaUUID);
_install('java.util', 'TimeUnit', JavaTimeUnit);
_install('java.util.regex', 'Pattern', JavaPattern);
_install('java.util.regex', 'Matcher', JavaMatcher);
_install('java.util.zip', 'GZIPInputStream', JavaGZIPInputStream);

_install('java.io', 'ByteArrayInputStream', ByteArrayInputStream);
_install('java.io', 'ByteArrayOutputStream', ByteArrayOutputStream);
_install('java.io', 'BufferedInputStream', BufferedInputStream);
_install('java.io', 'InputStreamReader', InputStreamReader);
_install('java.io', 'IOException', JavaException);

_install('java.net', 'URL', JavaURL);
_install('java.net', 'URI', JavaURI);
_install('java.net', 'URLEncoder', JavaURLEncoder);
_install('java.net', 'URLDecoder', JavaURLDecoder);

_install('java.math', 'BigInteger', BigInteger);
_install('java.nio', 'ByteBuffer', JavaByteBuffer);

_install('javax.crypto', 'Cipher', JavaCipher);
_install('javax.crypto', 'SecretKeyFactory', SecretKeyFactory);
_install('javax.crypto', 'KeyGenerator', KeyGenerator);
_install('javax.crypto', 'Mac', Mac);
_install('javax.crypto.spec', 'SecretKeySpec', SecretKeySpec);
_install('javax.crypto.spec', 'IvParameterSpec', IvParameterSpec);
_install('javax.crypto.spec', 'DESKeySpec', DESKeySpec);

_install('java.security', 'MessageDigest', MessageDigest);
_install('java.security', 'KeyFactory', KeyFactory);
_install('java.security', 'Signature', Signature);
_install('java.security', 'SecureRandom', SecureRandom);
_install('java.security.spec', 'PKCS8EncodedKeySpec', PKCS8EncodedKeySpec);
_install('java.security.spec', 'X509EncodedKeySpec', X509EncodedKeySpec);
_install('java.security.spec', 'RSAPrivateKeySpec', RSAPrivateKeySpec);

_install('android.util', 'Base64', AndroidBase64);
_install('android.text', 'TextUtils', AndroidTextUtils);
_install('android.graphics', 'BitmapFactory', AndroidBitmapFactory);

_install('cn.hutool.core.codec', 'Base64', HutoolBase64);
_install('cn.hutool.core.util', 'StrUtil', HutoolStrUtil);
_install('cn.hutool.core.util', 'ZipUtil', HutoolZipUtil);
_install('cn.hutool.crypto.digest', 'DigestUtil', HutoolDigestUtil);


// ---------------------------------------------------------------------------
// 8.5 fastjson / Gson 兼容（书源常用 JSON 封装）
// ---------------------------------------------------------------------------

function _jsonParseLoose(text) {
    if (_isNil(text)) { return null; }
    try { return JSON.parse(_str(text)); } catch (e) { return null; }
}
function _jsonRaw(value) {
    if (value && value.__jsonObject) { return value._map; }
    if (value && value.__jsonArray) { return value._array; }
    return value;
}
function _jsonStringify(value) {
    try { return JSON.stringify(_jsonRaw(value)); } catch (e) { return 'null'; }
}
function _wrapJSON(value) {
    if (value && typeof value === 'object') {
        return Array.isArray(value) ? new FastjsonJSONArray(value) : new FastjsonJSONObject(value);
    }
    return value;
}

function FastjsonJSONObject(map) {
    this.__jsonObject = true;
    if (map && map.__jsonObject) { this._map = map._map; }
    else { this._map = map && typeof map === 'object' ? map : {}; }
}
_define(FastjsonJSONObject.prototype, 'get', function (key) { return _wrapJSON(this._map[_str(key)]); });
_define(FastjsonJSONObject.prototype, 'getString', function (key) {
    var v = this._map[_str(key)];
    return _isNil(v) ? null : String(v);
});
_define(FastjsonJSONObject.prototype, 'getInt', function (key) {
    var v = this._map[_str(key)];
    return _isNil(v) ? 0 : (parseInt(v, 10) || 0);
});
_define(FastjsonJSONObject.prototype, 'getInteger', FastjsonJSONObject.prototype.getInt);
_define(FastjsonJSONObject.prototype, 'getLong', FastjsonJSONObject.prototype.getInt);
_define(FastjsonJSONObject.prototype, 'getDouble', function (key) {
    var v = this._map[_str(key)];
    return _isNil(v) ? 0 : (parseFloat(v) || 0);
});
_define(FastjsonJSONObject.prototype, 'getFloat', FastjsonJSONObject.prototype.getDouble);
_define(FastjsonJSONObject.prototype, 'getBoolean', function (key) {
    var v = this._map[_str(key)];
    return v === true || v === 'true' || v === 1 || v === '1';
});
_define(FastjsonJSONObject.prototype, 'getBooleanValue', FastjsonJSONObject.prototype.getBoolean);
_define(FastjsonJSONObject.prototype, 'getJSONObject', function (key) {
    var v = this._map[_str(key)];
    if (_isNil(v)) { return null; }
    if (typeof v === 'string') { v = _jsonParseLoose(v); }
    return _wrapJSON(v);
});
_define(FastjsonJSONObject.prototype, 'getJSONArray', function (key) {
    var v = this._map[_str(key)];
    if (_isNil(v)) { return null; }
    if (typeof v === 'string') { v = _jsonParseLoose(v); }
    return _wrapJSON(v);
});
_define(FastjsonJSONObject.prototype, 'optString', function (key, fallback) {
    var v = this._map[_str(key)];
    return _isNil(v) ? _str(fallback) : String(v);
});
_define(FastjsonJSONObject.prototype, 'optInt', function (key, fallback) {
    var v = this._map[_str(key)];
    return _isNil(v) ? (parseInt(fallback, 10) || 0) : (parseInt(v, 10) || 0);
});
_define(FastjsonJSONObject.prototype, 'optBoolean', function (key, fallback) {
    var v = this._map[_str(key)];
    if (_isNil(v)) { return fallback === true; }
    return v === true || v === 'true' || v === 1 || v === '1';
});
_define(FastjsonJSONObject.prototype, 'optJSONObject', function (key) {
    var v = this._map[_str(key)];
    return _isNil(v) ? null : _wrapJSON(v);
});
_define(FastjsonJSONObject.prototype, 'optJSONArray', function (key) {
    var v = this._map[_str(key)];
    return _isNil(v) ? null : _wrapJSON(v);
});
_define(FastjsonJSONObject.prototype, 'containsKey', function (key) {
    return Object.prototype.hasOwnProperty.call(this._map, _str(key));
});
_define(FastjsonJSONObject.prototype, 'size', function () { return Object.keys(this._map).length; });
_define(FastjsonJSONObject.prototype, 'isEmpty', function () { return Object.keys(this._map).length === 0; });
_define(FastjsonJSONObject.prototype, 'keySet', function () { return Object.keys(this._map); });
_define(FastjsonJSONObject.prototype, 'entrySet', function () {
    var self = this;
    return Object.keys(this._map).map(function (k) {
        return { key: k, value: self._map[k], getKey: function () { return k; }, getValue: function () { return self._map[k]; } };
    });
});
_define(FastjsonJSONObject.prototype, 'put', function (key, value) {
    this._map[_str(key)] = value; return value;
});
_define(FastjsonJSONObject.prototype, 'toJSONString', function () { return _jsonStringify(this._map); });
_define(FastjsonJSONObject.prototype, 'toString', function () { return _jsonStringify(this._map); });
_define(FastjsonJSONObject.prototype, 'getAsString', function () { return _jsonStringify(this._map); });
_define(FastjsonJSONObject.prototype, 'getAsJsonObject', function () { return this; });
_define(FastjsonJSONObject.prototype, 'getAsJsonArray', function () { return null; });
_define(FastjsonJSONObject.prototype, 'has', function (key) { return this.containsKey(key); });
_define(FastjsonJSONObject.prototype, 'add', function (key, value) { return this.put(key, value); });

function FastjsonJSONArray(array) {
    this.__jsonArray = true;
    if (array && array.__jsonArray) { this._array = array._array; }
    else { this._array = Array.isArray(array) ? array : []; }
}
_define(FastjsonJSONArray.prototype, 'size', function () { return this._array.length; });
_define(FastjsonJSONArray.prototype, 'isEmpty', function () { return this._array.length === 0; });
_define(FastjsonJSONArray.prototype, 'get', function (index) { return _wrapJSON(this._array[index | 0]); });
_define(FastjsonJSONArray.prototype, 'getJSONObject', function (index) { return _wrapJSON(this._array[index | 0]); });
_define(FastjsonJSONArray.prototype, 'getJSONArray', function (index) { return _wrapJSON(this._array[index | 0]); });
_define(FastjsonJSONArray.prototype, 'getString', function (index) {
    var v = this._array[index | 0];
    return _isNil(v) ? null : String(v);
});
_define(FastjsonJSONArray.prototype, 'optString', function (index, fallback) {
    var v = this._array[index | 0];
    return _isNil(v) ? _str(fallback) : String(v);
});
_define(FastjsonJSONArray.prototype, 'toArray', function () { return this._array.slice(); });
_define(FastjsonJSONArray.prototype, 'toJSONString', function () { return _jsonStringify(this._array); });
_define(FastjsonJSONArray.prototype, 'toString', function () { return _jsonStringify(this._array); });
_define(FastjsonJSONArray.prototype, 'getAsJsonArray', function () { return this; });
_define(FastjsonJSONArray.prototype, 'getAsString', function () { return _jsonStringify(this._array); });
_define(FastjsonJSONArray.prototype, 'forEach', function (fn) { this._array.forEach(function (v, i) { fn(_wrapJSON(v), i); }); });

var FastjsonJSON = {
    parse: function (text) { return _wrapJSON(_jsonParseLoose(text)); },
    parseObject: function (text) { return _wrapJSON(_jsonParseLoose(text)) || new FastjsonJSONObject({}); },
    parseArray: function (text) { return _wrapJSON(_jsonParseLoose(text)) || new FastjsonJSONArray([]); },
    toJSONString: function (value) { return _jsonStringify(value); },
    toJavaObject: function (value) { return _wrapJSON(value); },
    isNull: function (value) { return _isNil(value); }
};

function Gson() {}
Gson.prototype.fromJson = function (text, type) { return _wrapJSON(_jsonParseLoose(text)); };
Gson.prototype.toJson = function (value) { return _jsonStringify(value); };
function GsonBuilder() { this._gson = new Gson(); }
GsonBuilder.prototype.setPrettyPrinting = function () { return this; };
GsonBuilder.prototype.disableHtmlEscaping = function () { return this; };
GsonBuilder.prototype.create = function () { return this._gson; };

var JsonParser = {
    parseString: function (text) { return _wrapJSON(_jsonParseLoose(text)); },
    parse: function (text) { return _wrapJSON(_jsonParseLoose(text)); },
    parseReader: function (text) { return _wrapJSON(_jsonParseLoose(text)); }
};

_install('com.alibaba.fastjson', 'JSON', FastjsonJSON);
_install('com.alibaba.fastjson', 'JSONObject', FastjsonJSONObject);
_install('com.alibaba.fastjson', 'JSONArray', FastjsonJSONArray);
_install('com.google.gson', 'Gson', Gson);
_install('com.google.gson', 'GsonBuilder', GsonBuilder);
_install('com.google.gson', 'JsonParser', JsonParser);
_install('com.google.gson', 'JsonObject', FastjsonJSONObject);
_install('com.google.gson', 'JsonArray', FastjsonJSONArray);

_install('com.jayway.jsonpath', 'JsonPath', JaywayJsonPath);
_install('com.jayway.jsonpath', 'Configuration', JsonPathConfiguration);
_install('com.jayway.jsonpath', 'Option', JsonPathOption);

_install('io.legado.app.help.http', 'StrResponse', StrResponse);
_install('okhttp3', 'OkHttpClient', OkHttpClient);
_install('okhttp3', 'MediaType', MediaType);
_install('okhttp3', 'RequestBody', RequestBody);
_install('okhttp3', 'Request', { Builder: RequestBuilder });
_install('okhttp3', 'Response', OkHttpResponse);
_install('okhttp3', 'Headers', OkHttpHeaders);

// org.jsoup / org.seimicrawler 由 jsoup_bridge.js 填充（保持命名空间存在）
if (!Packages.org) { Packages.org = {}; }
if (!Packages.org.jsoup) { Packages.org.jsoup = {}; }
if (!Packages.org.seimicrawler) { Packages.org.seimicrawler = {}; }
if (!Packages.org.seimicrawler.xpath) { Packages.org.seimicrawler.xpath = {}; }

// 全局别名（Rhino importPackage 的近似）
var globalAliases = {
    ArrayList: ArrayList, LinkedList: ArrayList, LinkedHashMap: LinkedHashMap, HashMap: HashMap,
    Arrays: JavaArrays, Collections: JavaCollections, Base64: JavaBase64, UUID: JavaUUID,
    Pattern: JavaPattern, Matcher: JavaMatcher, BigInteger: BigInteger, ByteBuffer: JavaByteBuffer,
    URL: JavaURL, URI: JavaURI, URLEncoder: JavaURLEncoder, URLDecoder: JavaURLDecoder,
    Cipher: JavaCipher, SecretKeyFactory: SecretKeyFactory, KeyGenerator: KeyGenerator,
    SecretKeySpec: SecretKeySpec, IvParameterSpec: IvParameterSpec, DESKeySpec: DESKeySpec,
    MessageDigest: MessageDigest, KeyFactory: KeyFactory, Signature: Signature, Mac: Mac,
    SecureRandom: SecureRandom, PKCS8EncodedKeySpec: PKCS8EncodedKeySpec, X509EncodedKeySpec: X509EncodedKeySpec,
    ByteArrayInputStream: ByteArrayInputStream, ByteArrayOutputStream: ByteArrayOutputStream,
    BufferedInputStream: BufferedInputStream, InputStreamReader: InputStreamReader,
    GZIPInputStream: JavaGZIPInputStream, StringBuilder: JavaStringBuilder, StringBuffer: JavaStringBuffer,
    Thread: JavaThread, System: JavaSystem, Math: JavaMath,
    StrUtil: HutoolStrUtil, ZipUtil: HutoolZipUtil, DigestUtil: HutoolDigestUtil,
    JsonPath: JaywayJsonPath, StrResponse: StrResponse,
    JSON: FastjsonJSON, JSONObject: FastjsonJSONObject, JSONArray: FastjsonJSONArray,
    Gson: Gson, GsonBuilder: GsonBuilder, JsonParser: JsonParser,
    OkHttpClient: OkHttpClient, Request: { Builder: RequestBuilder }, RequestBody: RequestBody, MediaType: MediaType
};
for (var aliasName in globalAliases) {
    if (Object.prototype.hasOwnProperty.call(globalAliases, aliasName) && global[aliasName] === undefined) {
        global[aliasName] = globalAliases[aliasName];
    }
}

// with(JavaImporter(...)) 常见包里类的类名已在 package 对象上；这里确保 `android`/`javax` 等可直接访问
global.android = global.android || _package('android');
global.javax = global.javax || _package('javax');
global.cn = global.cn || _package('cn');
global.okhttp3 = global.okhttp3 || _package('okhttp3');
global.com = global.com || _package('com');
global.io = global.io || _package('io');
global.org = global.org || _package('org');

// 供诊断使用
global.__zhijianPackagesStubInfo = {
    version: '2.0-engine',
    classes: ['javax.crypto.Cipher', 'java.security.MessageDigest', 'java.util.ArrayList', 'com.jayway.jsonpath.JsonPath', 'okhttp3.OkHttpClient', 'com.alibaba.fastjson.JSON', 'com.google.gson.Gson']
};

})(this);
