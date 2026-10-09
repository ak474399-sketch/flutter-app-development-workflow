import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart' as g;
import 'inventory.dart';

class GoogleAdBackend implements AdBackend {
  final g.AdRequest request;
  final g.AdSize bannerSize;
  final g.NativeTemplateStyle? nativeStyle;
  final void Function(String pool, AdIncome income)? onIncome;
  final void Function()? onExternal;
  GoogleAdBackend({
    this.request = const g.AdRequest(nonPersonalizedAds: true),
    this.bannerSize = g.AdSize.banner,
    this.nativeStyle,
    this.onIncome,
    this.onExternal,
  });
  @override
  Future<void> initialize() async {
    await g.MobileAds.instance.initialize();
  }

  @override
  Future<AdHandle> load(AdPool pool, int slot) {
    final result = Completer<AdHandle>();
    final unit = pool.units[slot % pool.units.length];
    void paid(
      g.Ad ad,
      double micros,
      g.PrecisionType precision,
      String currency,
    ) {
      if (micros.isFinite && micros >= 0 && currency.isNotEmpty) {
        try {
          onIncome?.call(pool.id, AdIncome(micros, currency, precision.name));
        } catch (_) {}
      }
    }

    void launch(Future<void> operation, {g.Ad? ad}) {
      unawaited(
        operation.catchError((Object _) async {
          if (ad != null) await ad.dispose();
          if (!result.isCompleted)
            result.completeError(StateError('ad_bridge_failure'));
        }),
      );
    }

    void loaded(g.Ad ad) {
      if (result.isCompleted) {
        unawaited(ad.dispose());
        return;
      }
      if (ad is g.AdWithoutView) ad.onPaidEvent = paid;
      result.complete(_GoogleHandle(ad, pool.kind, onExternal));
    }

    void failed(g.LoadAdError error) {
      if (!result.isCompleted)
        result.completeError(StateError('ad_load_${error.code}'));
    }

    switch (pool.kind) {
      case AdKind.appOpen:
        launch(
          g.AppOpenAd.load(
            adUnitId: unit,
            request: request,
            adLoadCallback: g.AppOpenAdLoadCallback(
              onAdLoaded: loaded,
              onAdFailedToLoad: failed,
            ),
          ),
        );
      case AdKind.interstitial:
        launch(
          g.InterstitialAd.load(
            adUnitId: unit,
            request: request,
            adLoadCallback: g.InterstitialAdLoadCallback(
              onAdLoaded: loaded,
              onAdFailedToLoad: failed,
            ),
          ),
        );
      case AdKind.rewarded:
        launch(
          g.RewardedAd.load(
            adUnitId: unit,
            request: request,
            rewardedAdLoadCallback: g.RewardedAdLoadCallback(
              onAdLoaded: loaded,
              onAdFailedToLoad: failed,
            ),
          ),
        );
      case AdKind.banner:
        final ad = g.BannerAd(
          adUnitId: unit,
          size: bannerSize,
          request: request,
          listener: g.BannerAdListener(
            onAdLoaded: loaded,
            onAdFailedToLoad: (ad, error) {
              unawaited(ad.dispose());
              failed(error);
            },
            onAdOpened: (_) => onExternal?.call(),
            onPaidEvent: paid,
          ),
        );
        launch(ad.load(), ad: ad);
      case AdKind.native:
        final ad = g.NativeAd(
          adUnitId: unit,
          request: request,
          nativeTemplateStyle:
              nativeStyle ??
              g.NativeTemplateStyle(templateType: g.TemplateType.medium),
          listener: g.NativeAdListener(
            onAdLoaded: loaded,
            onAdFailedToLoad: (ad, error) {
              unawaited(ad.dispose());
              failed(error);
            },
            onAdOpened: (_) => onExternal?.call(),
            onPaidEvent: paid,
          ),
        );
        launch(ad.load(), ad: ad);
    }
    return result.future;
  }
}

class _GoogleHandle implements AdHandle {
  final g.Ad ad;
  @override
  final AdKind kind;
  final void Function()? onExternal;
  bool _used = false, _disposed = false, _earned = false;
  Completer<AdResult>? _done;
  _GoogleHandle(this.ad, this.kind, this.onExternal);
  @override
  Widget? get view =>
      ad is g.AdWithView ? g.AdWidget(ad: ad as g.AdWithView) : null;
  g.FullScreenContentCallback<T> _callbacks<T extends g.Ad>() =>
      g.FullScreenContentCallback<T>(
        onAdDismissedFullScreenContent: (_) => _finish(AdStatus.dismissed),
        onAdFailedToShowFullScreenContent: (_, error) =>
            _finish(AdStatus.failed),
        onAdClicked: (_) => onExternal?.call(),
      );
  void _finish(AdStatus state) {
    if (_done?.isCompleted == false)
      _done!.complete(AdResult(state, earned: _earned));
  }

  @override
  Future<AdResult> show({String? rewardNonce}) async {
    if (_used || _disposed) return const AdResult(AdStatus.failed);
    _used = true;
    _done = Completer<AdResult>();
    try {
      final current = ad;
      if (current is g.AppOpenAd) {
        current.fullScreenContentCallback = _callbacks<g.AppOpenAd>();
        await current.show();
      } else if (current is g.InterstitialAd) {
        current.fullScreenContentCallback = _callbacks<g.InterstitialAd>();
        await current.show();
      } else if (current is g.RewardedAd) {
        current.fullScreenContentCallback = _callbacks<g.RewardedAd>();
        if (rewardNonce != null)
          await current.setServerSideOptions(
            g.ServerSideVerificationOptions(customData: rewardNonce),
          );
        await current.show(
          onUserEarnedReward: (_, reward) {
            _earned = true;
          },
        );
      } else {
        _finish(AdStatus.failed);
      }
    } catch (_) {
      _finish(AdStatus.failed);
    }
    return _done!.future;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await ad.dispose();
  }
}

/// One unique lease per visible slot. Host removes this widget on keyboard/background.
class LeasedAdSlot extends StatefulWidget {
  final AdLease lease;
  final double width, height;
  const LeasedAdSlot({
    super.key,
    required this.lease,
    required this.width,
    required this.height,
  });
  @override
  State<LeasedAdSlot> createState() => _LeasedAdSlotState();
}

class _LeasedAdSlotState extends State<LeasedAdSlot> {
  @override
  void didUpdateWidget(LeasedAdSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lease != widget.lease) unawaited(oldWidget.lease.release());
  }

  @override
  void dispose() {
    unawaited(widget.lease.release());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    height: widget.height,
    child: ClipRect(child: widget.lease.handle.view ?? const SizedBox.shrink()),
  );
}
