# 基础 SDK：必选 Firebase 与 Meta

## 组成与准备
`assets/sdk/app_growth_sdk` 是可复制或作为 Git/path 依赖使用的 Flutter 插件，Android 原生 Meta SDK + FlutterFire。Firebase三项和Meta为必选；不自动加入Firebase Auth、FCM、Firestore、Facebook Login或分享。

每个项目准备：
- 当前平台／环境／应用身份；Firebase注册应用、客户端配置、后台访问权限。
- Meta App ID、Client Token、平台注册信息及广告侧关联；独立测试接收范围。
- 事件表：来源、触发、参数、是否自动上报、金额和币种来源、接收平台、去重规则。
- 产品隐私／同意规则。SDK默认拒绝数据采集，明确设置Consent后才开；同时保持Meta自动事件/广告标识采集关闭的Manifest默认值。

底层来自官方 [FlutterFire](https://firebase.google.com/docs/flutter/setup) 与 [Meta Android SDK](https://github.com/facebook/facebook-android-sdk)。选定版本锁定验证，不用动态latest。配置文件和ID是各项目资料，不沿用历史实例。Meta App Secret和供应商／后台私钥不进客户端；Client Token仅用于官方客户端配置，不当作服务端私钥。

## 接入
复制包到应用 `packages/app_growth_sdk` 并用path dependency。按包根 INTEGRATION.md 设置Android Manifest、Firebase配置与启动。注入本项目FirebaseOptions或官方平台配置；不要复制旧项目google-services.json。初始化基础层后绑定同意状态和约定事件。

Remote Config有本地默认、类型校验、超时和失败保留前值；基础层只返回配置值，不直接控制广告。可选广告／订阅模块自己绑定允许的键，禁止越权重新启用未选功能。当前实现不提供实时更新监听，按需要明确接入。

Meta自动初始化／自动事件／广告标识采集默认关闭；同意后手动初始化和激活，logEvent显式映射。安装事件由原生SDK行为产生，不人为伪造install事件或承诺每次安装都有可用广告归因。金额事件由已确认交易／收入触发，自动和手工同事件选择一条路径，避免重复统计。

## 验收与缺口
分别记录：依赖编译、SDK初始化、Firebase DebugView事件、非致命测试错误入Crashlytics、远端已发布值取得、Meta后台测试事件、广告后台可核对的归因。SDK上报调用成功不等于后台收到或已归因。

基础单元测试用替代适配器与通道检查状态和事件，不替代真实配置／网络／控制台。未提供真实配置时真实接入验收待完成。首版Android Native Meta；其它平台调用会明确失败，不静默忽略。

元数据与行为可能被传到第三方。对话正文、照片、健康测量、凭证不进通用事件或异常信息；按约定只发非敏感业务标识。SDK内仅允许项目事先定义的参数，错误信息保留类型而非正文。不得将当前隐私同意推定为另一产品同意。

## 可选模块与示例
广告：`assets/sdk/app_iaa_sdk/INTEGRATION.md`。订阅：`assets/sdk/app_subscription_sdk/INTEGRATION.md`。共同宿主 `assets/sdk/example_app` 始终明确标注模拟，不做真实服务调用。只依赖被选用的商业包，未选包不因为“示例用了三个包”而强制带进新应用；必选基础层保持独立。测试／构建／真实配置验收分开记录。
