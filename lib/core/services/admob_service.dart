import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../config/env.dart';

class AdMobService {
  static final AdMobService instance = AdMobService._internal();
  AdMobService._internal();

  InterstitialAd? _interstitialAd;
  bool _isInterstitialLoading = false;
  DateTime? _lastInterstitialShownAt;

  // 4-Minute Cooldown rule (Section 9.3)
  static const Duration _cooldownDuration = Duration(minutes: 4);

  static Future<void> initialize() async {
    try {
      await MobileAds.instance.initialize();
      debugPrint('AdMob initialized');
    } catch (e) {
      debugPrint('AdMob init warning: $e');
    }
  }

  /// Preloads interstitial ad for free tier
  void preloadInterstitial() {
    if (_isInterstitialLoading || _interstitialAd != null) return;
    _isInterstitialLoading = true;

    // Use live unit id or test unit id in debug mode
    final adUnitId = kDebugMode ? Env.admobTestInterstitialId : Env.admobInterstitialUnitId;

    InterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialLoading = false;
          _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _interstitialAd = null;
              preloadInterstitial();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _interstitialAd = null;
              preloadInterstitial();
            },
          );
        },
        onAdFailedToLoad: (error) {
          debugPrint('Interstitial failed to load: $error');
          _interstitialAd = null;
          _isInterstitialLoading = false;
        },
      ),
    );
  }

  /// Shows interstitial after receipt share with 4-min cooldown
  /// Never shows if isPro is true!
  void showInterstitialIfEligible({required bool isPro}) {
    if (isPro) return;

    final now = DateTime.now();
    if (_lastInterstitialShownAt != null &&
        now.difference(_lastInterstitialShownAt!) < _cooldownDuration) {
      debugPrint('AdMob: Interstitial suppressed due to 4-minute cooldown.');
      return;
    }

    if (_interstitialAd != null) {
      _lastInterstitialShownAt = now;
      _interstitialAd!.show();
    } else {
      preloadInterstitial();
    }
  }

  /// Helper to create and load a BannerAd
  BannerAd createBannerAd({
    required bool isPro,
    required VoidCallback onLoaded,
  }) {
    final adUnitId = kDebugMode ? Env.admobTestBannerId : Env.admobBannerUnitId;
    return BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) => onLoaded(),
        onAdFailedToLoad: (ad, error) {
          debugPrint('Banner ad failed to load: $error');
          ad.dispose();
        },
      ),
    );
  }
}
