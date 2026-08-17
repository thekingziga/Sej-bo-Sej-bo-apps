import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
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
  const DonationResult.success(this.tier)
    : cancelled = false,
      error = null,
      pending = false,
      unavailable = false;
  const DonationResult.cancelled()
    : tier = null,
      cancelled = true,
      error = null,
      pending = false,
      unavailable = false;
  const DonationResult.failure(this.error)
    : tier = null,
      cancelled = false,
      pending = false,
      unavailable = false;

  /// Handed off to the browser. The payment has not happened yet and may never
  /// happen - claiming success here would be a lie, since the user can still
  /// close the tab.
  const DonationResult.handedOff(this.tier)
    : cancelled = false,
      error = null,
      pending = true,
      unavailable = false;

  /// The server has not been configured for this payment provider (503). Not
  /// the user's fault and not worth an angry red box - the UI hides tipping.
  const DonationResult.notAvailable(this.error)
    : tier = null,
      cancelled = false,
      pending = false,
      unavailable = true;

  final DonationTier? tier;
  final bool cancelled;
  final String? error;
  final bool pending;
  final bool unavailable;

  bool get ok => tier != null && !pending;
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

  /// The store's own record for a tier, or null when it has not returned one.
  ///
  /// Null is normal and not an error: the product may be unpriced, inactive, or
  /// still propagating after being created in Play Console.
  ProductDetails? productFor(DonationTier tier) {
    for (final p in _products) {
      if (p.id == tier.storeProductId) return p;
    }
    return null;
  }

  /// True when the store can actually sell this tier.
  bool hasProduct(DonationTier tier) => !supportsStoreBilling || productFor(tier) != null;

  /// Store-reported localised price, e.g. "€4,99".
  ///
  /// Falls back to our own label only where there is no store to ask - on the
  /// Stripe rail. On a store rail an unknown price means the tier is not
  /// purchasable, and showing our hardcoded number there would advertise a
  /// price we cannot honour: exactly what happened when Play returned only one
  /// of the three products and the other two displayed stale euro amounts.
  String priceFor(DonationTier tier) => productFor(tier)?.price ?? tier.display;

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

    // After the listener is attached, so anything it turns up is handled.
    await _replayUnfinished();
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          // Nothing to do - a slow card or a parent-approval flow. The store
          // will deliver it again when it resolves.
          break;
        case PurchaseStatus.canceled:
          _controller.add(const DonationResult.cancelled());
        case PurchaseStatus.error:
          _controller.add(DonationResult.failure(p.error?.message ?? 'Purchase failed.'));
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verifyThenFinish(p);
      }
    }
  }

  /// Verify with our server, and only then tell the store we are done.
  ///
  /// The order is the whole point. Finishing a transaction is irreversible and
  /// tells the store the user got what they paid for, so it has to come after
  /// the receipt has actually been checked - otherwise a forged or failed
  /// purchase is accepted permanently.
  ///
  /// When verification fails the transaction is deliberately left unfinished:
  ///
  /// - a `400` receipt is invalid, and leaving it unfinished lets Google
  ///   auto-refund it after three days, which is the correct outcome;
  /// - a transient failure (429, 5xx, offline, 503) gets replayed on the next
  ///   launch by [_replayUnfinished], so a real tip is not lost to a blip.
  ///
  /// The risk this trades against is a genuine tip sitting unverified for more
  /// than three days of server downtime, which Google would then refund. That
  /// is strictly better than acknowledging money we never recorded.
  Future<void> _verifyThenFinish(PurchaseDetails p) async {
    final tier = _tierForProduct(p.productID);
    try {
      await _api.verifyStorePurchase(
        platform: (!kIsWeb && Platform.isAndroid) ? 'google' : 'apple',
        productId: p.productID,
        token: p.verificationData.serverVerificationData,
      );
    } on ApiException catch (e) {
      if (e.statusCode == 503) {
        _controller.add(DonationResult.notAvailable(e.message));
      } else {
        _controller.add(DonationResult.failure(e.message));
      }
      return; // Unfinished on purpose. See above.
    } catch (e) {
      _controller.add(DonationResult.failure('Could not confirm your tip: $e'));
      return;
    }

    await _finish(p);
    if (tier != null) _controller.add(DonationResult.success(tier));
  }

  /// Tells the store the transaction is done.
  ///
  /// On Android a tip has to be **consumed**, not merely acknowledged:
  /// acknowledging satisfies the three-day refund rule but leaves the product
  /// owned, so the user could never tip the same amount twice. Consuming does
  /// both. On Apple platforms finishing the transaction is all there is.
  Future<void> _finish(PurchaseDetails p) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final addition =
            InAppPurchasePlatformAddition.instance! as InAppPurchaseAndroidPlatformAddition;
        await addition.consumePurchase(p);
      } catch (_) {
        // Fall through to completePurchase, which at least acknowledges and so
        // stops the refund clock.
      }
    }
    if (p.pendingCompletePurchase) {
      try {
        await _iap.completePurchase(p);
      } catch (_) {
        // Already consumed on Android: acknowledging afterwards is rejected,
        // and harmlessly so.
      }
    }
  }

  /// Picks up anything paid for but never finished - the app killed between
  /// paying and verifying, or a server outage during the last attempt.
  ///
  /// Safe to run on every launch: the server ignores duplicate tokens, so a
  /// replayed purchase is recorded once and never double-counted.
  Future<void> _replayUnfinished() async {
    try {
      await _iap.restorePurchases();
    } catch (_) {
      // Nothing to restore, or the store refused. Not worth surfacing.
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
    // Not `firstWhere(orElse: throw)`: a tier the store has not returned is an
    // ordinary situation - the product is unpriced, inactive, or still
    // propagating - and it used to throw a StateError out of an un-awaited
    // path, which surfaced as a crash rather than a message.
    final product = productFor(tier);
    if (product == null) {
      return const DonationResult.failure(
        'That tip is not available from the store right now.',
      );
    }
    try {
      await _iap.buyConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
        // MUST stay false. With autoConsume the plugin consumes the purchase
        // inside its own pipeline, before our listener runs - so the store
        // would be told the transaction is finished before the server had
        // verified the receipt. _finish() consumes explicitly instead.
        autoConsume: false,
      );
      // The sheet is up; the real outcome arrives on [results].
      return const DonationResult.cancelled();
    } catch (e) {
      return DonationResult.failure('Could not open the store sheet: $e');
    }
  }

  Future<DonationResult> _donateViaStripe(DonationTier tier) async {
    try {
      final url = await _api.createStripeCheckout(tierId: tier.id);
      // System browser, never a webview: Stripe blocks some payment methods in
      // embedded webviews and 3-D Secure often fails there.
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok) return const DonationResult.failure('Could not open the browser.');
      // Handed off, not paid. Stripe tells the server via webhook; there is
      // nothing to poll and the user can still close the tab.
      return DonationResult.handedOff(tier);
    } on ApiException catch (e) {
      if (e.statusCode == 503) return DonationResult.notAvailable(e.message);
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
