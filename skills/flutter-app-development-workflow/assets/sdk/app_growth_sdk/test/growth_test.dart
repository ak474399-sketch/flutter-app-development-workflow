import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:app_growth_sdk/app_growth_sdk.dart';

class FakeFirebase implements GrowthBackend {
  int init = 0, events = 0, errors = 0;
  bool failInit = false, failConsent = false;
  GrowthConsent consent = const GrowthConsent();
  Map<String, Object> values = {'enabled': true};
  String? errorType;
  @override
  Future<void> initialize(Map<String, Object> defaults) async {
    init++;
    if (failInit) throw StateError('failure');
  }

  @override
  Future<void> setConsent(GrowthConsent value) async {
    if (failConsent) throw StateError('failure');
    consent = value;
  }

  @override
  Future<void> event(
    String name,
    Map<String, Object> params,
    double? value,
  ) async {
    events++;
  }

  @override
  Future<void> error(String type, StackTrace stack, bool fatal) async {
    errors++;
    errorType = type;
  }

  @override
  Future<Map<String, Object>> fetchConfig(Map<String, Object> defaults) async =>
      values;
}

class FakeMeta implements MetaBackend {
  int init = 0, events = 0, activated = 0;
  bool allowed = false;
  Map<String, Object>? last;
  @override
  Future<void> initialize(String id, String token) async {
    init++;
  }

  @override
  Future<void> setConsent(bool events, bool ids) async {
    allowed = events;
  }

  @override
  Future<void> activate() async {
    activated++;
  }

  @override
  Future<void> event(
    String name,
    Map<String, Object> params,
    double? value,
  ) async {
    events++;
    last = params;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeFirebase fb;
  late FakeMeta meta;
  late GrowthSdk sdk;
  setUp(() {
    fb = FakeFirebase();
    meta = FakeMeta();
    sdk = GrowthSdk(
      config: GrowthConfig(
        metaAppId: '123',
        metaClientToken: 'TEST_ONLY',
        remoteDefaults: {'enabled': false},
        events: {
          'open': EventRule(
            firebaseName: 'open',
            metaName: 'open',
            fields: {'feature': ParamKind.text},
            metaFields: {'feature': 'feature_id'},
          ),
        },
      ),
      firebase: fb,
      meta: meta,
    );
  });
  test(
    'denied consent initializes Firebase without Meta or tracked events',
    () async {
      await sdk.start();
      await sdk.track('open', params: {'feature': 'a'});
      expect(fb.init, 1);
      expect(meta.init, 0);
      expect(fb.events, 0);
      expect(meta.events, 0);
    },
  );
  test('grant then revoke applies gates and no duplicate activation', () async {
    await sdk.start();
    await sdk.setConsent(
      const GrowthConsent(analytics: true, metaEvents: true),
    );
    await sdk.start();
    expect(meta.activated, 1);
    await sdk.track('open', params: {'feature': 'a'});
    expect(meta.last, {'feature_id': 'a'});
    await sdk.setConsent(const GrowthConsent());
    await sdk.track('open', params: {'feature': 'b'});
    expect(meta.events, 1);
    expect(fb.events, 1);
  });
  test('unexpected or private-shaped undeclared parameters rejected', () async {
    await sdk.start();
    await expectLater(
      sdk.track('open', params: {'message': 'private'}),
      throwsArgumentError,
    );
    await expectLater(
      sdk.track('open', value: double.nan),
      throwsArgumentError,
    );
  });
  test('failed consent never enables event delivery', () async {
    await sdk.start();
    fb.failConsent = true;
    await sdk.setConsent(const GrowthConsent(analytics: true));
    await sdk.track('open');
    expect(fb.events, 0);
    expect(sdk.failed, contains('firebase_consent'));
  });
  test('remote invalid response retains last valid snapshot', () async {
    await sdk.start();
    await sdk.refreshConfig();
    expect(sdk.remote['enabled'], true);
    fb.values = {'enabled': 'wrong'};
    await sdk.refreshConfig();
    expect(sdk.remote['enabled'], true);
    expect(sdk.failed, contains('remote_fetch'));
  });
  test('init retry and exception body not forwarded', () async {
    fb.failInit = true;
    await sdk.start();
    expect(sdk.failed, contains('firebase_init'));
    fb.failInit = false;
    await sdk.start();
    await sdk.setConsent(const GrowthConsent(crashReports: true));
    await sdk.recordError(StateError('PRIVATE_BODY'), StackTrace.empty);
    expect(fb.errorType, 'StateError');
    expect(fb.errors, 1);
  });
  test('native channel forwards explicit config/consent and events', () async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('dev.workflow/app_growth');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
          calls.add(c);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final native = NativeMetaBackend();
    await native.initialize('123', 'TEST_ONLY');
    await native.setConsent(true, false);
    await native.activate();
    await native.event('open', {'feature_id': 'a'}, null);
    expect(calls.map((c) => c.method), [
      'initialize',
      'consent',
      'activate',
      'event',
    ]);
    expect((calls[1].arguments as Map)['advertiserId'], false);
  });
}
