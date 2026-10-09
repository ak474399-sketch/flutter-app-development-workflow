import 'package:in_app_purchase/in_app_purchase.dart' as iap;
import 'subscription.dart';

class InAppPurchaseClient implements StoreClient {
  final iap.InAppPurchase api;
  final Map<String, iap.ProductDetails> _products = {};
  InAppPurchaseClient({iap.InAppPurchase? api})
    : api = api ?? iap.InAppPurchase.instance;
  @override
  Stream<List<StoreUpdate>> get updates => api.purchaseStream.map(
    (list) => list
        .map(
          (p) => StoreUpdate(
            productId: p.productID,
            purchaseId: p.purchaseID,
            verificationData: p.verificationData.serverVerificationData,
            source: p.verificationData.source,
            needsCompletion: p.pendingCompletePurchase,
            native: p,
            state: switch (p.status) {
              iap.PurchaseStatus.pending => PurchaseState.pending,
              iap.PurchaseStatus.purchased => PurchaseState.purchased,
              iap.PurchaseStatus.restored => PurchaseState.restored,
              iap.PurchaseStatus.canceled => PurchaseState.canceled,
              iap.PurchaseStatus.error => PurchaseState.error,
            },
          ),
        )
        .toList(),
  );
  @override
  Future<bool> available() => api.isAvailable();
  @override
  Future<StoreCatalog> query(Set<String> ids) async {
    final result = await api.queryProductDetails(ids);
    if (result.error != null) throw StateError('Store product query failed');
    _products.clear();
    for (final p in result.productDetails) {
      _products[p.id] = p;
    }
    return StoreCatalog(
      result.productDetails
          .map(
            (p) => StoreProduct(
              id: p.id,
              title: p.title,
              price: p.price,
              currency: p.currencyCode,
              amount: p.rawPrice,
            ),
          )
          .toList(),
      result.notFoundIDs.toSet(),
    );
  }

  @override
  Future<bool> buy(String productId) {
    final product = _products[productId];
    if (product == null) throw ArgumentError('Product not queried');
    return api.buyNonConsumable(
      purchaseParam: iap.PurchaseParam(productDetails: product),
    );
  }

  @override
  Future<void> restore() => api.restorePurchases();
  @override
  Future<void> complete(StoreUpdate update) {
    final purchase = update.native;
    if (purchase is! iap.PurchaseDetails)
      throw ArgumentError('Missing native purchase');
    return api.completePurchase(purchase);
  }
}
