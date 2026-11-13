import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'save.dart';

/// ---------------------------------------------------------------------------
/// Google Play products. Create these as IN-APP PRODUCTS in Play Console
/// (Store presence → Products → In-app products) with EXACTLY these ids:
///
///   arrows_coins_100    — consumable   — 100 coins
///   arrows_coins_550    — consumable   — 550 coins
///   arrows_coins_1200   — consumable   — 1200 coins
///   arrows_coins_3000   — consumable   — 3000 coins
///   arrows_remove_ads   — non-consumable
///
/// Until the products exist in Play Console the shop shows prices as
/// unavailable — the rest of the game keeps working normally.
/// ---------------------------------------------------------------------------
class BillingConfig {
  static const String coinsSmall = 'arrows_coins_100';
  static const String coinsMedium = 'arrows_coins_550';
  static const String coinsLarge = 'arrows_coins_1200';
  static const String coinsMega = 'arrows_coins_3000';
  static const String removeAds = 'arrows_remove_ads';

  static const List<String> allIds = [
    coinsSmall,
    coinsMedium,
    coinsLarge,
    coinsMega,
    removeAds,
  ];

  static const Map<String, int> coinsFor = {
    coinsSmall: 100,
    coinsMedium: 550,
    coinsLarge: 1200,
    coinsMega: 3000,
  };
}

/// Central Google Play Billing facade. Fail-safe: billing problems never
/// block the game; the shop simply shows products as unavailable.
class Billing {
  static final Billing instance = Billing._();

  Billing._();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// Products fetched from Google Play (empty until the store responds).
  final ValueNotifier<List<ProductDetails>> products =
      ValueNotifier<List<ProductDetails>>([]);

  /// Set while a store round-trip is in flight.
  final ValueNotifier<bool> loading = ValueNotifier<bool>(false);

  /// Bumped after every purchase/restore so the UI can rebuild + show snackbars.
  final ValueNotifier<String?> message = ValueNotifier<String?>(null);

  bool _available = false;
  bool get available => _available;

  /// Fires when a purchase succeeded (coins granted / ads removed) — used by
  /// the shop to celebrate.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Future<void> init() async {
    try {
      _available = await _iap.isAvailable();
    } catch (_) {
      _available = false;
    }
    if (!_available) return;

    try {
      _sub = _iap.purchaseStream.listen(
        _onPurchases,
        onDone: () => _sub?.cancel(),
        onError: (_) {},
      );
      await queryProducts();
    } catch (_) {
      _available = false;
    }
  }

  Future<void> queryProducts() async {
    if (!_available) return;
    loading.value = true;
    try {
      final res = await _iap.queryProductDetails(BillingConfig.allIds.toSet());
      products.value = res.productDetails;
      // Not-found products simply stay absent (e.g. not yet created in
      // Play Console) — nothing to do, the shop shows a hint instead.
    } catch (_) {
      products.value = [];
    }
    loading.value = false;
  }

  Future<void> buy(ProductDetails p) async {
    if (!_available) return;
    try {
      final isCoins = BillingConfig.coinsFor.containsKey(p.id);
      final param = PurchaseParam(productDetails: p);
      if (isCoins) {
        // autoConsume:false → we consume AFTER granting coins, so a crash
        // between purchase and grant never eats the player's money.
        await _iap.buyConsumable(purchaseParam: param, autoConsume: false);
      } else {
        await _iap.buyNonConsumable(purchaseParam: param);
      }
    } catch (_) {
      message.value = 'Purchase could not start — is Google Play up to date?';
    }
  }

  Future<void> restore() async {
    if (!_available) {
      message.value = 'Google Play Billing is not available on this device.';
      return;
    }
    try {
      await _iap.restorePurchases();
    } catch (_) {
      message.value = 'Restore failed — try again later.';
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    bool changed = false;
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (p.productID == BillingConfig.removeAds) {
            if (!GameSave.instance.adsRemoved) {
              GameSave.instance.setAdsRemoved(true);
              changed = true;
              message.value =
                  p.status == PurchaseStatus.restored
                      ? 'Ads removed restored — thank you!'
                      : 'Ads removed — thank you for supporting Arrows!';
            }
          } else if (BillingConfig.coinsFor.containsKey(p.productID)) {
            final coins = BillingConfig.coinsFor[p.productID]!;
            GameSave.instance.addCoins(coins);
            changed = true;
            message.value = p.status == PurchaseStatus.restored
                ? null // consumables are never restored — unreachable
                : '+$coins coins added!';
            // Consume AFTER granting so coins can never be lost.
            if (p is GooglePlayPurchaseDetails) {
              try {
                final addition = _iap
                    .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
                await addition.consumePurchase(p);
              } catch (_) {}
            }
          }
          if (p.pendingCompletePurchase) {
            try {
              await _iap.completePurchase(p);
            } catch (_) {}
          }
          break;
        case PurchaseStatus.error:
          message.value = 'Purchase failed: ${p.error?.message ?? 'try again'}';
          break;
        case PurchaseStatus.canceled:
          message.value = 'Purchase canceled.';
          break;
        case PurchaseStatus.pending:
          message.value = 'Purchase pending — coins arrive once Google confirms.';
          break;
      }
    }
    if (changed) revision.value++;
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
