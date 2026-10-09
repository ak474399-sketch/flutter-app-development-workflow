# 无凭据模拟示例

本示例用于订阅页面／广告库存交互演示和 Android 原生依赖编译。页面标注模拟，不扣款，不请求真实广告，不发送 Firebase／Meta 事件，不连接验证服务器。模拟实现仅限此目录和测试；正式应用必须使用真实适配器及验证后端。

要求 Flutter 3.41.9 或经重新验证的兼容版本、JDK17+、Android SDK36+。默认国内 Flutter 包镜像沿用调用者环境，不修改全局配置。

```sh
flutter pub get
flutter analyze
flutter build apk --debug
```

运行应用涉及选择设备；没有设备授权时止于本地构建。所有 SDK path dependency 使用相邻目录，复制时保持结构。Android Manifest 中的 AdMob App ID 是 Google 官方示例 ID；切换真实模式前需建立本产品环境配置，避免修改示例后误称正式应用。
