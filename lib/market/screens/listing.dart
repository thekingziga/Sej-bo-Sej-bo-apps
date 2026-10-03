import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../api.dart';
import '../../l10n.dart';
import '../../models.dart' show Links;
import '../../theme.dart';
import '../../widgets.dart';
import '../models.dart';
import '../session.dart';
import '../widgets.dart';
import 'chat.dart';
import 'login.dart';

/// One listing. Pops with `true` when it changed - sold or deleted - so the
/// grid behind it can refresh.
class ListingScreen extends StatefulWidget {
  const ListingScreen({
    super.key,
    required this.api,
    required this.session,
    required this.listingId,
    this.initial,
  });

  final Api api;
  final MarketSession session;
  final int listingId;

  /// Shown at once while the fresh copy loads, so opening a tile is instant.
  final Listing? initial;

  @override
  State<ListingScreen> createState() => _ListingScreenState();
}

class _ListingScreenState extends State<ListingScreen> {
  late Listing? _l = widget.initial;
  bool _loading = false;
  bool _busy = false;
  bool _changed = false;
  Object? _error;

  String get _lang => L10n.of(context).code;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// Fetched again even with [ListingScreen.initial]: the grid's copy may be
  /// stale, and only a signed-in fetch says whether this is yours and whether
  /// you already have a conversation about it.
  Future<void> _load() async {
    setState(() {
      _loading = _l == null;
      _error = null;
    });
    final s = widget.session;
    Future<Listing> call(String? token) => widget.api.listing(widget.listingId, token: token, lang: _lang);
    try {
      Listing fresh;
      if (!s.signedIn) {
        fresh = await call(null);
      } else {
        try {
          fresh = await s.authed(call);
        } on ApiException catch (e) {
          if (e.code != 'unauthorized') rethrow;
          fresh = await call(null);
        }
      }
      if (mounted) setState(() => _l = fresh);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _message({required bool offer}) async {
    final l = _l;
    if (l == null) return;
    if (!await ensureMarketReady(context, widget.session) || !mounted) return;
    // Signing in may have just revealed that this is yours, or that there is
    // already a thread about it - read it again before deciding where to go.
    await _load();
    final fresh = _l;
    if (fresh == null || !mounted || fresh.isMine) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          api: widget.api,
          session: widget.session,
          conversationId: fresh.myConversationId,
          newThreadListing: fresh.myConversationId == null ? fresh : null,
          startWithOffer: offer,
        ),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _markSold() async {
    final l = _l;
    if (l == null) return;
    final t = L10n.of(context);
    if (!await confirmBrutal(context, t['marketSoldConfirm'])) return;
    await _act(() async {
      final sold = await widget.session.authed((tk) => widget.api.markSold(l.id, token: tk, lang: _lang));
      if (mounted) setState(() => _l = sold);
    });
  }

  Future<void> _delete() async {
    final l = _l;
    if (l == null) return;
    final t = L10n.of(context);
    if (!await confirmBrutal(context, t['marketDeleteConfirm'], danger: true)) return;
    await _act(() async {
      await widget.session.authed((tk) => widget.api.deleteListing(l.id, token: tk, lang: _lang));
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      _changed = true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(marketError(L10n.of(context), e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final l = _l;
    if (l == null) return;
    final t = L10n.of(context);
    await SharePlus.instance.share(
      ShareParams(text: '${l.title} - ${marketPrice(t, l.priceCents)}\n${Links.listing(l.id)}', subject: l.title),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final l = _l;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: Brutal.paper,
        body: SafeArea(
          child: Column(
            children: [
              MarketTopBar(
                title: l?.title ?? '',
                actions: [
                  if (l != null)
                    BrutalButton(
                      color: Brutal.cyan,
                      onPressed: _share,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.ios_share, size: 15),
                          const SizedBox(width: 5),
                          Text(t['marketShare'], style: Brutal.label.copyWith(fontSize: 12)),
                        ],
                      ),
                    ),
                ],
              ),
              Expanded(
                child: _loading
                    ? const Loading()
                    : l == null
                    ? ErrorState(message: marketError(t, _error ?? '...'), onRetry: _load)
                    : _body(l, t),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(Listing l, Strings t) {
    final expiresIn = l.expiresAt?.difference(DateTime.now()).inDays;
    return RefreshIndicator(
      color: Brutal.ink,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          Container(
            decoration: BoxDecoration(
              color: Brutal.paperDeep,
              border: Border.all(color: Brutal.ink, width: 4),
              boxShadow: Brutal.shadow(dx: 7, dy: 7),
            ),
            height: MediaQuery.of(context).size.height * 0.45,
            child: ListingPhoto(url: l.imageUrl, sold: l.isSold, seed: l.id, fit: BoxFit.contain, stampSize: 44),
          ),
          const SizedBox(height: 22),
          Align(alignment: Alignment.centerLeft, child: PriceTag(cents: l.priceCents, large: true)),
          const SizedBox(height: 16),
          Text(l.title, style: Brutal.display.copyWith(fontSize: 32)),
          if (l.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(l.description, style: Brutal.body.copyWith(fontSize: 17)),
          ],
          const SizedBox(height: 14),
          Text(
            [
              '${t['marketSeller']}: ${l.sellerName}',
              '${t['marketPosted']} ${relativeDate(l.createdAt)}',
              if (!l.isSold && expiresIn != null)
                expiresIn <= 0 ? t['marketExpiresSoon'] : t['marketExpiresIn'].replaceAll('{days}', '$expiresIn'),
            ].join(' · '),
            style: Brutal.body.copyWith(fontSize: 14, color: Brutal.ink.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 22),
          ..._actions(l, t),
          const SizedBox(height: 24),
          Text(t['marketSafety'], style: Brutal.body.copyWith(fontSize: 13, color: Brutal.ink.withValues(alpha: 0.7))),
          if (!l.isMine) ...[
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => showMarketReportSheet(
                  context,
                  title: t['marketReportListing'],
                  submit: (reason, details) =>
                      widget.api.reportListing(l.id, reason, details: details, lang: _lang),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.flag_outlined, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      t['marketReportListing'],
                      style: Brutal.body.copyWith(fontSize: 14, decoration: TextDecoration.underline),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _actions(Listing l, Strings t) {
    Widget wide(String label, Color color, VoidCallback? onTap) => BrutalButton(
      color: color,
      onPressed: _busy ? null : onTap,
      child: Center(child: Text(label, style: Brutal.label.copyWith(fontSize: 15))),
    );

    if (l.isMine) {
      return [
        BrutalBox(
          color: Brutal.cyan,
          padding: const EdgeInsets.all(14),
          child: Text(t['marketYours'], style: Brutal.heading.copyWith(fontSize: 18)),
        ),
        const SizedBox(height: 16),
        if (!l.isSold) ...[wide(t['marketMarkSold'], kHot, _markSold), const SizedBox(height: 12)],
        wide(t['marketDelete'], Brutal.danger, _delete),
      ];
    }
    if (l.isSold) {
      return [
        BrutalBox(
          color: Brutal.paperDeep,
          padding: const EdgeInsets.all(14),
          child: Text(t['marketClosed'], style: Brutal.heading.copyWith(fontSize: 18)),
        ),
        if (l.myConversationId != null) ...[
          const SizedBox(height: 12),
          wide(t['marketOpenThread'], Brutal.cyan, () => _message(offer: false)),
        ],
      ];
    }
    if (l.myConversationId != null) {
      return [wide(t['marketOpenThread'], Brutal.cyan, () => _message(offer: false))];
    }
    return [
      wide(t['marketMessage'], Brutal.cyan, () => _message(offer: false)),
      const SizedBox(height: 12),
      wide(t['marketOffer'], kHot, () => _message(offer: true)),
    ];
  }
}
