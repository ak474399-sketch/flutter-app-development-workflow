# AI 订阅类与广告变现应用开发 Skill

从已有 APK、逆向报告及开发记录出发，指导 AI agent 分阶段制作 AI 订阅类或广告变现的 Flutter 应用。案例按类别转述，不披露源项目名称、目录或品牌。首次调用直接说明十阶段、准备材料、产物和验收；每大阶段先对齐标准，用户验收产物后进入依赖阶段。默认 Firebase Analytics、Crashlytics、Remote Config 和 Meta App Events；订阅和 IAA 可选。

Skill：`skills/flutter-app-development-workflow/SKILL.md`。包含阶段引导、验收／页面／素材模板、只读检查器、15条类别化经验与用户决定，以及387份匿名开发记录指纹。

运行代码位于 skill 自带 `assets/sdk`：基础 SDK、可选广告库存与真实 Google 适配、可选购买／恢复与订阅页、标明模拟的共同示例。配置和业务后端由每个产品独立准备。当前 Android-first；不是已经真实收费或上线的应用工厂。

## 使用

克隆此私有仓库后，将 `skills/flutter-app-development-workflow` 复制到 `~/.codex/skills/`，或使用支持 GitHub 子目录的 skill-installer。私有仓库需要调用者自身访问权限；不要把 GitHub token 写进 skill。调用：

```text
$flutter-app-development-workflow
读取我的 APK／逆向资料与当前开发记录，告诉我目前处于哪个阶段、需要准备什么，再逐阶段引导开发和验收。
```

已有项目从当前有效阶段续办；不会强制重做已验阶段。模板里 approval 默认为空，不自动替用户验收。

## 验证和限制

见 `VALIDATION.json` 与 skill `references/validation.md`。流程／素材和三个 SDK 共50项自动检查；21个隔离阶段记录用例复验符合预期。独立agent执行8个引导场景，并以新agent复验一处阶段措辞修订，归档输入与答复转述见 `references/evaluations/20261010/report.md`。这些是有限范围验证；真实业务验收、第三方后台接收、商店支付／权益、广告归因仍须当前产品验证。示例不能证明真实收费或广告投放。

各 SDK 的 `INTEGRATION.md` 给出路径依赖、配置与宿主职责；只引入所选商业化包。源码包含依赖锁，没有正式配置、旧项目广告单元、生产密钥或用户设备数据。

## 对外介绍

这是一套给 AI agent 使用的商业化应用开发 skill，适合已有参考 APK、逆向报告或开发资料，希望制作 AI 订阅类或广告变现产品的人。调用后先说明阶段、准备材料、交付物和验收办法，再根据当前进度提出关键问题；已有明确决定直接复用。

流程覆盖资料核对、页面与交互、image 设计、Flutter UI、本地功能、后端、AI 服务、SDK 与商业化、整体验收和发布交付。每个大阶段先明确范围和标准，实际产物经用户验收后再进入依赖阶段。

提供可复用订阅和广告 SDK：订阅含购买、恢复、权益验证调用及订阅页交互；广告含请求、缓存、过期、互斥展示、失败放行和奖励回调。两者独立可选。Firebase Analytics、Crashlytics、Remote Config 和 Facebook App Events 为默认必选模块；各产品独立准备配置和采集同意规则。

页面先用 icon 占位，再替换独立 image 素材；交付包含 banner、logo、真实 UI 上线图、源码、配置模板、版本包与验证记录。当前 Android-first，真实后端、商店交易和设备验收仍需按产品完成。
