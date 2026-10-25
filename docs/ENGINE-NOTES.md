# 书源引擎 / Java 兼容层说明（ENGINE-NOTES）

> 分线：engine（task-4）。写入范围：`Zhijian/Core/{Runtime,Rules,Parsing,Pipeline}`、
> `Zhijian/Resources/{packages_stub.js,jsoup_bridge.js}`、本文件。
> 构建：`xcodebuild -project Zhijian.xcodeproj -scheme Zhijian -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/zj-engine build`（BUILD SUCCEEDED）。

## 1. 新增文件

| 文件 | 作用 |
|---|---|
| `Zhijian/Core/Runtime/CodecSupport.swift` | 原生算法底座：字符集/Base64/Hex、MD5/SHA1/224/256/384/512、HMAC、AES/DES/3DES（ECB/CBC/CTR/CFB/OFB + PKCS5/7/NoPadding）、GZIP、RSA（PKCS#1/PKCS#8/X.509 DER 解析 + 签名/验签）。只用 CommonCrypto/CryptoKit/Compression/Security。 |
| `Zhijian/Core/Runtime/JSRuntime+Native.swift` | 注册 JavaScriptCore 全局 `_native*` 函数（见 §3）。 |
| `Zhijian/Core/Runtime/JSRuntime+JavaCompat.swift` | 扩充 `java.*`（见 §4）、`source.loginCheckJs` 执行器、文件缓存系统。 |
| `Zhijian/Core/Runtime/JSRuntime+Jsoup.swift` | `JsoupDOMStore` + 约 30 个 `_jsoup*` 原生函数（handle 代理）。 |
| `Zhijian/Resources/packages_stub.js` | 自写 Rhino/Java 兼容层（`Packages`、`javax.crypto`、`java.security`、`java.util`…）。 |
| `Zhijian/Resources/jsoup_bridge.js` | `org.jsoup.Jsoup/Connection/Document/Element/Elements`、`JXDocument/JXNode` 绑定。 |

`JSRuntime.installAPIs` 会依次注入 native 全局 → `_jsoup*` → `packages_stub.js` → `jsoup_bridge.js`（Bundle 资源，进程内缓存）。注入失败记录在 `JSRuntime.compatibilityLayerError`，不会崩溃。

## 2. JS 兼容层 API（packages_stub.js）

全局：`String.prototype.getBytes/isEmpty/contains/equals/equalsIgnoreCase/replaceAll/replaceFirst/matches/string/bytes`、
`JavaImporter(...)`、`importPackage()`、`importClass()`、`Packages`、`java.<pkg>` 命名空间、常用类全局别名
（`ArrayList/Cipher/MessageDigest/Pattern/URL/...`）。

| 包 | 类 |
|---|---|
| `java.lang` | String、Integer、Long、Double、Boolean、Math、System、Thread（sleep 上限 2s）、StringBuilder/StringBuffer、Exception/RuntimeException |
| `java.util` | ArrayList/LinkedList、HashMap/LinkedHashMap、HashSet、Arrays、Collections、Base64、UUID、TimeUnit、regex.Pattern/Matcher、zip.GZIPInputStream |
| `java.io` | ByteArrayInputStream/OutputStream、BufferedInputStream、InputStreamReader、IOException |
| `java.net` | URL、URI、URLEncoder、URLDecoder |
| `java.nio` / `java.math` | ByteBuffer、BigInteger（内部 BigInt，支持 add/subtract/multiply/divide/mod/modPow/compareTo/toByteArray） |
| `javax.crypto` | Cipher（ENCRYPT_MODE=1/DECRYPT_MODE=2，doFinal/update/getIV）、SecretKeyFactory、KeyGenerator、Mac、spec.SecretKeySpec/IvParameterSpec/DESKeySpec |
| `java.security` | MessageDigest、KeyFactory、Signature（RSA SHA1/256/384/512，PKCS1v1.5 或 PSS）、SecureRandom、spec.PKCS8/X509/RSAPrivateKeySpec |
| `android.*` | util.Base64（DEFAULT/NO_PADDING/NO_WRAP/CRLF/URL_SAFE）、text.TextUtils、graphics.BitmapFactory（恒 null） |
| `cn.hutool.*` | core.codec.Base64、core.util.StrUtil/ZipUtil（gzip/unGzip）、crypto.digest.DigestUtil |
| `com.jayway.jsonpath` | JsonPath（`read`、`using(config).parse(...).read`、`compile`）、Configuration、Option（SUPPRESS_EXCEPTIONS） |
| `okhttp3` | OkHttpClient、Request.Builder、RequestBody、MediaType、Response、Headers（execute 走 native HTTP） |
| `io.legado.app.help.http` | StrResponse（url/body/code/message/headers） |

典型用法：

