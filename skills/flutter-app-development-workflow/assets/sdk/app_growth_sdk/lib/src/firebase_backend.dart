import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'adapters.dart';
import 'models.dart';

class FirebaseBackend implements GrowthBackend {
  final FirebaseOptions? options;
  FirebaseBackend({this.options});

  @override
  Future<void> initialize(Map<String, Object> defaults) async {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: options);
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(false);
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
    await FirebaseRemoteConfig.instance.setDefaults(defaults);
    await FirebaseRemoteConfig.instance.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 5),
        minimumFetchInterval: const Duration(hours: 12),
      ),
    );
  }

  @override
  Future<void> setConsent(GrowthConsent consent) async {
    await FirebaseAnalytics.instance.setConsent(
      analyticsStorageConsentGranted: consent.analytics,
      adStorageConsentGranted: false,
      adUserDataConsentGranted: false,
      adPersonalizationSignalsConsentGranted: false,
    );
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(
      consent.analytics,
    );
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      consent.crashReports,
    );
  }

  @override
  Future<void> event(String name, Map<String, Object> params, double? value) {
    final values = <String, Object>{
      for (final e in params.entries)
        e.key: e.value is bool ? (e.value == true ? 1 : 0) : e.value,
      if (value != null) 'value': value,
    };
    return FirebaseAnalytics.instance.logEvent(name: name, parameters: values);
  }

  @override
  Future<void> error(String type, StackTrace stack, bool fatal) =>
      FirebaseCrashlytics.instance.recordError(
        StateError('Application error type: $type'),
        stack,
        fatal: fatal,
      );

  @override
  Future<Map<String, Object>> fetchConfig(Map<String, Object> defaults) async {
    await FirebaseRemoteConfig.instance.fetchAndActivate();
    final values = FirebaseRemoteConfig.instance;
    final result = <String, Object>{};
    for (final e in defaults.entries) {
      final raw = values.getValue(e.key).asString();
      final Object? parsed = switch (e.value) {
        bool() => raw == 'true' ? true : (raw == 'false' ? false : null),
        int() => int.tryParse(raw),
        double() => double.tryParse(raw),
        _ => raw,
      };
      if (parsed == null || !validScalar(parsed)) {
        throw StateError('Invalid remote value: ${e.key}');
      }
      result[e.key] = parsed;
    }
    return result;
  }
}
