enum ParamKind { text, number, flag }

class GrowthConsent {
  final bool analytics;
  final bool crashReports;
  final bool metaEvents;
  final bool advertiserId;
  const GrowthConsent({
    this.analytics = false,
    this.crashReports = false,
    this.metaEvents = false,
    this.advertiserId = false,
  });
}

class EventRule {
  final String firebaseName;
  final String metaName;
  final Map<String, ParamKind> fields;
  final Map<String, String> metaFields;
  const EventRule({
    required this.firebaseName,
    required this.metaName,
    this.fields = const {},
    this.metaFields = const {},
  });
}

class GrowthConfig {
  final String metaAppId;
  final String metaClientToken;
  final Map<String, Object> remoteDefaults;
  final Map<String, EventRule> events;
  final Duration timeout;
  GrowthConfig({
    required this.metaAppId,
    required this.metaClientToken,
    this.remoteDefaults = const {},
    this.events = const {},
    this.timeout = const Duration(seconds: 5),
  }) {
    if (!RegExp(r'^\d+$').hasMatch(metaAppId) || metaClientToken.isEmpty) {
      throw ArgumentError('Missing project Meta client configuration');
    }
    if (timeout <= Duration.zero) throw ArgumentError('Invalid timeout');
    for (final entry in remoteDefaults.entries) {
      if (!validName(entry.key) || !validScalar(entry.value)) {
        throw ArgumentError('Invalid remote default: ${entry.key}');
      }
    }
    for (final rule in events.values) {
      if (!validName(rule.firebaseName) || !validName(rule.metaName)) {
        throw ArgumentError('Invalid event name');
      }
      if (rule.fields.length > 25 ||
          rule.fields.keys.any((k) => !validName(k)) ||
          rule.metaFields.keys.any((k) => !rule.fields.containsKey(k)) ||
          rule.metaFields.values.any((k) => !validName(k))) {
        throw ArgumentError('Invalid event fields');
      }
    }
  }
}

bool validName(String s) => RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,39}$').hasMatch(s);
bool validScalar(Object v) =>
    v is String || v is bool || (v is num && v.isFinite);

Map<String, Object> validateParams(EventRule rule, Map<String, Object> params) {
  for (final e in params.entries) {
    final kind = rule.fields[e.key];
    final v = e.value;
    final ok = switch (kind) {
      ParamKind.text => v is String && v.length <= 100,
      ParamKind.number => v is num && v.isFinite,
      ParamKind.flag => v is bool,
      null => false,
    };
    if (!ok) throw ArgumentError('Unexpected or invalid event field: ${e.key}');
  }
  return Map.unmodifiable(params);
}