```js
// AES/CBC/PKCS5Padding（key/iv 按 UTF-8 字节）
var cipher = javax.crypto.Cipher.getInstance("AES/CBC/PKCS5Padding");
cipher.init(javax.crypto.Cipher.ENCRYPT_MODE,
            new javax.crypto.spec.SecretKeySpec(key, "AES"),
            new javax.crypto.spec.IvParameterSpec(iv));
var encrypted = cipher.doFinal("明文".getBytes("UTF-8"));

// Legado 兼容的便捷 API
var crypto = java.createSymmetricCrypto("AES/CBC/PKCS5Padding", key, iv);
var plain = crypto.decryptStr(encryptedBase64);
var md5 = java.digestHex("abc", "MD5");
var data = com.jayway.jsonpath.JsonPath.read(json, "$.data.list[*].name");

// DOM（native 持有 DOM，JS 只持 handle）
var doc = org.jsoup.Jsoup.parse(html, baseUrl);
var titles = doc.select("li.title").eachText();
var jx = org.seimicrawler.xpath.JXDocument.create(html);
var nodes = jx.selN("//li/a/@href");
```

## 3. Native 全局函数（JSContext）

| 函数 | 语义 |
|---|---|
| `_nativeStrToBytes(str, charset)` / `_nativeBytesToStr(bytes, charset)` | 字符串↔字节数组；支持 UTF-8/GBK/GB18030/Big5/UTF-16/ISO-8859-1/ASCII |
| `_nativeBase64Encode(bytes)` / `_nativeBase64DecodeToBytes(str)` | Base64（兼容 URL-safe 输入） |
| `_nativeCipherProcess(dataB64, keyB64, transformation, ivB64, isDecrypt)` | 对称加解密，返回密文/明文的 Base64 |
| `_nativeGzip(bytes)` / `_nativeGunzip(bytes)` | gzip（Compression 框架 + 自写 CRC32/头尾） |
| `_nativeJsonPathRead(json, path, suppress)` | JsonPath；`suppress=true` 时错误返回 null |
| `_nativeSleepMillis(ms)` | 阻塞 sleep（上限 2000ms，对齐 Legado） |
| `_nativeDigestBase64(bytes, algorithm)` / `_nativeHMacBase64(key, data, algorithm)` | 摘要/HMAC，返回 Base64 |
| `_nativeRandomUUID()` | 小写 UUID |

`_jsoup*`：`Parse/RootHandle/BodyHandle/HeadHandle/SelectHandles/XPathResults/DocumentText|Html|Title|BaseUri/
ChildrenHandles/ParentHandle/Next|PreviousSiblingHandle/NodeText|OwnText|TextNodes|Data|Html|OuterHtml|TagName|
Attr|HasAttr|HasClass|Attributes|AbsUrl/SetTagName|SetAttr|RemoveAttr|SetText|SetHtml/Empty|Remove|Before|After|
Append|Prepend/CloneHandle/ConnectFetch/ClearDomStore`。DOM store 每次 `Jsoup.parse` 生成独立文档（不走规则缓存），可变操作会刷新文档序。

## 4. java.* API（JSRuntime）

原有：`ajax/get/post/put/head/connect`、`base64Encode/Decode`、`md5Encode/md5Encode16`、`hexEncodeToString/hexDecodeToString`、
`timeFormat/timeFormatUTC/currentTime`、`log/toast/longToast`、`getCookie/setCookie/getCookieByKey/putCookie/removeCookie`、
`getString/getStringList/getElement/getElements/getList`、`getWebViewUA`、`put/delete`（缓存）。

新增：`base64DecodeToByteArray`、`hexDecodeToByteArray`、`digestHex`、`digestBase64Str`、`HMacHex/HMacBase64`、
`createSymmetricCrypto`、`encryptStr/decryptStr`、`aesEncodeToString/aesDecodeToString/aesBase64DecodeToString`、
`aesEncodeToBase64String/aesDecodeToByteArray`、`createSign(alg)`、`createAsymmetricCrypto` 缺失时抛诊断、
`strToBytes/bytesToStr`、`encodeURI/decodeURI(+WithCharset)`、`toURL`、`htmlFormat`、`strToInt`、`substring`、
`t2s/s2t`（恒等）、`randomUUID`、`androidId`、`ajaxAll`、`getTxtInUrl`、`cacheFile/downloadFile/getFile/readFile/
readTxtFile/deleteFile/getTxtInFolder`、`importScript`、`openUrl`（主线程系统浏览器）、`refreshExplore`（no-op）。

文件 API 限定在 `Library/Caches/zhijian-js/` 内（拒绝 `..`），与 Legado 的「私有缓存目录」语义一致。

**明确 unsupported（抛 `UnsupportedApi`，映射错误码 -10）**：`java.webView`、`webViewGetSource`、`webViewGetOverrideUrl`、
`startBrowser/startBrowserAwait`、`getVerificationCode`、`queryBase64TTF/queryTTF`。书源用到这些时会得到可读诊断，
而不是 `undefined is not a function`。

## 5. SourcePipeline

