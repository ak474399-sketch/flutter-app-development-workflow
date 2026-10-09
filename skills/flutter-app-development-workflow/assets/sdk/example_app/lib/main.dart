import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app_subscription_sdk/app_subscription_sdk.dart';
import 'package:app_iaa_sdk/app_iaa_sdk.dart';

void main() => runApp(const DemoApp());

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: ThemeData(colorSchemeSeed: Colors.blue),
    home: const DemoHome(),
  );
}

class DemoHome extends StatefulWidget {
  const DemoHome({super.key});
  @override
  State<DemoHome> createState() => _DemoHomeState();
}

class _DemoHomeState extends State<DemoHome> {
  final store = DemoStore();
  late final SubscriptionController subscription;
  late final AdInventory ads;
  String result = '所有操作均为模拟；不调用真实购买、广告或归因服务。';
  @override
  void initState() {
    super.initState();
    subscription = SubscriptionController(
      store: store,
      verifier: DemoVerifier(),
      productIds: {'demo_plan'},
    );
    ads = AdInventory(
      backend: DemoAdBackend(),
      selected: true,
      pools: [
        AdPool('interstitial', AdKind.interstitial, ['demo_only']),
      ],
    );
    unawaited(subscription.start());
    unawaited(ads.activate(enabled: true, consent: true));
  }

  @override
  void dispose() {
    subscription.dispose();
    unawaited(store.events.close());
    unawaited(ads.close());
    super.dispose();
  }

  void openPaywall() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (pageContext) => SubscriptionPaywall(
          controller: subscription,
          hero: const ColoredBox(
            color: Colors.black87,
            child: Center(
              child: Text('模拟主视觉', style: TextStyle(color: Colors.white)),
            ),
          ),
          title: '订阅交互演示（不收费）',
          purchaseLabel: '模拟购买',
          restoreLabel: '模拟恢复',
          closeLabel: '关闭',
          planLabel: (p) => p.title,
          status: (s) => Text('模拟状态：${s.name}'),
          legalLinks: [const Text('正式接入需配置本产品条款和隐私链接')],
          onClose: () => Navigator.of(pageContext).pop(),
          onSuccess: () => Navigator.of(pageContext).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SDK 模拟演示／不收费')),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(result),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: openPaywall,
            child: const Text('查看订阅页与 2 秒关闭按钮'),
          ),
          OutlinedButton(
            onPressed: () async {
              final value = await ads.show(
                'interstitial',
                isCurrent: () => mounted,
              );
              if (mounted) {
                setState(
                  () => result =
                      '模拟广告结果：${value.status.name}；缓存补请求后 ${ads.count('interstitial')} 条',
                );
              }
            },
            child: const Text('模拟消耗共享广告库存'),
          ),
        ],
      ),
    ),
  );
}

// These classes exist ONLY in this labeled demo and must never grant production rights.
class DemoStore implements StoreClient {
  final events = StreamController<List<StoreUpdate>>.broadcast();
  int serial = 0;
  @override
  Stream<List<StoreUpdate>> get updates => events.stream;
  @override
  Future<bool> available() async => true;
  @override
  Future<StoreCatalog> query(Set<String> ids) async => StoreCatalog([
    const StoreProduct(
      id: 'demo_plan',
      title: '模拟套餐',
      price: '模拟价格，无扣款',
      currency: 'DEMO',
      amount: 0,
    ),
  ], {});
  @override
  Future<bool> buy(String id) async {
    events.add([
      StoreUpdate(
        productId: id,
        purchaseId: 'demo_${++serial}',
        state: PurchaseState.purchased,
      ),
    ]);
    return true;
  }

  @override
  Future<void> restore() async {
    events.add([
      const StoreUpdate(
        productId: 'demo_plan',
        purchaseId: 'demo_restored',
        state: PurchaseState.restored,
      ),
    ]);
  }

  @override
  Future<void> complete(StoreUpdate update) async {}
}

class DemoVerifier implements EntitlementVerifier {
  @override
  Future<VerifiedEntitlement> verifyAndApply(StoreUpdate update) async =>
      VerifiedEntitlement(active: true, transactionId: update.purchaseId!);
}

class DemoAdBackend implements AdBackend {
  @override
  Future<void> initialize() async {}
  @override
  Future<AdHandle> load(AdPool pool, int slot) async => DemoAd(pool.kind);
}

class DemoAd implements AdHandle {
  @override
  final AdKind kind;
  DemoAd(this.kind);
  @override
  Widget? get view => null;
  @override
  Future<AdResult> show({String? rewardNonce}) async =>
      const AdResult(AdStatus.dismissed);
  @override
  Future<void> dispose() async {}
}
