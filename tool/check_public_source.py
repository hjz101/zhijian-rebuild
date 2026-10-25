#!/usr/bin/env python3
"""开源边界检查：扫描跟踪树，禁止敏感内容混入。

检查项：
1. 个人路径（/Users/<user>/...）与主目录引用
2. 硬编码密钥/Token（关键词 + 常见格式）
3. 逆向报告路径引用（file:///Users/... / Documents/deepseek-harness）
4. 明确排除文件（dist/、*.bundle、*.ipa、*.xcarchive、shots/）
5. 文档中的栖阅报告路径引用
退出码：0 通过，1 有违规。
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# 只扫描 git 跟踪的文件（跳过 .git 与构建产物）
def tracked_files():
    try:
        out = os.popen(f"cd {ROOT} && git ls-files").read().splitlines()
        return [f for f in out if f]
    except Exception:
        return []

BANNED_PATTERNS = [
    re.compile(r"/Users/[A-Za-z0-9_.-]+/"),
    re.compile(r"file:///Users/"),
    re.compile(r"Documents/deepseek-harness"),
    re.compile(r"qireader/raw/Payload"),
    re.compile(r"\b(sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,})\b"),
]
BANNED_EXT = (".ipa", ".bundle", ".xcarchive", ".dylib", ".mobileprovision", ".p12", ".cer", ".key")
BANNED_DIRS = ("dist/", "shots/", "build/", "DerivedData/", "xcuserdata/")
BANNED_FILES = {".env", "secrets.json", "credentials.json"}

def main():
    violations = []
    for rel in tracked_files():
        if rel.startswith(BANNED_DIRS) or rel in BANNED_FILES or rel.endswith(BANNED_EXT):
            violations.append(f"[file] {rel}")
            continue
        path = os.path.join(ROOT, rel)
        if not os.path.isfile(path):
            continue
        try:
            with open(path, "r", encoding="utf-8", errors="ignore") as fh:
                content = fh.read()
        except Exception:
            continue
        for pat in BANNED_PATTERNS:
            m = pat.search(content)
            if m:
                # 显示所在行
                line_no = content[:m.start()].count("\n") + 1
                violations.append(f"[pattern] {rel}:{line_no} {pat.pattern}")
                break
    if violations:
        print("开源边界检查失败：")
        for v in violations[:50]:
            print("  ", v)
        print(f"共 {len(violations)} 处违规")
        sys.exit(1)
    print("开源边界检查通过 ✅（无个人路径/密钥/逆向报告引用）")

if __name__ == "__main__":
    main()
