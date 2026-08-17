import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../l10n.dart';
import '../donations.dart';
import '../models.dart';
import '../theme.dart';
import '../update_gate.dart';
import '../widgets.dart';

class DonateScreen extends StatefulWidget {
  const DonateScreen({super.key, required this.api, required this.donations});

  final Api api;
  final DonationGateway donations;

  @override
  State<DonateScreen> createState() => _DonateScreenState();
}

class _DonateScreenState extends State<DonateScreen> {
  StreamSubscription<DonationResult>? _sub;
  String? _busyTier;
  bool _thanks = false;
  String? _error;

  /// Set when the browser has the payment and we genuinely do not know the
  /// outcome yet. Distinct from [_thanks], which claims the money arrived.
  bool _handedOff = false;

  /// The server answered 503 - this provider is not configured yet. Tipping is
  /// hidden rather than shown as a failure, because it is not one.
  String? _unavailable;

  @override
  void initState() {
    super.initState();
    _sub = widget.donations.results.listen((r) {
      if (!mounted) return;
      setState(() {
        _busyTier = null;
        if (r.unavailable) {
          _unavailable = r.error;
          _error = null;
        } else if (r.ok) {
          _thanks = true;
          _handedOff = false;
          _error = null;
        } else if (r.pending) {
          _handedOff = true;
          _error = null;
        } else if (r.error != null) {
          _error = r.error;
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _donate(DonationTier tier) async {
    setState(() {
      _busyTier = tier.id;
      _error = null;
    });

    final result = await widget.donations.donate(tier);
    if (!mounted) return;

    // On store rails the real outcome arrives on the stream, so only settle
    // here for the Stripe rail or an outright failure.
    if (DonationGateway.rail == DonationRail.stripe || result.error != null) {
      setState(() {
        _busyTier = null;
        if (result.unavailable) {
          _unavailable = result.error;
          _error = null;
          return;
        }
        if (result.ok) _thanks = true;
        // Stripe hands off to the browser: the webhook, not the app, decides
        // whether money moved. Saying "thanks" here would be a guess.
        _handedOff = result.pending;
        _error = result.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rail = DonationGateway.rail;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 34),
        children: [
          BrandHeader(title: L10n.of(context)['supportTitle'],
              subtitle: L10n.of(context)['supportSub']),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Entrance(index: 0, child: const _PitchCard()),
                const SizedBox(height: 22),

                if (_thanks) ...[
                  Entrance(index: 0, child: const _ThanksCard()),
                  const SizedBox(height: 20),
                ],

                if (_handedOff) ...[
                  BrutalBox(
                    color: Brutal.cyan,
                    dx: 3,
                    dy: 3,
                    padding: const EdgeInsets.all(13),
                    child: Text(
                      L10n.of(context)['donateInBrowser'],
                      style: Brutal.body.copyWith(fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],

                if (_error != null) ...[
                  BrutalBox(
                    color: Brutal.danger,
                    dx: 3,
                    dy: 3,
                    padding: const EdgeInsets.all(13),
                    child: Text(_error!, style: Brutal.body.copyWith(fontSize: 14)),
                  ),
                  const SizedBox(height: 18),
                ],

                // 503 from the server means this payment provider is not
                // switched on yet. Showing tip buttons that cannot work is
                // worse than showing none, so they come out entirely.
                if (_unavailable != null) ...[
                  BrutalBox(
                    color: Brutal.paperDeep,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          L10n.of(context)['donateSoonTitle'],
                          style: Brutal.label.copyWith(fontSize: 14),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          L10n.of(context)['donateSoonBody'],
                          style: Brutal.body.copyWith(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ] else ...[
                  for (var i = 0; i < kDonationTiers.length; i++) ...[
                    Entrance(
                      index: i + 1,
                      child: _TierCard(
                        tier: kDonationTiers[i],
                        accent: Brutal.accentFor(i),
                        // A tier the store has not returned cannot be charged,
                        // so it shows a dash and does not respond to taps -
                        // rather than advertising our hardcoded euro amount and
                        // then failing when the store has no such product.
                        available: widget.donations.hasProduct(kDonationTiers[i]),
                        price: widget.donations.priceFor(kDonationTiers[i]),
                        busy: _busyTier == kDonationTiers[i].id,
                        onTap: () => _donate(kDonationTiers[i]),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  const SizedBox(height: 10),
                  _RailNote(rail: rail),
                  // Why the amounts are not round numbers. Play grosses the
                  // price up by local VAT and then rounds to its own price
                  // points, so the tiers read 2.39 / 2.49 rather than 2.00 -
                  // which looks like a bug unless someone says otherwise.
                  if (rail == DonationRail.store) ...[
                    const SizedBox(height: 10),
                    _PriceNote(),
                  ],
                ],
                const SizedBox(height: 26),
                // Play and Apple both expect the privacy policy and terms to be
                // reachable from inside the app, not only from the store listing.
                const _LegalLinks(),
                VersionFooter(api: widget.api),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PitchCard extends StatelessWidget {
  const _PitchCard();

  @override
  Widget build(BuildContext context) {
    return BrutalBox(
      color: Brutal.orange,
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset(
            'assets/img/logo.png',
            width: 72,
            errorBuilder: (_, _, _) => const SizedBox(width: 72),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('THIS RUNS ON A\nRASPBERRY PI', style: Brutal.display.copyWith(fontSize: 24)),
                const SizedBox(height: 8),
                Text(
                  'No ads. No tracking. No accounts. Just a very small computer '
                  'in a cupboard, archiving humanity’s worst decisions.',
                  style: Brutal.body.copyWith(fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThanksCard extends StatelessWidget {
  const _ThanksCard();

  @override
  Widget build(BuildContext context) {
    return BrutalBox(
      color: Brutal.lime,
      rotation: -0.015,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Text('😻', style: TextStyle(fontSize: 46)),
          const SizedBox(height: 8),
          Text('CERTIFIED LEGEND', style: Brutal.display.copyWith(fontSize: 26)),
          const SizedBox(height: 5),
          Text(
            'The Pi thanks you. It will keep going.',
            textAlign: TextAlign.center,
            style: Brutal.body.copyWith(fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.tier,
    required this.accent,
    required this.price,
    required this.busy,
    required this.onTap,
    this.available = true,
  });

  final DonationTier tier;
  final Color accent;
  final String price;
  final bool busy;
  final VoidCallback onTap;

  /// False when the store has no such product - unpriced, inactive, or still
  /// propagating after being created in the console.
  final bool available;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy || !available ? null : onTap,
      child: BrutalBox(
        color: available ? accent : Brutal.paperDeep,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Text(tier.emoji, style: const TextStyle(fontSize: 34)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tier.label.toUpperCase(), style: Brutal.label.copyWith(fontSize: 15)),
                  const SizedBox(height: 3),
                  Text(tier.blurb, style: Brutal.body.copyWith(fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: Brutal.paper,
                border: Brutal.outline,
                boxShadow: Brutal.shadow(dx: 3, dy: 3),
              ),
              child: busy
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 3, color: Brutal.ink),
                    )
                  : Text(available ? price : '—',
                      style: Brutal.display.copyWith(fontSize: 19)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tells the user - honestly - where their money actually goes on this platform.
/// Explains the odd tier prices, in the same quiet grey as the rail note.
class _PriceNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.receipt_long_outlined, size: 15, color: Brutal.ink.withValues(alpha: 0.55)),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            L10n.of(context)['priceNote'],
            style: Brutal.body.copyWith(fontSize: 12, color: Brutal.ink.withValues(alpha: 0.6)),
          ),
        ),
      ],
    );
  }
}

class _RailNote extends StatelessWidget {
  const _RailNote({required this.rail});

  final DonationRail rail;

  @override
  Widget build(BuildContext context) {
    final text = rail == DonationRail.store
        ? 'Handled by the App Store / Google Play. They take their cut before it '
              'reaches the Pi — that is their rule, not ours.'
        : 'Handled by Stripe in your browser. Card details never touch this app.';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          rail == DonationRail.store ? Icons.lock_outline : Icons.open_in_new,
          size: 15,
          color: Brutal.ink.withValues(alpha: 0.55),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: Brutal.body.copyWith(fontSize: 12, color: Brutal.ink.withValues(alpha: 0.6)),
          ),
        ),
      ],
    );
  }
}


/// Links out to the policy pages on the website. They are plain HTML, not API
/// endpoints, so this deliberately opens a browser rather than fetching them.
class _LegalLinks extends StatelessWidget {
  const _LegalLinks();

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in [
          (t['legalPrivacy'], Links.privacy),
          (t['legalTerms'], Links.terms),
          (t['legalWebsite'], Links.website),
        ]) ...[
          GestureDetector(
            onTap: () => _open(item.$2),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Brutal.ink, width: 2)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(item.$1, style: Brutal.body.copyWith(fontSize: 15)),
                  ),
                  Icon(Icons.open_in_new, size: 15, color: Brutal.ink.withValues(alpha: 0.6)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
