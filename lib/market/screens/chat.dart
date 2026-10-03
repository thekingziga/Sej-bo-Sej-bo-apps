import 'dart:async';

import 'package:flutter/material.dart';

import '../../api.dart';
import '../../l10n.dart';
import '../../theme.dart';
import '../models.dart';
import '../session.dart';
import '../widgets.dart';
import 'listing.dart';

/// One conversation about one listing.
///
/// Opened either on an existing thread ([conversationId]) or on a listing with
/// no thread yet ([newThreadListing]); the first message sent creates the
/// thread, and from then on it is an ordinary one.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.api,
    required this.session,
    this.conversationId,
    this.newThreadListing,
    this.startWithOffer = false,
  }) : assert(conversationId != null || newThreadListing != null);

  final Api api;
  final MarketSession session;
  final int? conversationId;
  final Listing? newThreadListing;

  /// Opens with the offer field showing - the "make an offer" button.
  final bool startWithOffer;

  /// How often an open thread asks for new messages. There is no push for
  /// messages yet, and an open conversation is exactly where a reply is being
  /// waited for.
  static const pollEvery = Duration(seconds: 5);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  late int? _id = widget.conversationId;
  Conversation? _conv;
  final _messages = <MarketMessage>[];
  final _text = TextEditingController();
  final _offer = TextEditingController();
  final _scroll = ScrollController();

  late bool _offerMode = widget.startWithOffer;
  bool _loading = false;
  bool _sending = false;
  int? _answering;
  String? _error;
  Object? _loadError;
  Timer? _poll;
  DateTime? _lastMessageAt;

  String get _lang => L10n.of(context).code;

  ListingSummary? get _listing =>
      _conv?.listing ?? (widget.newThreadListing == null ? null : ListingSummary.of(widget.newThreadListing!));

  String get _otherName => _conv?.otherName ?? widget.newThreadListing?.sellerName ?? '';

  bool get _listingActive => _listing?.isActive ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _reload();
        _startPolling();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _text.dispose();
    _offer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Stops asking while the app is in the background - no one is reading, and
  /// a phone in a pocket should not wake up every five seconds for a meme site.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _pollOnce();
      _startPolling();
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  void _startPolling() {
    if (_id == null || _poll != null) return;
    _poll = Timer.periodic(ChatScreen.pollEvery, (_) => _pollOnce());
  }

  Future<void> _reload() async {
    final id = _id;
    if (id == null) return;
    setState(() {
      _loading = _messages.isEmpty;
      _loadError = null;
    });
    try {
      final r = await widget.session.authed((t) => widget.api.thread(id, token: t, lang: _lang));
      if (!mounted) return;
      final wasUnread = r.conversation.unread || widget.session.unreadCount > 0;
      setState(() {
        _conv = r.conversation;
        _lastMessageAt = r.conversation.lastMessageAt;
        _messages
          ..clear()
          ..addAll(r.messages);
      });
      _toBottom();
      // Reading the thread just marked it read on the server; without this the
      // badge on the tab kept counting it until the inbox was closed.
      if (wasUnread) widget.session.refresh(lang: _lang);
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Asks only for what is newer than the last message held.
  ///
  /// That cannot see an older message changing - the other side answering
  /// your offer - so the thread's `last_message_at` is watched as well: when it
  /// moves and nothing new came with it, the whole thread is read again. A new
  /// offer also triggers a full read, because it supersedes any pending one
  /// further up and only the server's copy says which.
  Future<void> _pollOnce() async {
    final id = _id;
    if (id == null || _sending || !mounted) return;
    try {
      final after = _messages.isEmpty ? null : _messages.last.id;
      final r = await widget.session.authed((t) => widget.api.thread(id, token: t, after: after, lang: _lang));
      if (!mounted) return;
      final fresh = r.messages.where((m) => !_messages.any((x) => x.id == m.id)).toList();
      final moved = _lastMessageAt != null && r.conversation.lastMessageAt.isAfter(_lastMessageAt!);
      if (fresh.any((m) => m.isOffer) || (fresh.isEmpty && moved)) {
        await _reload();
        return;
      }
      setState(() {
        _conv = r.conversation;
        _lastMessageAt = r.conversation.lastMessageAt;
        _messages.addAll(fresh);
      });
      if (fresh.isNotEmpty) _toBottom();
    } catch (e) {
      // A missed poll is not worth a message; the next one tries again. A dead
      // session is the exception - authed() has already ended it, so stop.
      if (e is ApiException && e.code == 'unauthorized' && mounted) {
        _poll?.cancel();
        Navigator.of(context).maybePop();
      }
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final t = L10n.of(context);
    final body = _text.text.trim();
    int? offerCents;
    if (_offerMode) {
      final parsed = Money.parse(_offer.text);
      if (!parsed.ok || parsed.cents == null) {
        setState(() => _error = t['chatOfferInvalid']);
        return;
      }
      offerCents = parsed.cents;
    }
    if (body.isEmpty && offerCents == null) {
      setState(() => _error = t['chatEmpty']);
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final id = _id;
      if (id == null) {
        final listing = widget.newThreadListing!;
        final r = await widget.session.authed((tk) => widget.api.messageSeller(
              listing.id,
              token: tk,
              body: body,
              offerCents: offerCents,
              lang: _lang,
            ));
        _id = r.conversationId;
        _text.clear();
        _offer.clear();
        _offerMode = false;
        await _reload();
        _startPolling();
      } else {
        final m = await widget.session.authed((tk) => widget.api.sendMessage(
              id,
              token: tk,
              body: body,
              offerCents: offerCents,
              lang: _lang,
            ));
        _text.clear();
        _offer.clear();
        _offerMode = false;
        if (m.isOffer) {
          await _reload();
        } else {
          setState(() => _messages.add(m));
          _toBottom();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = marketError(t, e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _answer(MarketMessage m, bool accept) async {
    final id = _id;
    if (id == null || _answering != null) return;
    final t = L10n.of(context);
    setState(() => _answering = m.id);
    try {
      final updated = await widget.session.authed(
        (tk) => widget.api.answerOffer(id, m.id, accept: accept, token: tk, lang: _lang),
      );
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((x) => x.id == m.id);
        if (i >= 0) _messages[i] = updated;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(marketError(t, e))));
      // Most likely "stale" - it was answered or superseded meanwhile. Show
      // the thread as it really is.
      await _reload();
    } finally {
      if (mounted) setState(() => _answering = null);
    }
  }

  Future<void> _menu(String choice) async {
    final id = _id;
    if (id == null) return;
    final t = L10n.of(context);
    if (choice == 'report') {
      await showMarketReportSheet(
        context,
        title: t['chatReport'],
        submit: (reason, details) => widget.session.authed(
          (tk) => widget.api.reportConversation(id, reason, token: tk, details: details, lang: _lang),
        ),
      );
    } else if (choice == 'block') {
      final ok = await confirmBrutal(context, t['chatBlockConfirm'].replaceAll('{name}', _otherName), danger: true);
      if (!ok || !mounted) return;
      try {
        await widget.session.authed((tk) => widget.api.blockInConversation(id, token: tk, lang: _lang));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['chatBlocked'])));
        Navigator.of(context).pop();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(marketError(t, e))));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final listing = _listing;
    return Scaffold(
      backgroundColor: Brutal.paper,
      body: SafeArea(
        child: Column(
          children: [
            MarketTopBar(
              title: _otherName,
              actions: [
                if (_id != null)
                  PopupMenuButton<String>(
                    onSelected: _menu,
                    icon: const Icon(Icons.more_vert, color: Brutal.ink),
                    color: Brutal.paper,
                    shape: const RoundedRectangleBorder(side: BorderSide(color: Brutal.ink, width: 3)),
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'report', child: Text(t['chatReport'], style: Brutal.body)),
                      PopupMenuItem(
                        value: 'block',
                        child: Text(t['chatBlock'].replaceAll('{name}', _otherName), style: Brutal.body),
                      ),
                    ],
                  ),
              ],
            ),
            if (listing != null) _ListingStrip(listing: listing, onTap: () => _openListing(listing)),
            Expanded(child: _thread(t)),
            _composer(t),
          ],
        ),
      ),
    );
  }

  void _openListing(ListingSummary l) => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => ListingScreen(api: widget.api, session: widget.session, listingId: l.id)),
  );

  Widget _thread(Strings t) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Brutal.ink));
    if (_loadError != null && _messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(marketError(t, _loadError!), textAlign: TextAlign.center, style: Brutal.body),
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            t['chatFirst'].replaceAll('{name}', _otherName),
            textAlign: TextAlign.center,
            style: Brutal.heading.copyWith(fontSize: 18),
          ),
        ),
      );
    }
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: _messages.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final m = _messages[i];
        return MessageBubble(
          message: m,
          listingActive: _listingActive,
          busy: _answering == m.id,
          onAnswer: (accept) => _answer(m, accept),
        );
      },
    );
  }

  Widget _composer(Strings t) {
    final active = _listingActive;
    return Container(
      decoration: const BoxDecoration(
        color: Brutal.paperDeep,
        border: Border(top: BorderSide(color: Brutal.ink, width: 3)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!active && _listing != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(t['marketClosed'], style: Brutal.body.copyWith(fontSize: 13)),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: Brutal.body.copyWith(fontSize: 14, color: Brutal.danger)),
            ),
          if (_offerMode && active)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _box(
                TextField(
                  controller: _offer,
                  autofocus: widget.startWithOffer,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  decoration: _deco(t['chatOfferField']).copyWith(suffixText: '€'),
                ),
                color: kHot,
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (active) ...[
                GestureDetector(
                  onTap: () => setState(() {
                    _offerMode = !_offerMode;
                    _error = null;
                  }),
                  child: Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: _offerMode ? kHot : Brutal.paper,
                      border: Brutal.outline,
                    ),
                    child: const Text('€', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: _box(
                  TextField(
                    controller: _text,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 2000,
                    textCapitalization: TextCapitalization.sentences,
                    style: Brutal.body.copyWith(fontSize: 16),
                    decoration: _deco(t['chatHint']).copyWith(counterText: ''),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              BrutalButton(
                color: Brutal.yellow,
                onPressed: _sending ? null : _send,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 3))
                    : Text(t['chatSend'], style: Brutal.label.copyWith(fontSize: 13)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _box(Widget child, {Color color = Brutal.paper}) => Container(
    decoration: BoxDecoration(color: color, border: Brutal.outline),
    child: child,
  );

  InputDecoration _deco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: Brutal.body.copyWith(fontSize: 16, color: Brutal.ink.withValues(alpha: 0.4)),
    border: InputBorder.none,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );
}

/// The listing a conversation is about, pinned above it - like the site's
/// thread header. Tapping it opens the listing.
class _ListingStrip extends StatelessWidget {
  const _ListingStrip({required this.listing, required this.onTap});

  final ListingSummary listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Brutal.paper,
          border: Brutal.outline,
          boxShadow: Brutal.shadow(dx: 4, dy: 4),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(border: Border.all(color: Brutal.ink, width: 2)),
              child: ListingPhoto(
                url: listing.imageUrl,
                sold: !listing.isActive,
                seed: listing.id,
                stampSize: 8,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(listing.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Brutal.heading.copyWith(fontSize: 16)),
                  const SizedBox(height: 4),
                  PriceTag(cents: listing.priceCents),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
