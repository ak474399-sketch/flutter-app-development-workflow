import 'dart:async';
import 'package:flutter/widgets.dart';

enum AdKind { appOpen, interstitial, native, banner, rewarded }

enum AdStatus { unavailable, stale, busy, dismissed, failed }

class AdResult {
  final AdStatus status;
  final bool earned;
  const AdResult(this.status, {this.earned = false});
}

class AdIncome {
  final double micros;
  final String currency;
  final String precision;
  const AdIncome(this.micros, this.currency, this.precision);
}

class AdPool {
  final String id;
  final AdKind kind;
  final List<String> units;
  final int capacity;
  final int priority;
  AdPool(
    this.id,
    this.kind,
    List<String> units, {
    this.capacity = 2,
    this.priority = 10,
  }) : units = List.unmodifiable(units) {
    if (id.isEmpty ||
        units.isEmpty ||
        units.any((v) => v.isEmpty) ||
        capacity < 1 ||
        capacity > 2) {
      throw ArgumentError('Invalid pool configuration');
    }
  }
}

abstract interface class AdHandle {
  AdKind get kind;
  Widget? get view;
  Future<AdResult> show({String? rewardNonce});
  Future<void> dispose();
}

abstract interface class AdBackend {
  Future<void> initialize();
  Future<AdHandle> load(AdPool pool, int slot);
}

class _Cached {
  final AdHandle handle;
  final Duration at;
  final int slot;
  _Cached(this.handle, this.at, this.slot);
}

class AdLease {
  final AdHandle handle;
  final Future<void> Function() _release;
  bool _released = false;
  AdLease._(this.handle, this._release);
  Future<void> release() async {
    if (_released) return;
    _released = true;
    await _release();
  }
}

/// Inventory is in memory. Business triggers, UMP consent and SSV are host-owned.
class AdInventory {
  final AdBackend backend;
  final bool selected;
  final List<AdPool> pools;
  final int concurrency;
  final Duration ttl, loadTimeout;
  final Duration Function()? clock;
  final Map<String, List<_Cached>> _ready = {};
  final Map<String, Set<int>> _loading = {};
  final Map<String, int> _failures = {};
  final Map<String, Duration> _blocked = {};
  final Set<Timer> _timers = {};
  final Set<AdLease> _leases = {};
  bool _enabled = false, _initialized = false, _closed = false;
  bool foreground = true;
  bool _showing = false, _initializing = false;
  bool _externalResume = false;
  int _epoch = 0, _active = 0;
  final Stopwatch _watch = Stopwatch()..start();

  AdInventory({
    required this.backend,
    required List<AdPool> pools,
    this.selected = false,
    this.concurrency = 4,
    this.ttl = const Duration(minutes: 55),
    this.loadTimeout = const Duration(seconds: 25),
    this.clock,
  }) : pools = List.unmodifiable(pools) {
    if (concurrency < 1 ||
        concurrency > 4 ||
        ttl <= Duration.zero ||
        loadTimeout <= Duration.zero ||
        pools.map((p) => p.id).toSet().length != pools.length ||
        pools
                .where((p) => p.kind == AdKind.interstitial)
                .fold<int>(0, (n, p) => n + p.capacity) >
            4) {
      throw ArgumentError('Invalid inventory limits');
    }
  }
  Duration get _now => clock?.call() ?? _watch.elapsed;
  bool get enabled => selected && _enabled && !_closed;
  bool get showing => _showing;
  int get activeRequests => _active;
  int count(String id) => _ready[id]?.length ?? 0;
  int pending(String id) => _loading[id]?.length ?? 0;
  AdPool _pool(String id) => pools.firstWhere((p) => p.id == id);

  Future<void> activate({required bool enabled, required bool consent}) async {
    if (_closed) return;
    _enabled = selected && enabled && consent;
    if (!_enabled) {
      await _clear();
      return;
    }
    if (!_initialized && !_initializing) {
      _initializing = true;
      try {
        await backend.initialize().timeout(loadTimeout);
        _initialized = true;
      } catch (_) {
        _initialized = false;
      } finally {
        _initializing = false;
      }
    }
    refill();
  }

  Future<void> _clear() async {
    _epoch++;
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    final old = _ready.values.expand((p) => p).toList();
    _ready.clear();
    _blocked.clear();
    _failures.clear();
    for (final item in old) {
      await _dispose(item.handle);
    }
    for (final lease in _leases.toList()) {
      await lease.release();
    }
  }

  Future<void> _dispose(AdHandle handle) async {
    try {
      await handle.dispose();
    } catch (_) {
      /* best-effort release */
    }
  }

  void prune(String id) {
    final pool = _ready[id] ??= [];
    final expired = pool.where((a) => _now - a.at >= ttl).toList();
    pool.removeWhere(expired.contains);
    for (final ad in expired) {
      unawaited(_dispose(ad.handle));
    }
  }

