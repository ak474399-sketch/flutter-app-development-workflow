import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_iaa_sdk/app_iaa_sdk.dart';

class Handle implements AdHandle {
  @override
  final AdKind kind;
  int disposed = 0, shown = 0;
  final Completer<AdResult>? result;
  Handle(this.kind, {this.result});
  @override
  Widget? get view => const SizedBox();
  @override
  Future<void> dispose() async {
    disposed++;
  }

  @override
  Future<AdResult> show({String? rewardNonce}) async {
    shown++;
    return result?.future ?? const AdResult(AdStatus.dismissed);
  }
}

class Backend implements AdBackend {
  int initialized = 0;
  final requests = <Completer<AdHandle>>[];
  final specs = <AdPool>[];
  @override
  Future<void> initialize() async {
    initialized++;
  }

  @override
  Future<AdHandle> load(AdPool pool, int slot) {
    final c = Completer<AdHandle>();
    requests.add(c);
    specs.add(pool);
    return c.future;
  }

  Handle finish(int index, {Completer<AdResult>? result}) {
    final h = Handle(specs[index].kind, result: result);
    requests[index].complete(h);
    return h;
  }
}

Future<void> turn() async {
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('unselected and denied modules never initialize or request', () async {
    final b = Backend();
    final a = AdInventory(
      backend: b,
      pools: [
        AdPool('i', AdKind.interstitial, ['TEST']),
      ],
    );
    await a.activate(enabled: true, consent: true);
    expect(b.initialized, 0);
    expect(b.requests, isEmpty);
    final denied = AdInventory(
      selected: true,
      backend: b,
      pools: [
        AdPool('denied', AdKind.interstitial, ['TEST']),
      ],
    );
    await denied.activate(enabled: true, consent: false);
    expect(b.initialized, 0);
    expect(b.requests, isEmpty);
    await denied.close();

    await a.close();
  });
  test('ready plus pending bounded and global concurrency four', () async {
    final b = Backend();
    final a = AdInventory(
      selected: true,
      backend: b,
      pools: [
        AdPool('a', AdKind.interstitial, ['TEST']),
        AdPool('b', AdKind.interstitial, ['TEST']),
        AdPool('c', AdKind.banner, ['TEST']),
      ],
    );
    await a.activate(enabled: true, consent: true);
    expect(a.activeRequests, 4);
    expect(a.pending('a'), 2);
    a.refill();
    expect(b.requests.length, 4);
    b.finish(0);
    await turn();
    expect(a.count('a') + a.pending('a'), 2);
    expect(a.activeRequests, 4);
    await a.close();
    for (var i = 1; i < b.requests.length; i++) {
      if (!b.requests[i].isCompleted) b.finish(i);
    }
    await turn();
  });
  test(
    'disabled late callbacks release and do not enter new inventory',
    () async {
      final b = Backend();
      final a = AdInventory(
        selected: true,
        backend: b,
        pools: [
          AdPool('i', AdKind.interstitial, ['TEST']),
        ],
      );
      await a.activate(enabled: true, consent: true);
      await a.activate(enabled: false, consent: true);
      final h = b.finish(0);
      b.finish(1);
      await turn();
      expect(a.count('i'), 0);
      expect(h.disposed, 1);
      await a.close();
    },
  );
  test(
    'expiry releases before acquisition and refills without auto-show',
    () async {
      var clock = Duration.zero;
      final b = Backend();
      final a = AdInventory(
        selected: true,
        backend: b,
        clock: () => clock,
        pools: [
          AdPool('i', AdKind.interstitial, ['TEST']),
        ],
      );
      await a.activate(enabled: true, consent: true);
      final h = b.finish(0);
      b.finish(1);
      await turn();
      clock = const Duration(minutes: 55);
      final r = await a.show('i', isCurrent: () => true);
      expect(r.status, AdStatus.unavailable);
      await turn();
      expect(h.disposed, 1);
      expect(h.shown, 0);
      await a.close();
      for (var i = 2; i < b.requests.length; i++) {
        b.finish(i);
      }
      await turn();
    },
  );
  test(
    'fullscreen mutex and stale opportunity do not consume inventory',
    () async {
      final b = Backend();
      final a = AdInventory(
        selected: true,
        backend: b,
        pools: [
          AdPool('i', AdKind.interstitial, ['TEST']),
        ],
      );
      await a.activate(enabled: true, consent: true);
      final completion = Completer<AdResult>();
      b.finish(0, result: completion);
      b.finish(1);
      await turn();
      expect(
        (await a.show('i', isCurrent: () => false)).status,
        AdStatus.stale,
      );
      final shown = a.show('i', isCurrent: () => true);
      expect((await a.show('i', isCurrent: () => true)).status, AdStatus.busy);
      completion.complete(const AdResult(AdStatus.dismissed, earned: false));
      expect((await shown).earned, false);
      await a.close();
      for (var i = 2; i < b.requests.length; i++) {
        b.finish(i);
      }
      await turn();
    },
  );
  test('inline leases unique and release exactly once', () async {
    final b = Backend();
    final a = AdInventory(
      selected: true,
      backend: b,
      pools: [
        AdPool('n', AdKind.native, ['TEST']),
      ],
    );
    await a.activate(enabled: true, consent: true);
    final h = b.finish(0);
    b.finish(1);
    await turn();
    final first = a.lease('n')!;
    final second = a.lease('n')!;
    expect(first.handle, same(h));
    expect(second.handle, isNot(same(h)));
    await first.release();
    await first.release();
    expect(h.disposed, 1);
    await a.close();
    for (var i = 2; i < b.requests.length; i++) {
      b.finish(i);
    }
    await turn();
  });
  testWidgets('timeout reserves physical request slots and releases late ads', (
    tester,
  ) async {
    final b = Backend();
    final a = AdInventory(
      selected: true,
      backend: b,
      loadTimeout: const Duration(seconds: 1),
      pools: [
        AdPool('i', AdKind.interstitial, ['TEST']),
      ],
    );
    await a.activate(enabled: true, consent: true);
    await tester.pump(const Duration(seconds: 2));
    a.refill();
    expect(b.requests.length, 2);
    expect(a.activeRequests, 2);
    final h = b.finish(0);
    b.finish(1);
    await tester.pump();
    expect(h.disposed, 1);
    expect(a.count('i'), 0);
    await a.close();
  });
  test('interstitial total capacity cannot exceed four', () {
    expect(
      () => AdInventory(
        backend: Backend(),
        pools: List.generate(
          3,
          (i) => AdPool('$i', AdKind.interstitial, ['TEST']),
        ),
      ),
      throwsArgumentError,
    );
  });
}
