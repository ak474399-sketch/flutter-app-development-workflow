# App Growth SDK 0.1.0

Android-first runtime adapter. Firebase Analytics/Crashlytics/Remote Config and Meta App Events are required. Commercialization stays out of this foundation package; real optional runtime adapters are in ../app_iaa_sdk and ../app_subscription_sdk. No iOS Meta plugin is implemented.

## Add to an application
Copy this folder into `packages/app_growth_sdk`, then declare:

```yaml
dependencies:
  app_growth_sdk:
    path: packages/app_growth_sdk
```

Configure this product with FlutterFire (FirebaseOptions or native platform configuration). Meta host AndroidManifest must supply this product's App ID and Client Token metadata:

```xml
<meta-data android:name="com.facebook.sdk.ApplicationId" android:value="@string/meta_app_id" />
<meta-data android:name="com.facebook.sdk.ClientToken" android:value="@string/meta_client_token" />
```

Create those string resources from your environment configuration. Never use a Meta App Secret here. Match Firebase/Meta platform registration to the build identity. Plugin manifest denies automatic collection before application consent. Confirm merged manifest retains these flags; don't override them to true before consent.

```dart
final growth = GrowthSdk(
  config: GrowthConfig(
    metaAppId: projectMetaAppId,
    metaClientToken: projectMetaClientToken,
    remoteDefaults: {'feature_enabled': false},
    events: {
      'feature_open': EventRule(
        firebaseName: 'feature_open', metaName: 'feature_open',
        fields: {'feature_id': ParamKind.text},
      ),
    },
  ),
  firebase: FirebaseBackend(options: projectFirebaseOptions),
  meta: NativeMetaBackend(),
);
await growth.start();
// Explicit project consent; never treat installation as consent.
await growth.setConsent(consentFromYourPrivacyFlow);
await growth.track('feature_open', params: {'feature_id': 'example_feature'});
await growth.refreshConfig();
```

Hook Flutter errors and platform errors in the host, preserving any existing handlers, and call `recordError`. It sends only the error type and stack; host-provided stacks must not include private content. On genuine foreground activation call `activate`, using one source of lifecycle events. The SDK does not watch routes/lifecycle automatically or invent installation events.

Parameter allowlists check names/types/size, not whether a permitted string contains personal data. Don't define fields for messages, photos, health readings, tokens or emails. Only pass approved non-sensitive business identifiers. Meta advertiser-ID flag remains false unless explicitly consented/configured. Firebase ad consent remains denied; enabling advertising consent is a separate extension.

Commercial modules may add verified purchase/ad-income event definitions with explicit currency, amount and provider mapping. Events alone do not process payments, grant entitlements, validate SSV or establish attribution. Automatic purchase logging is disabled to avoid duplicate manual events.

## Observable state and retry
Check `failed` for init/consent/event/config failures. `ready` means both adapters initialized, not backend receipt. Denied Meta consent intentionally leaves Meta uninitialized; Firebase can operate independently. Call `start` to retry init failures. Track failures aren't replayed automatically: use application-owned idempotency and confirmed transaction/event rules. Config rejects incompatible values and retains previous valid defaults on failures.

## Verification
`flutter analyze` and `flutter test` exercise orchestration and channel contracts without credentials. Android host debug build validates native API compatibility. Real initialization, installed-device events, Firebase consoles, Meta receipt and ad attribution require your project configuration and remain separate gates. No production data or device tests should run merely from installing this package.
