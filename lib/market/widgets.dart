import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets.dart';
import 'models.dart';

/// The marketplace's visual pieces, ported from the website's own CSS so a
/// listing looks like the same object in both places: the yellow price tag,
/// the rotated red SOLD stamp over a greyed photo, the dashed offer card that
/// turns green when accepted, cyan bubbles for your own messages.

/// The site's price wording: an amount, "free", or "make an offer".
String marketPrice(Strings t, int? cents) {
  if (cents == null) return t['marketPriceOffer'];
  if (cents == 0) return t['marketFree'];
  return Money.format(cents, t.code);
}

/// The website's pure yellow (`--hot: #ff0`). Brutal.yellow is warmer, but the
/// price tag and the offer card are the site's two loudest things and should
/// read as the same colour in both places.
const kHot = Color(0xFFFFFF00);
const _soldRed = Color(0xFFDD0000);
const _accepted = Color(0xFF88FF88);
const _dead = Color(0xFFDDDDDD);

class PriceTag extends StatelessWidget {
  const PriceTag({super.key, required this.cents, this.large = false});

  final int? cents;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 14 : 8, vertical: large ? 4 : 1),
      decoration: BoxDecoration(
        color: kHot,
        border: Border.all(color: Brutal.ink, width: 2),
        boxShadow: large ? Brutal.shadow(dx: 4, dy: 4) : null,
      ),
      child: Text(
        marketPrice(t, cents),
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: large ? 30 : 16,
          color: Brutal.ink,
          height: 1.15,
        ),
      ),
    );
  }
}

/// The rubber stamp from the site: rotated, red, over the photo rather than
/// instead of it - a sold thing is still worth looking at, just not worth
/// messaging about.
class SoldStamp extends StatelessWidget {
  const SoldStamp({super.key, this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    return Transform.rotate(
      angle: -14 * math.pi / 180,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: size * 0.6, vertical: size * 0.1),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          border: Border.all(color: _soldRed, width: size < 30 ? 3 : 5),
        ),
        child: Text(
          t['marketSold'],
          style: TextStyle(
            color: _soldRed,
            fontSize: size,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

/// CSS `grayscale(0.7)`, which is what the site puts on a sold listing's photo.
const _soldFilter = ColorFilter.matrix(<double>[
  0.2126 + 0.7874 * 0.3, 0.7152 - 0.7152 * 0.3, 0.0722 - 0.0722 * 0.3, 0, 0,
  0.2126 - 0.2126 * 0.3, 0.7152 + 0.2848 * 0.3, 0.0722 - 0.0722 * 0.3, 0, 0,
  0.2126 - 0.2126 * 0.3, 0.7152 - 0.7152 * 0.3, 0.0722 + 0.9278 * 0.3, 0, 0,
  0, 0, 0, 1, 0,
]);

/// A listing's photo, greyed and stamped when sold. Draws a placeholder for a
/// missing or broken image rather than an error icon - demo listings have no
/// photo at all, and a dead link on one tile should not look like a crash.
class ListingPhoto extends StatelessWidget {
  const ListingPhoto({
    super.key,
    required this.url,
    required this.sold,
    required this.seed,
    this.fit = BoxFit.cover,
    this.stampSize = 22,
  });

  final String? url;
  final bool sold;

  /// Picks the placeholder colour, so neighbouring tiles differ.
  final int seed;
  final BoxFit fit;
  final double stampSize;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: Brutal.accentFor(seed),
      alignment: Alignment.center,
      child: Icon(Icons.sell_outlined, size: 40, color: Brutal.ink.withValues(alpha: 0.55)),
    );
    Widget image = (url ?? '').isEmpty
        ? placeholder
        : Image.network(
            url!,
            fit: fit,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, _, _) => placeholder,
            loadingBuilder: (_, child, progress) =>
                progress == null ? child : Container(color: Brutal.paperDeep),
          );
    if (sold) image = ColorFiltered(colorFilter: _soldFilter, child: image);
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        if (sold) Center(child: SoldStamp(size: stampSize)),
      ],
    );
  }
}

/// A tile in the marketplace grid.
class ListingCard extends StatelessWidget {
  const ListingCard({super.key, required this.listing, required this.onTap});

