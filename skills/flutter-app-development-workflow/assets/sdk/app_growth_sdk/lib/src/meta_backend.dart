import 'package:flutter/services.dart';
import 'adapters.dart';

class NativeMetaBackend implements MetaBackend {
  static const channel = MethodChannel('dev.workflow/app_growth');

  @override
  Future<void> initialize(String appId, String clientToken) =>
      channel.invokeMethod<void>('initialize', {
        'appId': appId,
        'clientToken': clientToken,
      });
  @override
  Future<void> setConsent(bool events, bool advertiserId) =>
      channel.invokeMethod<void>('consent', {
        'events': events,
        'advertiserId': advertiserId,
      });
  @override
  Future<void> activate() => channel.invokeMethod<void>('activate');
  @override
  Future<void> event(String name, Map<String, Object> params, double? value) =>
      channel.invokeMethod<void>('event', {
        'name': name,
        'params': params,
        'value': value,
      });
}
