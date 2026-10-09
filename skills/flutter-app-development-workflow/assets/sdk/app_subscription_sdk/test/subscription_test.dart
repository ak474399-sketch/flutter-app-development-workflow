import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_subscription_sdk/app_subscription_sdk.dart';

class Store implements StoreClient {
  final events = StreamController<List<StoreUpdate>>.broadcast(sync: true);
  int buys = 0, completes = 0, restores = 0;
  bool failComplete = false;
  @override
  Stream<List<StoreUpdate>> get updates => events.stream;
  @override
  Future<bool> available() async => true;
  @override
  Future<StoreCatalog> query(Set<String> ids) async => StoreCatalog([
    const StoreProduct(
      id: 'p',
      title: '套餐',
      price: '测试价格',
      currency: 'TEST',
      amount: 0,
    ),
  ], {});
  @override
  Future<bool> buy(String id) async {
    buys++;
    return true;
  }

  @override
  Future<void> restore() async {
    restores++;
    events.add([
      const StoreUpdate(
        productId: 'p',
        purchaseId: 'tx',
        state: PurchaseState.restored,
        needsCompletion: true,
      ),
    ]);
  }

  @override
  Future<void> complete(StoreUpdate update) async {
    completes++;
    if (failComplete) throw StateError('failure');
  }

  void emit(PurchaseState state, {String product = 'p'}) => events.add([
    StoreUpdate(
      productId: product,
      purchaseId: 'tx',
      state: state,
      needsCompletion: true,
    ),
  ]);
}

class Verifier implements EntitlementVerifier {
  int calls = 0;
  bool active = true, fail = false;
  Completer<VerifiedEntitlement>? pending;
  @override
  Future<VerifiedEntitlement> verifyAndApply(StoreUpdate update) async {
    calls++;
    if (fail) throw StateError('verification unavailable');
    return pending?.future ??
        VerifiedEntitlement(active: active, transactionId: 'canonical_tx');
  }
}

void main() {
  late Store store;
  late Verifier verifier;
  late SubscriptionController c;
  int reports = 0;
  setUp(() {
    reports = 0;
    store = Store();
    verifier = Verifier();
    c = SubscriptionController(
      store: store,
      verifier: verifier,
      productIds: {'p'},
      onVerified: (_, __) => reports++,
    );
  });
  tearDown(() async {
    c.dispose();
    await store.events.close();
  });
  test('pending canceled and error never grant or acknowledge', () async {
    await c.start();
    for (final s in [
      PurchaseState.pending,
      PurchaseState.canceled,
      PurchaseState.error,
    ]) {
      store.emit(s);
      await c.drain();
    }
    expect(verifier.calls, 0);
    expect(c.successRevision, 0);
    expect(store.completes, 0);
  });
  test(
    'purchase duplicate callbacks report once after verification and acknowledgement',
    () async {
      await c.start();
      await c.purchase('p');
      await c.purchase('p');
      expect(store.buys, 1);
      store.emit(PurchaseState.purchased);
      store.emit(PurchaseState.purchased);
      await c.drain();
      expect(c.state, SubscriptionState.active);
      expect(reports, 1);
      expect(store.completes, 2);
    },
  );
  test(
    'invalid rights or verification outage do not acknowledge, retry is possible',
    () async {
      await c.start();
      verifier.fail = true;
      store.emit(PurchaseState.purchased);
      await c.drain();
      expect(c.state, SubscriptionState.failed);
      expect(store.completes, 0);
      verifier.fail = false;
      await c.retryVerification();
      expect(c.state, SubscriptionState.active);
      expect(reports, 1);
    },
  );
  test('inactive rights and unrelated products cannot activate', () async {
    await c.start();
    store.emit(PurchaseState.purchased, product: 'other');
    await c.drain();
    expect(verifier.calls, 0);
    verifier.active = false;
    store.emit(PurchaseState.purchased);
    await c.drain();
    expect(c.successRevision, 0);
    expect(store.completes, 0);
  });
  test('restore verifies instead of granting locally', () async {
    await c.start();
    await c.restore();
    await c.drain();
    expect(verifier.calls, 1);
    expect(c.state, SubscriptionState.active);
    expect(c.successRevision, 1);
  });
  test('store acknowledgement failure retained for retry', () async {
    await c.start();
    store.failComplete = true;
    store.emit(PurchaseState.purchased);
    await c.drain();
    expect(c.successRevision, 0);
    store.failComplete = false;
    await c.retryVerification();
    expect(c.successRevision, 1);
    expect(reports, 1);
  });
  test('disposed controller ignores late verification', () async {
    await c.start();
    verifier.pending = Completer<VerifiedEntitlement>();
    store.emit(PurchaseState.purchased);
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    verifier.pending!.complete(
      const VerifiedEntitlement(active: true, transactionId: 'tx'),
    );
    await c.drain();
    expect(reports, 0);
  });
  Widget page({VoidCallback? close, VoidCallback? success}) => MaterialApp(
    home: SubscriptionPaywall(
      controller: c,
      hero: const ColoredBox(color: Colors.black),
      title: '订阅',
      purchaseLabel: '购买',
      restoreLabel: '恢复',
      closeLabel: '关闭',
      planLabel: (p) => p.title,
      status: (s) => Text(s.name),
      legalLinks: [const Text('条款')],
      onClose: close ?? () {},
      onSuccess: success ?? () {},
    ),
  );
  testWidgets(
    'close unavailable before 2000ms and visible at boundary, rebuild does not reset',
    (tester) async {
      await c.start();
      int closes = 0;
      await tester.pumpWidget(page(close: () => closes++));
      await tester.pump(const Duration(milliseconds: 1999));
      expect(find.byKey(const ValueKey('subscription_close')), findsNothing);
      await tester.pumpWidget(page(close: () => closes++));
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byKey(const ValueKey('subscription_close')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('subscription_close')));
      await tester.tap(find.byKey(const ValueKey('subscription_close')));
      expect(closes, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'verified purchase auto closes once even before close timer, pending does not',
    (tester) async {
      await tester.runAsync(() => c.start());
      int success = 0;
      await tester.pumpWidget(page(success: () => success++));
      await tester.runAsync(() async {
        store.emit(PurchaseState.pending);
        await c.drain();
      });
      await tester.pump();
      expect(success, 0);
      await tester.runAsync(() async {
        store.emit(PurchaseState.purchased);
        await c.drain();
      });
      await tester.pump();
      expect(success, 1);
      await tester.runAsync(() async {
        store.emit(PurchaseState.purchased);
        await c.drain();
      });
      await tester.pump();
      expect(success, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'verified restore also closes, destroyed page never closes a new route',
    (tester) async {
      await tester.runAsync(() => c.start());
      int success = 0;
      await tester.pumpWidget(page(success: () => success++));
      await tester.runAsync(() => c.restore());
      await tester.pump();
      expect(success, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        store.emit(PurchaseState.purchased);
        await c.drain();
      });
      await tester.pump();
      expect(success, 1);
    },
  );
  testWidgets('small screen large text and RTL do not overflow', (
    tester,
  ) async {
    await tester.runAsync(() => c.start());
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(1.8),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: (page() as MaterialApp).home!,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
