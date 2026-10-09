import 'dart:async';
import 'adapters.dart';
import 'models.dart';

class GrowthSdk {
  final GrowthConfig config;
  final GrowthBackend firebase;
  final MetaBackend meta;
  GrowthConsent _consent = const GrowthConsent();
  Map<String, Object> _remote;
  bool _started = false;
  bool _metaReady = false;
  bool _firebaseReady = false;
  bool _activated = false;
  bool _firebaseAllowed = false;
  bool _metaAllowed = false;
  final Set<String> _failed = {};
  Future<void> _tail = Future.value();

  GrowthSdk({required this.config, required this.firebase, required this.meta})
    : _remote = Map.of(config.remoteDefaults);

  Map<String, Object> get remote => Map.unmodifiable(_remote);
  Set<String> get failed => Set.unmodifiable(_failed);
  bool get ready => _firebaseReady && _metaReady;

  Future<void> _queue(Future<void> Function() op) {
    final next = _tail.then((_) => op());
    _tail = next.then((_) {}, onError: (Object e, StackTrace s) {});
    return next;
  }

  Future<bool> _try(String part, Future<void> Function() op) async {
    try {
      await op().timeout(config.timeout);
      _failed.remove(part);
      return true;
    } catch (_) {
      _failed.add(part);
      return false;
    }
  }

  /// Initializes Firebase with collection denied; Meta initialization waits for consent.
  /// Call again to retry failed adapters; repeated calls do not reactivate an already active app.
  Future<void> start() => _queue(() async {
    _started = true;
    if (!_firebaseReady) {
      _firebaseReady = await _try(
        'firebase_init',
        () => firebase.initialize(config.remoteDefaults),
      );
    }
    await _applyConsent();
  });

  Future<void> setConsent(GrowthConsent consent) => _queue(() async {
    _consent = consent;
    if (_started) await _applyConsent();
  });

  Future<void> _applyConsent() async {
    _firebaseAllowed = false;
    _metaAllowed = false;
    if (!_consent.metaEvents) _activated = false;
    if (_firebaseReady) {
      _firebaseAllowed = await _try(
        'firebase_consent',
        () => firebase.setConsent(_consent),
      );
    }
    if (_consent.metaEvents && !_metaReady) {
      _metaReady = await _try(
        'meta_init',
        () => meta.initialize(config.metaAppId, config.metaClientToken),
      );
    }
    if (_metaReady) {
      _metaAllowed = await _try(
        'meta_consent',
        () => meta.setConsent(_consent.metaEvents, _consent.advertiserId),
      );
      if (_metaAllowed && _consent.metaEvents && !_activated) {
        _activated = await _try('meta_activate', meta.activate);
      }
    }
  }

  Future<void> activate() => _queue(() async {
    if (_metaReady && _metaAllowed && _consent.metaEvents)
      await _try('meta_activate', meta.activate);
  });

  Future<void> track(
    String key, {
    Map<String, Object> params = const {},
    double? value,
  }) => _queue(() async {
    final rule = config.events[key];
    if (rule == null) throw ArgumentError('Event not defined: $key');
    final data = validateParams(rule, params);
    if (value != null && !value.isFinite)
      throw ArgumentError('Invalid event value');
    if (!_started) throw StateError('Call start before tracking');
    if (_firebaseReady && _firebaseAllowed && _consent.analytics) {
      await _try(
        'firebase_event',
        () => firebase.event(rule.firebaseName, data, value),
      );
    }
    if (_metaReady && _metaAllowed && _consent.metaEvents) {
      final mapped = {
        for (final e in data.entries) rule.metaFields[e.key] ?? e.key: e.value,
      };
      await _try('meta_event', () => meta.event(rule.metaName, mapped, value));
    }
  });

  Future<void> recordError(
    Object error,
    StackTrace stack, {
    bool fatal = false,
  }) => _queue(() async {
    if (_firebaseReady && _firebaseAllowed && _consent.crashReports) {
      await _try(
        'firebase_error',
        () => firebase.error(error.runtimeType.toString(), stack, fatal),
      );
    }
  });

  Future<void> refreshConfig() => _queue(() async {
    if (!_firebaseReady) return;
    await _try('remote_fetch', () async {
      final candidate = await firebase.fetchConfig(config.remoteDefaults);
      final checked = <String, Object>{};
      for (final e in config.remoteDefaults.entries) {
        final v = candidate[e.key];
        final matches = switch (e.value) {
          bool() => v is bool,
          String() => v is String,
          int() => v is int,
          double() => v is num && v.isFinite,
          _ => false,
        };
        if (!matches) throw StateError('Invalid remote value: ${e.key}');
        checked[e.key] = v!;
      }
      _remote = checked;
    });
  });
}
