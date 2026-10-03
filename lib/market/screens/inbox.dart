import 'package:flutter/material.dart';

import '../../api.dart';
import '../../l10n.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../models.dart';
import '../session.dart';
import '../widgets.dart';
import 'chat.dart';

/// Every conversation, newest first - the site's inbox. Unread rows are
/// yellow, as they are there.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, required this.api, required this.session});

  final Api api;
  final MarketSession session;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  List<Conversation>? _items;
  Object? _error;

  String get _lang => L10n.of(context).code;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await widget.session.authed((t) => widget.api.conversations(token: t, lang: _lang));
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.code == 'unauthorized') {
        Navigator.of(context).maybePop();
        return;
      }
      setState(() => _error = e);
    }
  }

  Future<void> _open(Conversation c) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(api: widget.api, session: widget.session, conversationId: c.id),
      ),
    );
    if (!mounted) return;
    _load();
    widget.session.refresh(lang: _lang);
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final items = _items;
    return Scaffold(
      backgroundColor: Brutal.paper,
      body: SafeArea(
        child: Column(
          children: [
            MarketTopBar(title: t['inboxTitle']),
            Expanded(
              child: RefreshIndicator(
                color: Brutal.ink,
                onRefresh: _load,
                child: items == null
                    ? (_error != null
                          ? ListView(children: [ErrorState(message: marketError(t, _error!), onRetry: _load)])
                          : const Loading())
                    : items.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(32),
                        children: [
                          Text(t['inboxEmpty'], textAlign: TextAlign.center, style: Brutal.heading.copyWith(fontSize: 20)),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _Row(conversation: items[i], onTap: () => _open(items[i])),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.conversation, required this.onTap});

  final Conversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final c = conversation;
    final who = (c.role == ConversationRole.buyer ? t['inboxWithSeller'] : t['inboxWithBuyer'])
        .replaceAll('{name}', c.otherName);
    final preview = c.lastOfferCents != null && c.lastBody.isEmpty
        ? t['offerPreview'].replaceAll('{amount}', Money.format(c.lastOfferCents!, t.code))
        : c.lastBody;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: c.unread ? kHot : Brutal.paper,
          border: Brutal.outline,
          boxShadow: Brutal.shadow(dx: 4, dy: 4),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(border: Border.all(color: Brutal.ink, width: 2)),
              child: ListingPhoto(
                url: c.listing.imageUrl,
                sold: !c.listing.isActive,
                seed: c.listing.id,
                stampSize: 8,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.listing.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Brutal.heading.copyWith(fontSize: 16),
                  ),
                  Text(who, style: Brutal.body.copyWith(fontSize: 13, color: Brutal.ink.withValues(alpha: 0.7))),
                  const SizedBox(height: 2),
                  Text(
                    '${c.lastMine ? t['inboxYou'] : ''}$preview',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Brutal.body.copyWith(
                      fontSize: 14,
                      fontWeight: c.unread ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(relativeDate(c.lastMessageAt), style: Brutal.body.copyWith(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
