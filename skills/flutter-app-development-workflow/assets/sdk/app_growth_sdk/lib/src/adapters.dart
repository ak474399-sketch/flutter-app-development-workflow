import 'models.dart';

abstract interface class GrowthBackend {
  Future<void> initialize(Map<String, Object> defaults);
  Future<void> setConsent(GrowthConsent consent);
  Future<void> event(String name, Map<String, Object> params, double? value);
  Future<void> error(String type, StackTrace stack, bool fatal);
  Future<Map<String, Object>> fetchConfig(Map<String, Object> defaults);
}

abstract interface class MetaBackend {
  Future<void> initialize(String appId, String clientToken);
  Future<void> setConsent(bool events, bool advertiserId);
  Future<void> activate();
  Future<void> event(String name, Map<String, Object> params, double? value);
}