  final Listing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: Brutal.paper,
          border: Brutal.outline,
          boxShadow: Brutal.shadow(dx: 4, dy: 4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Brutal.ink, width: Brutal.border)),
                ),
                child: ListingPhoto(url: listing.imageUrl, sold: listing.isSold, seed: listing.id),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 4, 9, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PriceTag(cents: listing.priceCents),
                  const SizedBox(height: 6),
                  Text(
                    listing.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Brutal.heading.copyWith(fontSize: 15),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The pink pill from the site's nav.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Brutal.pink,
        border: Border.all(color: Brutal.ink, width: 2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Brutal.ink),
      ),
    );
  }
}

/// A back button and a title - the marketplace's screens all start with it.
class MarketTopBar extends StatelessWidget {
  const MarketTopBar({super.key, required this.title, this.actions = const []});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: Brutal.paper,
                border: Brutal.outline,
                boxShadow: Brutal.shadow(dx: 3, dy: 3),
              ),
              child: const Icon(Icons.arrow_back, size: 20),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Brutal.label.copyWith(fontSize: 14)),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// A message, in the site's bubble style. Offers render as the dashed card
/// inside it, with the answer buttons only when this person may answer.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.listingActive,
    this.onAnswer,
    this.busy = false,
  });

  final MarketMessage message;
  final bool listingActive;

  /// Called with true for accept, false for decline.
  final ValueChanged<bool>? onAnswer;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final mine = message.mine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: 0.82,
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
            decoration: BoxDecoration(
              color: mine ? Brutal.cyan : Brutal.paper,
              border: Brutal.outline,
              boxShadow: Brutal.shadow(dx: 3, dy: 3),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.body.isNotEmpty)
                  Text(message.body, style: Brutal.body.copyWith(fontSize: 16)),
                if (message.isOffer) ...[
                  if (message.body.isNotEmpty) const SizedBox(height: 6),
                  OfferCard(
                    message: message,
                    canAnswer: onAnswer != null && message.canAnswer(listingActive: listingActive),
                    busy: busy,
                    onAnswer: onAnswer,
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  relativeDate(message.createdAt),
                  style: Brutal.body.copyWith(fontSize: 12, color: Brutal.ink.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OfferCard extends StatelessWidget {
  const OfferCard({
    super.key,
    required this.message,
    required this.canAnswer,
    this.onAnswer,
    this.busy = false,
  });

  final MarketMessage message;
  final bool canAnswer;
  final ValueChanged<bool>? onAnswer;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final status = message.offerStatus;
    final dead = status == OfferStatus.declined || status == OfferStatus.superseded;
    final color = switch (status) {
      OfferStatus.accepted => _accepted,
      OfferStatus.declined || OfferStatus.superseded => _dead,
      _ => kHot,
    };
    final statusText = switch (status) {
      OfferStatus.accepted => t['offerAccepted'],
      OfferStatus.declined => t['offerDeclined'],
      OfferStatus.superseded => t['offerSuperseded'],
      _ => t['offerPending'],
    };
    final strike = dead ? TextDecoration.lineThrough : null;

    return CustomPaint(
      painter: _DashedBorder(),
      child: Container(
        color: color,
        margin: const EdgeInsets.all(1.5),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t['offerLabel'].toUpperCase(), style: Brutal.label.copyWith(fontSize: 11, decoration: strike)),
            Text(
              Money.format(message.offerCents!, t.code),
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Brutal.ink, decoration: strike),
            ),
            Text(statusText, style: Brutal.body.copyWith(fontSize: 13, decoration: strike)),
            if (canAnswer) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  BrutalButton(
                    color: _accepted,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    onPressed: busy ? null : () => onAnswer?.call(true),
                    child: Text(t['offerAccept'], style: Brutal.label.copyWith(fontSize: 12)),
                  ),
                  BrutalButton(
                    color: Brutal.paper,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    onPressed: busy ? null : () => onAnswer?.call(false),
                    child: Text(t['offerDecline'], style: Brutal.label.copyWith(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The site's `3px dashed #000`, which Flutter's BoxDecoration cannot draw.
class _DashedBorder extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Brutal.ink
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    const dash = 7.0, gap = 5.0;
    final r = Rect.fromLTWH(1.5, 1.5, size.width - 3, size.height - 3);
    for (final (a, b) in [
      (r.topLeft, r.topRight),
      (r.topRight, r.bottomRight),
      (r.bottomRight, r.bottomLeft),
      (r.bottomLeft, r.topLeft),
    ]) {
      final length = (b - a).distance;
      final dir = (b - a) / length;
      for (var d = 0.0; d < length; d += dash + gap) {
        canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, length), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Asks yes or no, in the app's style. Returns false when dismissed.
Future<bool> confirmBrutal(BuildContext context, String message, {bool danger = false}) async {
  final t = L10n.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: BrutalBox(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message, style: Brutal.body.copyWith(fontSize: 17)),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: BrutalButton(
                    color: Brutal.paper,
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Center(child: Text(t['confirmNo'], style: Brutal.label)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: BrutalButton(
                    color: danger ? Brutal.danger : Brutal.yellow,
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: Center(child: Text(t['confirmYes'], style: Brutal.label)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return ok ?? false;
}

/// Reports a listing or a conversation. The reasons are the marketplace's
/// five, not the feed's, so this is its own small sheet; [submit] does the
/// sending and throws on failure, which is shown in the sheet.
Future<void> showMarketReportSheet(
  BuildContext context, {
  required String title,
  required Future<void> Function(MarketReportReason reason, String details) submit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MarketReportSheet(title: title, submit: submit),
  );
}

class _MarketReportSheet extends StatefulWidget {
  const _MarketReportSheet({required this.title, required this.submit});

  final String title;
  final Future<void> Function(MarketReportReason reason, String details) submit;

  @override
  State<_MarketReportSheet> createState() => _MarketReportSheetState();
}

class _MarketReportSheetState extends State<_MarketReportSheet> {
  MarketReportReason? _reason;
  final _details = TextEditingController();
  bool _sending = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.submit(reason, _details.text);
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final reasons = {
      MarketReportReason.scam: t['marketReasonScam'],
      MarketReportReason.prohibited: t['marketReasonProhibited'],
      MarketReportReason.spam: t['marketReasonSpam'],
      MarketReportReason.harassment: t['marketReasonHarassment'],
      MarketReportReason.other: t['marketReasonOther'],
    };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Brutal.paper,
          border: Border(top: BorderSide(color: Brutal.ink, width: 4)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            child: _done
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(t['marketReported'], style: Brutal.body.copyWith(fontSize: 17)),
                      const SizedBox(height: 16),
                      BrutalButton(
                        color: Brutal.yellow,
                        onPressed: () => Navigator.of(context).pop(),
                        child: Center(child: Text('OK', style: Brutal.label)),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(widget.title.toUpperCase(), style: Brutal.label.copyWith(fontSize: 15)),
                      const SizedBox(height: 12),
                      for (final e in reasons.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GestureDetector(
                            onTap: () => setState(() => _reason = e.key),
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                              decoration: BoxDecoration(
                                color: _reason == e.key ? Brutal.yellow : Brutal.paper,
                                border: Brutal.outline,
                              ),
                              child: Text(e.value, style: Brutal.body.copyWith(fontSize: 16)),
                            ),
                          ),
                        ),
                      const SizedBox(height: 6),
                      BrutalField(
                        label: t['reportDetails'],
                        hint: t['reportDetailsHint'],
                        controller: _details,
                        maxLength: 500,
                        maxLines: 3,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(_error!, style: Brutal.body.copyWith(color: Brutal.danger)),
                      ],
                      const SizedBox(height: 14),
                      BrutalButton(
                        color: _reason == null ? Brutal.paperDeep : Brutal.danger,
                        onPressed: _reason == null || _sending ? null : _send,
                        child: Center(
                          child: _sending
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 3))
                              : Text(t['reportSend'], style: Brutal.label),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// A full-width panel for "this needs the website" and "this is switched off".
class MarketNotice extends StatelessWidget {
  const MarketNotice({super.key, required this.title, required this.body, this.action});

  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return BrutalBox(
      color: Brutal.cyan,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Brutal.label.copyWith(fontSize: 15)),
          const SizedBox(height: 8),
          Text(body, style: Brutal.body.copyWith(fontSize: 15)),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}

/// What to tell a person about a failed marketplace call. The server's own
/// message is already localised and is shown as it came, except for the three
/// conditions that are about the app's state rather than the request.
String marketError(Strings t, Object e) {
  if (e is ApiException) {
    if (e.code == 'unavailable') return t['marketUnavailableBody'];
    if (e.code == 'unconfigured' || e.statusCode == 503) return t['marketOffline'];
    if (e.code == 'unauthorized') return t['sessionEnded'];
    return e.message;
  }
  return '$e';
}
