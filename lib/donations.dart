import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'models.dart';

/// Why this class exists, in one paragraph:
///
/// Apple and Google both require that anything which looks like a digital tip
/// to the developer goes through their own billing (StoreKit / Play Billing).
/// Linking out to Stripe from inside the iOS or Android app is a review
/// rejection, not a grey area. So mobile uses store billing and takes the 15-30%
/// cut, while Windows - which has no such gatekeeper - uses Stripe Checkout and
/// keeps ~97%. Same UI, two completely different money paths underneath.
enum DonationRail { store, stripe }

class DonationResult {
  const DonationResult.success(this.tier) : cancelled = false, error = null;
  const DonationResult.cancelled() : tier = null, cancelled = true, error = null;
  const DonationResult.failure(this.error) : tier = null, cancelled = false;

  final DonationTier? tier;
  final bool cancelled;
  final String? error;

  bool get ok => tier != null;
}

class DonationGateway {
  DonationGateway(this._api);

  final Api _api;
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  final _controller = StreamController<DonationResult>.broadcast();
  Stream<DonationResult> get results => _controller.stream;

  List<ProductDetails> _products = const [];
  bool _available = false;

  /// True only where an app-store billing implementation actually exists.
  static bool get supportsStoreBilling {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isAndroid || Platform.isMacOS;
  }

  static DonationRail get rail => supportsStoreBilling ? DonationRail.store : DonationRail.stripe;

  /// Store-reported localised price, e.g. "€4,99". Falls back to our own label
  /// when the store has not been queried or the product is not configured yet.
  String priceFor(DonationTier tier) {
    for (final p in _products) {
      if (p.id == tier.storeProductId) return p.price;
    }
    return tier.display;
  }

  bool get storeReady => _available && _products.isNotEmpty;

  Future<void> init() async {
    if (!supportsStoreBilling) return;

    try {
      _available = await _iap.isAvailable();
    } catch (_) {
      _available = false;
    }
    if (!_available) return;

    _sub = _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) {
        _controller.add(DonationResult.failure('Store error: $e'));
      },
    );

    try {
      final resp = await _iap.queryProductDetails(
        kDonationTiers.map((t) => t.storeProductId).toSet(),
      );
      _products = resp.productDetails;
    } catch (_) {
      _products = const [];
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          break;
        case PurchaseStatus.canceled:
          _controller.add(const DonationResult.cancelled());
        case PurchaseStatus.error:
          _controller.add(DonationResult.failure(p.error?.message ?? 'Purchase failed.'));
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final tier = _tierForProduct(p.productID);
          // Server-side verification. Never trust the client for money.
          await _api.verifyStorePurchase(
            platform: (!kIsWeb && Platform.isAndroid) ? 'google' : 'apple',
            productId: p.productID,
            token: p.verificationData.serverVerificationData,
          );
          if (tier != null) _controller.add(DonationResult.success(tier));
      }

      // Tips are consumables: always complete, or the store will replay them
      // on every launch and block future purchases.
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
  }

  DonationTier? _tierForProduct(String productId) {
    for (final t in kDonationTiers) {
      if (t.storeProductId == productId) return t;
    }
    return null;
  }

  /// Kicks off a donation. On store rails this returns as soon as the sheet is
  /// presented - listen to [results] for the outcome. On the Stripe rail the
  /// browser takes over and the result arrives via webhook, not here.
  Future<DonationResult> donate(DonationTier tier) async {
    if (rail == DonationRail.stripe) return _donateViaStripe(tier);

    if (!storeReady) {
      return const DonationResult.failure(
        'Store products are not configured yet. See docs/DONATIONS.md.',
      );
    }
    final product = _products.firstWhere(
      (p) => p.id == tier.storeProductId,
      orElse: () => throw StateError('missing product'),
    );
    try {
      await _iap.buyConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
        // Android only; harmless elsewhere. Keeps repeat tipping possible.
        autoConsume: true,
      );
      return const DonationResult.cancelled(); // placeholder until stream fires
    } catch (e) {
      return DonationResult.failure('Could not open the store sheet: $e');
    }
  }

  Future<DonationResult> _donateViaStripe(DonationTier tier) async {
    try {
      final url = await _api.createStripeCheckout(tierId: tier.id);
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok) return const DonationResult.failure('Could not open the browser.');
      return DonationResult.success(tier);
    } on ApiException catch (e) {
      return DonationResult.failure(e.message);
    } catch (e) {
      return DonationResult.failure('Checkout failed: $e');
    }
  }

  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}
