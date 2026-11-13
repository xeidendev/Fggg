import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../core/ads.dart';
import '../core/audio.dart';
import '../core/billing.dart';
import '../core/save.dart';
import '../core/theme.dart';
import 'widgets.dart';

/// Coin shop (v5.0):
///  - Google Play coin packs (consumable IAPs)
///  - "Remove ads" (non-consumable IAP)
///  - Free coins via a rewarded ad
/// Everything degrades gracefully when billing is unavailable.
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  @override
  void initState() {
    super.initState();
    Billing.instance.revision.addListener(_onBillingChange);
    Billing.instance.message.addListener(_onBillingMessage);
    // Refresh the product list every time the shop opens.
    Billing.instance.queryProducts();
  }

  @override
  void dispose() {
    Billing.instance.revision.removeListener(_onBillingChange);
    Billing.instance.message.removeListener(_onBillingMessage);
    super.dispose();
  }

  void _onBillingChange() {
    if (!mounted) return;
    setState(() {});
  }

  void _onBillingMessage() {
    final msg = Billing.instance.message.value;
    if (!mounted || msg == null) return;
    Billing.instance.message.value = null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.ink,
        content: Text(msg, style: AppTheme.body(14, color: Colors.white)),
        duration: const Duration(milliseconds: 1800),
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final save = GameSave.instance;
    final billing = Billing.instance;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  RoundIcon(
                    icon: Icons.arrow_back_rounded,
                    onTap: () {
                      GameAudio.play('close');
                      Navigator.pop(context);
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Shop', style: AppTheme.display(24)),
                        Text(
                          'coins power hints & arrow styles',
                          style: AppTheme.body(13, color: AppTheme.inkSoft),
                        ),
                      ],
                    ),
                  ),
                  const SavedCoinPill(),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  // ---- free coins via rewarded ad ----
                  _Card(
                    color: AppTheme.green,
                    icon: Icons.movie_rounded,
                    title: 'FREE COINS',
                    subtitle:
                        'Watch a short video → +${AdConfig.rewardedCoins} coins, as often as you like.',
                    trailing: JuicyButton(
                      color: Colors.white,
                      height: 46,
                      width: 110,
                      enableSound: false,
                      onPressed: () => Ads.showRewarded(
                        context,
                        adLabel: 'free coins',
                        onReward: () {
                          GameSave.instance.addCoins(AdConfig.rewardedCoins);
                          GameAudio.playSynth('coin');
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: AppTheme.ink,
                              content: Text(
                                '+${AdConfig.rewardedCoins} coins — enjoy!',
                                style: AppTheme.body(14, color: Colors.white),
                              ),
                            ),
                          );
                        },
                      ),
                      child: Text('WATCH',
                          style: AppTheme.title(15, color: AppTheme.green)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // ---- remove ads ----
                  if (!save.adsRemoved)
                    _Card(
                      color: AppTheme.purple,
                      icon: Icons.block_rounded,
                      title: 'REMOVE ADS',
                      subtitle:
                          'No more banners or interstitials. Forever. Rewarded bonuses stay available.',
                      trailing: _PriceButton(
                        productId: BillingConfig.removeAds,
                        color: AppTheme.purple,
                      ),
                    )
                  else
                    _Card(
                      color: AppTheme.purple.withAlpha(140),
                      icon: Icons.verified_rounded,
                      title: 'ADS REMOVED',
                      subtitle: 'You own this — thanks for the support!',
                      trailing: const Icon(Icons.check_circle_rounded,
                          color: Colors.white, size: 34),
                    ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Text('Coin packs', style: AppTheme.title(18)),
                      const SizedBox(width: 8),
                      const Icon(Icons.bolt_rounded,
                          color: AppTheme.gold, size: 20),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (!billing.available && billing.products.value.isEmpty)
                    const _StoreUnavailableCard(),
                  ValueListenableBuilder<bool>(
                    valueListenable: billing.loading,
                    builder: (context, loading, _) => loading &&
                            billing.products.value.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(28),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : Column(
                            children: [
                              for (final p in billing.products.value)
                                if (BillingConfig.coinsFor.containsKey(p.id))
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _CoinPackTile(product: p),
                                  ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Payments are handled securely by Google Play. '
                    'Restore purchases after reinstalling to get "Remove ads" back.',
                    style: AppTheme.body(12, color: AppTheme.inkSoft),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => Billing.instance.restore(),
                      icon: const Icon(Icons.restore_rounded,
                          size: 18, color: AppTheme.inkSoft),
                      label: Text('Restore purchases',
                          style: AppTheme.body(14, color: AppTheme.inkSoft)),
                    ),
                  ),
                ],
              ),
            ),
            const AdBanner(),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(70),
            offset: const Offset(0, 8),
            blurRadius: 0.5,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: Colors.white, size: 22),
                    const SizedBox(width: 8),
                    Text(title,
                        style: AppTheme.display(17, color: Colors.white)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(subtitle,
                    style: AppTheme.body(13, color: Colors.white.withAlpha(230))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          trailing,
        ],
      ),
    );
  }
}

class _StoreUnavailableCard extends StatelessWidget {
  const _StoreUnavailableCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.paper,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.paperDark, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.storefront_rounded,
              color: AppTheme.inkSoft, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Google Play Billing is not available here.\n'
              'Coin packs appear automatically once the products are published in Play Console.',
              style: AppTheme.body(13, color: AppTheme.inkSoft),
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceButton extends StatelessWidget {
  const _PriceButton({required this.productId, required this.color});

  final String productId;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final billing = Billing.instance;
    ProductDetails? p;
    for (final pd in billing.products.value) {
      if (pd.id == productId) p = pd;
    }
    return JuicyButton(
      color: Colors.white,
      height: 46,
      width: 110,
      enableSound: false,
      onPressed: p == null
          ? null
          : () {
              GameAudio.play('click');
              Billing.instance.buy(p!);
            },
      child: Text(
        p?.price ?? '—',
        style: AppTheme.title(15, color: color),
      ),
    );
  }
}

class _CoinPackTile extends StatelessWidget {
  const _CoinPackTile({required this.product});

  final ProductDetails product;

  @override
  Widget build(BuildContext context) {
    final coins = BillingConfig.coinsFor[product.id] ?? 0;
    final bonus = coins >= 1200
        ? 'BEST VALUE'
        : coins >= 550
            ? 'POPULAR'
            : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x22241E33), offset: Offset(0, 4), blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          const _CoinBadgeBig(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$coins coins', style: AppTheme.display(18)),
                if (bonus != null)
                  Container(
                    margin: const EdgeInsets.only(top: 3),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.gold.withAlpha(40),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(bonus,
                        style: AppTheme.body(11,
                            color: const Color(0xFF9A6E00), w: FontWeight.w700)),
                  ),
              ],
            ),
          ),
          JuicyButton(
            color: AppTheme.gold,
            height: 44,
            width: 104,
            enableSound: false,
            onPressed: () {
              GameAudio.play('click');
              Billing.instance.buy(product);
            },
            child: Text(product.price,
                style: AppTheme.title(15, color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _CoinBadgeBig extends StatelessWidget {
  const _CoinBadgeBig();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: const BoxDecoration(
        color: AppTheme.gold,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFFFFD970),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFB27E00), width: 2.5),
          ),
        ),
      ),
    );
  }
}
