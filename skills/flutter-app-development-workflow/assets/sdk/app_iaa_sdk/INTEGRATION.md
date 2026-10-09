# 可选 IAA SDK 0.1.0

包含真实 Google Mobile Ads 适配器及独立可测试库存层：开屏、插页、Banner、原生模板、激励；收入回调保留 micros／币种／精度。默认每池 ready＋pending≤2、全部插页≤4、加载并发≤4、55 分钟到期。未选择或未获得允许请求的同意时不初始化。

复制到 `packages/app_iaa_sdk`，通过 path dependency 引用。应用按官方要求设置本产品 AdMob App ID；调试仅用官方测试单元，正式配置不能出现在模拟示例中。广告同意与 UMP 由宿主准备；非个性化请求不能替代同意判断。

```dart
late AdInventory inventory;
final backend = GoogleAdBackend(
  onExternal: () => inventory.markExternalAdNavigation(),
  onIncome: (pool, income) {
    // income.micros / 1000000 is the SDK-reported amount.
    // Send only approved, deduplicated income events to the growth adapter.
  },
);
inventory = AdInventory(
  backend: backend,
  selected: projectUsesAds, // immutable local capability selection
  pools: [
    AdPool('inter_0', AdKind.interstitial, projectInterstitialUnits0),
    AdPool('inter_1', AdKind.interstitial, projectInterstitialUnits1),
  ],
);
await inventory.activate(enabled: projectAdsEnabled, consent: consentAllowsAdRequests);
final result = await inventory.show('inter_0', isCurrent: () => mounted && stillAtTheApprovedOpportunity);
// Unavailable/failed: continue the original business flow. Never auto-show a refill.
```

页面触发／频率由项目确认；SDK 不统计英语业务点击。开屏使用 `startup`，预算默认10秒；宿主先调用 activate，初始化与启动等待应共用同一10秒预算（同时启动两者，禁止先等待初始化再额外等待10秒）。插页回退需项目明示策略。后台设 `foreground=false`；真正回前台调用 `resumeOpportunity()` 并由宿主决定是否进入启动流程。外跳回前台会抑制重复机会。

Banner／原生通过 `lease(pool)` 取得唯一租约，再放入 `LeasedAdSlot`；该组件销毁／替换时释放。宿主将它放在业务控件之外、保证分区与间距；键盘或后台到来时移除组件。高度／宽度按实际格式核验；默认 banner 为320×50，可注入自适应尺寸；原生使用官方 medium template，也可注入已验收样式。原生真实触摸边界仍需真机验收，ClipRect 本身不等于已验证原生触摸隔离。

激励 `show(rewardNonce: preparedServerNonce)` 设置 SSV custom_data。`earned` 仅表示 SDK 回调，绝不发会员／聊天次数；领取仍要服务器真实 SSV 验证及幂等回执。收入回调也不是结算到账。

关闭：`activate(enabled:false, consent:false)` 释放 ready／租用并使旧代次失效；`close()` 终止此库存。底层全屏加载不支持取消：25秒后结果失效，但并发槽位保留到原始请求回调，迟到对象立即释放。可能暂时没有库存，不通过反复发新请求突破并发上限。已显示的全屏广告由 SDK 正常结束；全屏互斥不靠任意超时强行解锁。

依赖锁和本包测试记录随源码交付。当前 Android 编译与替代适配器测试不证明真实填充、平台后台刷新、SSV、收入接收或归因。官方依据：[Google Mobile Ads](https://developers.google.com/admob/flutter/quick-start)。
