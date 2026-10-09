# Flutter 应用开发流程 Skill

从已有 APK／逆向资料及真实开发记录出发，引导用户分阶段制作 Flutter 应用。首次调用直接说明十阶段、准备材料、产物和验收；每大阶段先对齐标准，用户验收产物后进入依赖阶段。默认 Firebase Analytics、Crashlytics、Remote Config 和 Meta App Events；订阅和 IAA 可选。

Skill：`skills/flutter-app-development-workflow/SKILL.md`。包含阶段引导、验收／页面／素材模板、只读检查器、15条经验来源及387份开发记录文件库存。

运行代码位于 skill 自带 `assets/sdk`：基础 SDK、可选广告库存与真实 Google 适配、可选购买／恢复与订阅页、标明模拟的共同示例。配置和业务后端由每个产品独立准备。当前 Android-first；不是已经真实收费或上线的应用工厂。

## 使用

克隆此私有仓库后，将 `skills/flutter-app-development-workflow` 复制到 `~/.codex/skills/`，或使用支持 GitHub 子目录的 skill-installer。私有仓库需要调用者自身访问权限；不要把 GitHub token 写进 skill。调用：

```text
$flutter-app-development-workflow
读取我的 APK／逆向资料与当前开发记录，告诉我目前处于哪个阶段、需要准备什么，再逐阶段引导开发和验收。
```

已有项目从当前有效阶段续办；不会强制重做已验阶段。模板里 approval 默认为空，不自动替用户验收。

## 验证和限制

见 `VALIDATION.json` 与 skill `references/validation.md`。流程／素材和三个 SDK 共50项自动检查；21个隔离阶段记录用例复验符合预期。独立agent执行8个引导场景，并以新agent复验一处阶段措辞修订，原始输入与答复见 `references/evaluations/20261010/report.md`。这些是有限范围验证；真实业务验收、第三方后台接收、商店支付／权益、广告归因仍须当前产品验证。示例不能证明真实收费或广告投放。

各 SDK 的 `INTEGRATION.md` 给出路径依赖、配置与宿主职责；只引入所选商业化包。源码包含依赖锁，没有正式配置、旧项目广告单元、生产密钥或用户设备数据。
