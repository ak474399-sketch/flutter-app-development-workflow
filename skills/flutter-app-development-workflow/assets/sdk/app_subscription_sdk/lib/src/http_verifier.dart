import 'dart:convert';
import 'dart:io';
import 'subscription.dart';

/// An authenticated backend adapter. The backend must verify the store, binding,
/// expiry/revocation and commit rights; a JSON response alone is not verification.
class HttpEntitlementVerifier implements EntitlementVerifier {
  final Uri endpoint;
  final Future<String> Function() accessToken;
  final HttpClient client;
  final Duration timeout;
  HttpEntitlementVerifier({
    required this.endpoint,
    required this.accessToken,
    HttpClient? client,
    this.timeout = const Duration(seconds: 15),
  }) : client = client ?? HttpClient() {
    if (endpoint.scheme != 'https' ||
        endpoint.host.isEmpty ||
        timeout <= Duration.zero) {
      throw ArgumentError('HTTPS verification endpoint required');
    }
  }
  @override
  Future<VerifiedEntitlement> verifyAndApply(StoreUpdate update) async {
    if (update.verificationData.isEmpty)
      throw ArgumentError('Store proof missing');
    final token = await accessToken().timeout(timeout);
    if (token.isEmpty) throw StateError('Authentication required');
    final request = await client.postUrl(endpoint).timeout(timeout);
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.write(
      jsonEncode({
        'productId': update.productId,
        'purchaseId': update.purchaseId,
        'source': update.source,
        'proof': update.verificationData,
        'restored': update.state == PurchaseState.restored,
      }),
    );
    final response = await request.close().timeout(timeout);
    if (response.statusCode != 200) {
      await response.drain<void>().timeout(timeout);
      throw StateError('Verification unavailable');
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(timeout)) {
      bytes.addAll(chunk);
      if (bytes.length > 65536)
        throw StateError('Verification response too large');
    }
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map ||
        data['active'] is! bool ||
        data['transactionId'] is! String)
      throw StateError('Invalid verification response');
    return VerifiedEntitlement(
      active: data['active'] as bool,
      transactionId: data['transactionId'] as String,
    );
  }

  void close() => client.close(force: true);
}
