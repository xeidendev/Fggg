import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'save.dart';
import 'theme.dart';

/// ---------------------------------------------------------------------------
/// AdMob configuration.
///
/// The ids below are GOOGLE'S OFFICIAL TEST IDS — they always fill, never
/// violate policy and let you verify every placement before release.
///
/// BEFORE PUBLISHING:
///   1. Create an AdMob app + ad units at https://apps.admob.com
///   2. Replace appId here AND in android/app/src/main/AndroidManifest.xml
///      (meta-data com.google.android.gms.ads.APPLICATION_ID).
///   3. Replace bannerId / interstitialId / rewardedId below.
/// ---------------------------------------------------------------------------
class AdConfig {
  static const String appId = 'ca-app-pub-3940256099942544~3347511713';
  static const String bannerId = 'ca-app-pub-3940256099942544/6300978111';
  static const String interstitialId = 'ca-app-pub-3940256099942544/1033173712';
  static const String rewardedId = 'ca-app-pub-3940256099942544/5224354917';

  /// Show a full-screen interstitial after every N completed levels.
  static const int interstitialEvery = 3;

  /// Free coins granted by the rewarded ad in the shop.
  static const int rewardedCoins = 50;
}

/// Central ad facade: banner widget, interstitial cadence, rewarded ads.
/// Everything is fail-safe — ads must never crash or block the game.
class Ads {
  static bool _initialized = false;
  static InterstitialAd? _interstitial;
  static RewardedAd? _rewarded;
  static int _levelExits = 0;
  static bool _interstitialLoading = false;
  static bool _rewardedLoading = false;

  static bool get adsRemoved => GameSave.instance.adsRemoved;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      await MobileAds.instance.initialize();
      _initialized = true;
      _loadInterstitial();
      _loadRewarded();
    } catch (_) {
      // Ads are strictly optional — offline devices keep working.
    }
  }

  // ---- banner ----
  // Banners live in the AdBanner widget below (it sizes itself adaptively).

  // ---- interstitial ----
  static void _loadInterstitial() {
    if (!_initialized || adsRemoved || _interstitialLoading) return;
    _interstitialLoading = true;
    InterstitialAd.load(
      adUnitId: AdConfig.interstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialLoading = false;
          _interstitial = ad;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _interstitial = null;
              _loadInterstitial(); // preload the next one
            },
            onAdFailedToShowFullScreenContent: (ad, _) {
              ad.dispose();
              _interstitial = null;
              _loadInterstitial();
            },
          );
        },
        onAdFailedToLoad: (_) => _interstitialLoading = false,
      ),
    );
  }

  /// Call after every completed level — shows an interstitial on the
  /// configured cadence. No-op when ads were purchased or nothing loaded.
  static void onLevelCompleted() {
    if (!_initialized || adsRemoved) return;
    _levelExits++;
    if (_levelExits % AdConfig.interstitialEvery != 0) return;
    _interstitial?.show();
    _interstitial = null;
  }

  // ---- rewarded ----
  static void _loadRewarded() {
    if (!_initialized || _rewardedLoading) return;
    _rewardedLoading = true;
    RewardedAd.load(
      adUnitId: AdConfig.rewardedId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedLoading = false;
          _rewarded = ad;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _rewarded = null;
              _loadRewarded();
            },
            onAdFailedToShowFullScreenContent: (ad, _) {
              ad.dispose();
              _rewarded = null;
              _loadRewarded();
            },
          );
        },
        onAdFailedToLoad: (_) => _rewardedLoading = false,
      ),
    );
  }

  static bool get rewardedReady => _rewarded != null;

  /// Shows a rewarded ad. [onReward] fires only after the reward was earned.
  /// If no ad is ready a friendly snackbar is shown instead — never a crash.
  static void showRewarded(
    BuildContext context, {
    required VoidCallback onReward,
    String adLabel = 'reward',
  }) {
    final ad = _rewarded;
    if (!_initialized || ad == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.ink,
          content: Text(
            'No ad available right now — check your connection and try again!',
            style: AppTheme.body(14, color: Colors.white),
          ),
          duration: const Duration(milliseconds: 1600),
        ),
      );
      return;
    }
    ad.show(onUserEarnedReward: (_, reward) => onReward());
    _rewarded = null;
    _loadRewarded();
  }
}

/// Anchored adaptive banner that manages its own lifecycle.
/// Renders nothing when ads were purchased via the IAP.
class AdBanner extends StatefulWidget {
  const AdBanner({super.key, this.margin = const EdgeInsets.symmetric(vertical: 6)});

  final EdgeInsetsGeometry margin;

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _banner;
  bool _loaded = false;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_banner == null && !Ads.adsRemoved) {
      final width = MediaQuery.of(context).size.width.truncate();
      final size = AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
              width <= 0 ? 360 : width)
          as AdSize?;
      if (size != null) {
        _banner = BannerAd(
          adUnitId: AdConfig.bannerId,
          size: size,
          request: const AdRequest(),
          listener: BannerAdListener(
            onAdLoaded: (_) {
              if (mounted) setState(() => _loaded = true);
            },
            onAdFailedToLoad: (_, __) {
              if (mounted) setState(() => _failed = true);
            },
          ),
        )..load();
      } else {
        _failed = true;
      }
    }
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Ads.adsRemoved || _failed || _banner == null || !_loaded) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: widget.margin,
      child: SafeArea(
        top: false,
        child: Center(
          child: SizedBox(
            width: _banner!.size.width.toDouble(),
            height: _banner!.size.height.toDouble(),
            child: AdWidget(ad: _banner!),
          ),
        ),
      ),
    );
  }
}
