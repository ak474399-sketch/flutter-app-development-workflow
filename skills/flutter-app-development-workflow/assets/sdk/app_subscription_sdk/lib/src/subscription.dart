import 'dart:async';
import 'package:flutter/foundation.dart';

enum PurchaseState { pending, purchased, restored, canceled, error }

enum SubscriptionState {
  idle,
  loading,
  ready,
  purchasing,
  pending,
  verifying,
  active,
  canceled,
  failed,
  unavailable,
}

class StoreProduct {
  final String id, title, price, currency;
  final double amount;
  const StoreProduct({
    required this.id,
    required this.title,
    required this.price,
    required this.currency,
    required this.amount,
  });
}

class StoreUpdate {
  final String productId;
  final String? purchaseId;
  final PurchaseState state;
  final String verificationData, source;
  final bool needsCompletion;
  final Object? native;
  const StoreUpdate({
    required this.productId,
    required this.state,
    this.purchaseId,
    this.verificationData = '',
    this.source = '',
    this.needsCompletion = false,
    this.native,
  });
}

class StoreCatalog {
  final List<StoreProduct> products;
  final Set<String> missing;
  StoreCatalog(List<StoreProduct> products, Set<String> missing)
    : products = List.unmodifiable(products),
      missing = Set.unmodifiable(missing);
}

abstract interface class StoreClient {
  Stream<List<StoreUpdate>> get updates;
  Future<bool> available();
  Future<StoreCatalog> query(Set<String> ids);
  Future<bool> buy(String productId);
  Future<void> restore();
  Future<void> complete(StoreUpdate update);
}

class VerifiedEntitlement {
  final bool active;

  /// Backend/store canonical transaction identity, never a client-generated ID.
  final String transactionId;
  const VerifiedEntitlement({
    required this.active,
    required this.transactionId,
  });
}

abstract interface class EntitlementVerifier {
  /// Real backend verifies store proof and commits rights idempotently before returning active.
  Future<VerifiedEntitlement> verifyAndApply(StoreUpdate update);
}

/// App-scoped: keep listening when the paywall is dismissed. No local mock grant.
class SubscriptionController extends ChangeNotifier {
  final StoreClient store;
  final EntitlementVerifier verifier;
  final Set<String> productIds;
  final Duration timeout;
  final void Function(String transactionId, StoreUpdate update)? onVerified;
  SubscriptionState state = SubscriptionState.idle;
  List<StoreProduct> products = [];
  Set<String> missing = {};
  int successRevision = 0;
  final Set<String> _reported = {};
  final Map<String, StoreUpdate> _retry = {};
  StreamSubscription<List<StoreUpdate>>? _listener;
  Future<void> _tail = Future.value();
  bool _closed = false, _command = false, _starting = false;
  SubscriptionController({
    required this.store,
    required this.verifier,
    required Set<String> productIds,
    this.timeout = const Duration(seconds: 20),
    this.onVerified,
  }) : productIds = Set.unmodifiable(productIds) {
    if (productIds.isEmpty ||
        productIds.any((v) => v.isEmpty) ||
        timeout <= Duration.zero)
      throw ArgumentError('Invalid subscription config');
  }
  bool get busy =>
      _command ||
      _starting ||
      {
        SubscriptionState.purchasing,
        SubscriptionState.pending,
        SubscriptionState.verifying,
      }.contains(state);
  void _set(SubscriptionState next) {
    if (_closed) return;
    state = next;
    notifyListeners();
  }

  Future<void> start() async {
    if (_closed || _starting) return;
    _listener ??= store.updates.listen(
      (list) {
        for (final update in list) {
          _tail = _tail.then((_) => _handle(update)).catchError((Object _) {
            _set(SubscriptionState.failed);
          });
        }
      },
      onError: (Object _) {
        _set(SubscriptionState.failed);
      },
    );
    _starting = true;
    _set(SubscriptionState.loading);
    try {
      if (!await store.available().timeout(timeout)) {
        _set(SubscriptionState.unavailable);
        return;
      }
      final catalog = await store.query(productIds).timeout(timeout);
      if (_closed) return;
      products = List.unmodifiable(
        catalog.products.where((p) => productIds.contains(p.id)),
      );
      missing = catalog.missing;
      if (state == SubscriptionState.loading)
        _set(
          products.isEmpty
              ? SubscriptionState.unavailable
              : SubscriptionState.ready,
        );
      else
        notifyListeners();
    } catch (_) {
      _set(SubscriptionState.failed);
    } finally {
      _starting = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<void> purchase(String productId) async {
    if (_closed || busy || !products.any((p) => p.id == productId)) return;
    _command = true;
    _set(SubscriptionState.purchasing);
    try {
      final launched = await store.buy(productId).timeout(timeout);
      if (!launched) _set(SubscriptionState.failed);
    } catch (_) {
      _set(SubscriptionState.failed);
    } finally {
      _command = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<void> restore() async {
    if (_closed || busy) return;
    _command = true;
    _set(SubscriptionState.pending);
    try {
      await store.restore().timeout(timeout);
      await _tail;
      if (state == SubscriptionState.pending) _set(SubscriptionState.ready);
    } catch (_) {
      _set(SubscriptionState.failed);
    } finally {
      _command = false;
      if (!_closed) notifyListeners();
    }
  }

  String _key(StoreUpdate update) =>
      '${update.source}|${update.productId}|${update.purchaseId ?? update.verificationData}';
  Future<void> _handle(StoreUpdate update) async {
    if (_closed || !productIds.contains(update.productId)) return;
    switch (update.state) {
      case PurchaseState.pending:
        _set(SubscriptionState.pending);
        return;
      case PurchaseState.canceled:
        _set(SubscriptionState.canceled);
        return;
      case PurchaseState.error:
        _set(SubscriptionState.failed);
        return;
      case PurchaseState.purchased:
      case PurchaseState.restored:
        break;
    }
    _retry[_key(update)] = update;
    _set(SubscriptionState.verifying);
    try {
      final rights = await verifier.verifyAndApply(update).timeout(timeout);
      if (_closed) return;
      if (!rights.active || rights.transactionId.isEmpty) {
        _set(SubscriptionState.failed);
        return;
      }
      // Finish store acknowledgement only after the backend has verified and committed rights.
      if (update.needsCompletion) await store.complete(update).timeout(timeout);
      if (_closed) return;
      _retry.remove(_key(update));
      if (_reported.add(rights.transactionId)) {
        try {
          onVerified?.call(rights.transactionId, update);
        } catch (_) {}
      }
      successRevision++;
      _set(SubscriptionState.active);
    } catch (_) {
      _set(SubscriptionState.failed);
    }
  }

  Future<void> retryVerification() async {
    if (_closed || busy) return;
    for (final update in _retry.values.toList()) {
      _tail = _tail.then((_) => _handle(update));
    }
    await _tail;
  }

  Future<void> drain() => _tail;
  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    unawaited(_listener?.cancel());
    _listener = null;
    super.dispose();
  }
}