  void refill() {
    if (!enabled || !_initialized || !foreground) return;
    final sorted = [...pools]..sort((a, b) => b.priority.compareTo(a.priority));
    for (final pool in sorted) {
      prune(pool.id);
      if (_now < (_blocked[pool.id] ?? Duration.zero)) continue;
      while (count(pool.id) + pending(pool.id) < pool.capacity &&
          _active < concurrency) {
        final used = {
          ...?_loading[pool.id],
          ...?_ready[pool.id]?.map((a) => a.slot),
        };
        final slot = List.generate(
          pool.capacity,
          (i) => i,
        ).firstWhere((i) => !used.contains(i));
        (_loading[pool.id] ??= {}).add(slot);
        _active++;
        unawaited(_load(pool, slot, _epoch));
      }
    }
  }

  Future<void> _load(AdPool pool, int slot, int epoch) async {
    AdHandle? handle;
    bool timedOut = false;
    Future<AdHandle>? request;
    try {
      request = backend.load(pool, slot);
      handle = await request.timeout(loadTimeout);
    } catch (_) {
      timedOut = true;
    }
    // Full-screen SDK loads cannot be cancelled. Reserve physical concurrency
    // until the underlying callback completes; reject and release late results.
    if (timedOut && request != null) {
      try {
        handle = await request;
      } catch (_) {}
    }
    _loading[pool.id]?.remove(slot);
    _active--;
    final current = enabled && epoch == _epoch;
    if (handle != null && current && !timedOut && handle.kind == pool.kind) {
      (_ready[pool.id] ??= []).add(_Cached(handle, _now, slot));
      _failures[pool.id] = 0;
    } else {
      if (handle != null) await _dispose(handle);
      if (current) {
        final fail = (_failures[pool.id] ?? 0) + 1;
        _failures[pool.id] = fail;
        final delay = Duration(seconds: fail <= 3 ? fail * 5 : 300);
        _blocked[pool.id] = _now + delay;
        if (fail <= 3) {
          late Timer timer;
          timer = Timer(delay, () {
            _timers.remove(timer);
            refill();
          });
          _timers.add(timer);
        }
      }
    }
    refill();
  }

  _Cached? _take(String id) {
    if (!enabled || !foreground) return null;
    _pool(id);
    prune(id);
    final pool = _ready[id]!;
    if (pool.isEmpty) {
      refill();
      return null;
    }
    final result = pool.removeAt(0);
    refill();
    return result;
  }

  AdLease? lease(String id) {
    final spec = _pool(id);
    if (spec.kind != AdKind.banner && spec.kind != AdKind.native) {
      throw ArgumentError('Only inline ads use leases');
    }
    final ad = _take(id);
    if (ad == null) return null;
    late AdLease lease;
    lease = AdLease._(ad.handle, () async {
      _leases.remove(lease);
      await _dispose(ad.handle);
      refill();
    });
    _leases.add(lease);
    return lease;
  }

  Future<AdResult> show(
    String id, {
    required bool Function() isCurrent,
    String? rewardNonce,
  }) async {
    final kind = _pool(id).kind;
    if (kind == AdKind.native || kind == AdKind.banner)
      throw ArgumentError('Use lease for inline ads');
    if (!enabled || !foreground) return const AdResult(AdStatus.unavailable);
    if (_showing) return const AdResult(AdStatus.busy);
    if (!isCurrent()) return const AdResult(AdStatus.stale);
    final ad = _take(id);
    if (ad == null) return const AdResult(AdStatus.unavailable);
    _showing = true;
    try {
      if (!enabled || !foreground || !isCurrent())
        return const AdResult(AdStatus.stale);
      return await ad.handle.show(rewardNonce: rewardNonce);
    } catch (_) {
      return const AdResult(AdStatus.failed);
    } finally {
      await _dispose(ad.handle);
      _showing = false;
      refill();
    }
  }

  /// App-open only; interstitial fallback requires an explicit host policy.
  Future<AdResult> startup(
    String id, {
    required bool Function() isCurrent,
    Duration budget = const Duration(seconds: 10),
  }) async {
    final deadline = _now + budget;
    if (budget <= Duration.zero || _pool(id).kind != AdKind.appOpen)
      throw ArgumentError('Invalid startup request');
    if (!enabled) return const AdResult(AdStatus.unavailable);
    final watch = Stopwatch()..start();
    while (enabled &&
        foreground &&
        isCurrent() &&
        _now < deadline &&
        watch.elapsed < budget) {
      prune(id);
      if (count(id) > 0) return show(id, isCurrent: isCurrent);
      refill();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return const AdResult(AdStatus.unavailable);
  }

  void markExternalAdNavigation() {
    _externalResume = true;
  }

  bool resumeOpportunity() {
    foreground = true;
    refill();
    final eligible = enabled && !_showing && !_externalResume;
    _externalResume = false;
    return eligible;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _enabled = false;
    await _clear();
  }
}
