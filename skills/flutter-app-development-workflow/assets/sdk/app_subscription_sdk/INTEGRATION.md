# 可选订阅 SDK 0.1.0

包含真实 `in_app_purchase` 客户端适配、应用级购买监听／恢复／验证／确认状态机、HTTPS 权益验证适配器及默认订阅页。默认关闭按钮首个可见帧后2秒出现；已验证、权益生效且完成所需商店确认后，购买或恢复均通知页面关闭一次。pending／失败／取消不会触发成功关闭。

```yaml
dependencies:
  app_subscription_sdk:
    path: packages/app_subscription_sdk
```

```dart
final verifier = HttpEntitlementVerifier(
  endpoint: projectVerificationEndpoint, // HTTPS, configured for this product
  accessToken: obtainCurrentProductAccessToken,
);
final controller = SubscriptionController(
  store: InAppPurchaseClient(),
  verifier: verifier,
  productIds: projectSubscriptionProductIds,
  onVerified: (canonicalTransactionId, update) {
    // Entitlements already committed by backend. Refresh application rights.
    // Purchase events: only a new confirmed purchase, not a restore or renewal guess.
  },
);
await controller.start(); // app startup; do not wait until the paywall route opens
```

Controller 保持应用级生命周期。订阅页销毁仅移除 UI 监听，不停止购买流，离页后的交易仍需处理；退出应用组件时 dispose。商品显示商店查询的本地价格，不硬编码地区价、币种或默认试用。查询未找到商品、不可购买和验证失败时由宿主传入明确且本地化的状态组件。

`SubscriptionPaywall` 需要已验收的 hero、标题、计划说明、购买／恢复／关闭文案、实际法律链接、onClose 和 onSuccess 路由回调。上方主视觉、左关闭右恢复、下方可滚动套餐／购买区；套餐互斥、48dp关闭触控、品牌取宿主 Theme。入口不同的返回路径由宿主给出，模块不硬编码旧路由。它不控制系统返回；减少动画、视频授权及静态回退由宿主 hero 组件负责。

后端合同：认证请求包含 `productId/purchaseId/source/proof/restored`；响应 `{"active": true, "transactionId": "canonical store identity"}`。必须先用官方商店接口验证应用、商品、交易状态、身份绑定、到期／撤销，再原子性幂等保存权益；返回 active 不得仅依据客户端传来的 true。此 SDK 提供调用合同，**不提供任何伪造验证后端，也未完成各产品真实后端与商品配置**。purchaseId 不作为跨平台唯一数据库键，后端确定规范交易身份，Android 使用可信 purchaseToken 等实际来源。

商店确认失败／网络验证失败保留待重试证明；`retryVerification()` 重试。内存状态不作最终权益源，重启从商店流与后端恢复；退款、过期、续订由后端的实时通知／查询更新权限，宿主应在前台恢复时取得当前权益快照。商品升级／降级、复杂优惠选择和账户绑定参数不包含在首版通用 buy 调用中，选用时补平台适配与独立验收。

测试位于 test；共同示例在 `../example_app`，所有模拟实现仅在明确标注的示例和测试中。正式代码不存在本地赠送会员的默认验证器。Android-first：Flutter 购买插件提供其它平台接口，但本轮没有 iOS 编译或商店测试。

官方依据：[Flutter IAP](https://pub.dev/packages/in_app_purchase)、[Google 验证与确认](https://developer.android.com/google/play/billing/security)、[subscriptionsv2.get](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptionsv2/get)。
