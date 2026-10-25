# i18n 审计报告

> `-i18nAudit` 设计为扫描源文件；模拟器内无法访问源码，改用宿主机脚本。

共扫描 51 个 Feature/App 文件，发现未接入 `tr()` 的**单行短中文 UI 文案 1 处**（已排除已覆盖项）。

逐条迁移方式：把这些字符串改为 `LocalizationManager.tr("key")` 并在文案表补充中/英。

```
Zhijian/App/AppEnvironment.swift:1081: push=已执行
```