- **concurrentRate 限速**：`RateLimiter.Configuration.parse` 支持 Legado 语义：`""`→默认 1 req/s；`"0"`→不限速；
  `"1000"`→1 次/1s；`"3/1000"`→窗口 1s 内最多 3 次。`rateLimitDescription` 可展示解析结果。
- **loginCheckJs**：每次 HTTP 响应后执行（绑定 `result` 响应对象：`code()/body()/headers()/header(k)/url()/setBody()`；
  脚本可用 `return result`，会被 IIFE 包裹）。返回字符串或修改 `setBody` 可替换 body；抛错含「登录/login」→ `-12`
  需要登录，其它 JS 错误 → `-9`。
- **诊断暴露给 UI**：`lastHTTPStatus`、`lastHTTPResponse`、`lastResponseURL`、`lastContentType`、`jsLogs`、
  `compatibilityLayerError`、`diagnosticsSnapshot`（书源名 + 最近 HTTP + 限速 + 请求流水 + JS console）。
- **TOC 顺序归一化**：`toc()` 末尾调用 `normalizedTOC`。当 ≥80% 标题能解析出章号/卷号（`第N章/回/节/话/集/篇`、
  `第N卷/部`、`卷N`、中文数字、裸数字标题）时，按 `(卷号, 章号)` **稳定升序**排序；未编号条目沿用前一个章号并保持
  相邻；卷标题回到原插入位置；不足 80% 时保持服务端原顺序。支持 `第一千零一章`、`第123章` 等。
- `RuleContext.contentType` 现在由最近响应 Content-Type 注入（JSON/HTML 嗅探更稳）。

## 6. 规则引擎边界（RuleEngine）

- `@put:{k:rule}`：先求值再写变量；支持宽松 JSON（单引号/裸 key）。
- `@get:key` 与 `@get:{key}`：整条规则时直接返回变量值；`{{@get:{k}}}` 插值可用。
- `{{...}}`：内层是子规则（`@`/`$.`/`$[`/`//`/`#`）先求值，否则进 JS；`{{$.a || '兜底'}}` 支持 `||` 兜底。
- 规则链：HTML 内容上 `&&/||/%%` 各段独立求值再合并（Legado AnalyzeByJSoup 语义）；`<js>`/`@js:` 段顺序传递上一段结果。
- `##正则##替换` 替换全部；`##正则##替换###`（第 4 段存在）只替换第一个匹配（Legado `split("##")` 语义）。
- 索引：`[0]`、`[-1]`、`[0:5]`、`[1:10:2]`、`[!0]`、Legado 旧写法 `.0` / `!0`。
- `@webjs:`：当前明确抛 `规则错误：@webjs: 规则需要 WebView...`（不再静默空结果）。
- `@css:/@xpath:/@json:/@regex:`、`$N` 正则组、URL `{{}}` 模板、`URL,{json}` 选项保持原语义。

## 7. 测试

**自动化（iOS Simulator 命令行，59/59 通过）**：兼容层加载、String.getBytes、Base64、MD5/SHA-256、AES Cipher
往返（中文）、createSymmetricCrypto/encryptStr/decryptStr、GZIP、JsonPath read/using、Pattern/Matcher、ArrayList/
LinkedHashMap、URLEncoder/Decoder、BigInteger、Android Base64、hutool DigestUtil、okhttp Request、Jsoup parse/select/
DOM 写操作、JXDocument/XPath、java.getFile/toURL/randomUUID/webView unsupported；规则 CSS 链/索引/`##`/`###`/
`{{}}`/@put/@get/@webjs 诊断/URL 模板；loginCheckJs 三种返回；TOC 倒序、中文数字、卷标题、<80% 保持原序、数字解析。

**真实书源**：`demo-source-rulianshi.json`（关于小说）搜《剑来》→详情/目录 1320 章 → 首章正文分页链路已由 Lead
集成测试验证通过（TOC 顺序归一化生效）。

## 8. 已知缺口

- WebView 相关能力未实现（`@webjs`、`java.webView*`、验证码、startBrowser）——明确报错，不静默失败。
- fastjson/Gson 无存根（与 QiReader 一致）；少数书源会失败。Bundle 内 `dagray-5.0-compat.json` 主要用 CSS/{{}}，不依赖它们。
- ZIP/RAR/7z 文件解包未实现（只有 GZIP）；`getZipStringContent` 等暂无。
- `BitmapFactory` 恒 null；`Thread.sleep` 上限 2000ms；Java 正则的 `\Q…\E` 已支持，命名组依赖 JS RegExp；
  `UUID.nameUUIDFromBytes` 为 MD5 v3 近似。
- RSA 支持 SHA1/256/384/512（PKCS1v1.5/PSS）；`MD5withRSA` 因 Security 框架限制不支持。
- `BigInteger` 已用 BigInt（优于 QiReader 的 double 实现），但尚未覆盖所有 Java 方法。
- 未做 JSC 执行超时中断（书源死循环仍可能长时间占用 JS 队列）。
