import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api.dart';
import '../../l10n.dart';
import '../../models.dart' show Links;
import '../../theme.dart';
import '../../widgets.dart';
import '../models.dart';
import '../session.dart';
import '../widgets.dart';
import 'account.dart';
import 'inbox.dart';
import 'listing.dart';
import 'login.dart';
import 'sell.dart';

/// The marketplace tab: everything for sale, newest first, two to a row.
class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key, required this.api, required this.session});

  final Api api;
  final MarketSession session;

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  final _items = <Listing>[];
  final _scroll = ScrollController();
  final _search = TextEditingController();
  Timer? _debounce;

  ListingSort _sort = ListingSort.newest;
  ListingSort _appliedSort = ListingSort.newest;
  String _appliedQ = '';
  int _page = 0;
  bool _hasNext = true;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;

  /// Bumped on every fresh load, so a slow response to an old search cannot
  /// land on top of the results for a newer one.
  int _generation = 0;

  /// The marketplace has answered at least once - so it exists on this server.
  bool _answered = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  String get _lang => L10n.of(context).code;

  void _onScroll() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _loadMore();
  }

  Future<void> _reload() async {
    final gen = ++_generation;
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final page = await _fetch(1);
      if (!mounted || gen != _generation) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _page = 1;
        _hasNext = page.hasNext;
        _appliedSort = page.sort;
        _appliedQ = page.q;
        _answered = true;
      });
    } catch (e) {
      if (mounted && gen == _generation) setState(() => _error = e);
    } finally {
      if (mounted && gen == _generation) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasNext || _error != null) return;
    final gen = _generation;
    setState(() => _loadingMore = true);
    try {
      final page = await _fetch(_page + 1);
      if (!mounted || gen != _generation) return;
      final seen = _items.map((l) => l.id).toSet();
      setState(() {
        // A listing published between two page loads shifts everything down by
        // one, so the next page repeats the last item of this one.
        _items.addAll(page.items.where((l) => !seen.contains(l.id)));
        _page = page.page;
        _hasNext = page.hasNext;
      });
    } catch (_) {
      // The next scroll tries again; the items already shown stay.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Browsing is public. Signed in, the token goes along so the server can
  /// mark your own listings - and it goes through [MarketSession.authed] like
  /// every other use of it, so a dead token ends the session here too.
  ///
  /// A dead token must not cost the person the listings, though: the session
  /// has already ended by the time the 401 arrives, so the page is fetched
  /// again as a visitor.
  Future<ListingPage> _fetch(int page) async {
    final s = widget.session;
    Future<ListingPage> call(String? token) =>
        widget.api.listings(page: page, q: _search.text, sort: _sort, token: token, lang: _lang);
    if (!s.signedIn) return call(null);
    try {
      return await s.authed(call);
    } on ApiException catch (e) {
      if (e.code != 'unauthorized') rethrow;
      return call(null);
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _reload);
  }

  void _setSort(ListingSort s) {
    if (s == _sort) return;
    setState(() => _sort = s);
    _reload();
  }

  Future<void> _open(Listing l) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ListingScreen(api: widget.api, session: widget.session, listingId: l.id, initial: l),
      ),
    );
    if (changed == true) _reload();
  }

  Future<void> _sell() async {
    if (!await ensureMarketReady(context, widget.session) || !mounted) return;
    final created = await Navigator.of(context).push<Listing>(
      MaterialPageRoute(builder: (_) => SellScreen(api: widget.api, session: widget.session)),
    );
    if (created == null || !mounted) return;
    _reload();
    _open(created);
  }

  Future<void> _inbox() async {
    if (!await ensureMarketReady(context, widget.session) || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => InboxScreen(api: widget.api, session: widget.session)),
    );
    widget.session.refresh(lang: _lang);
  }

  Future<void> _account() async {
    if (!widget.session.signedIn) {
      await ensureMarketReady(context, widget.session);
      if (mounted) _reload();
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AccountScreen(api: widget.api, session: widget.session)),
    );
    if (changed == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Brutal.paper,
          body: SafeArea(
            child: RefreshIndicator(
              color: Brutal.ink,
              onRefresh: _reload,
              child: CustomScrollView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _header(t)),
                  ..._body(t),
                  const SliverToBoxAdapter(child: SizedBox(height: 96)),
                ],
              ),
            ),
          ),
          // Not offered until the marketplace has answered once: shown during
          // the first load it would flash and vanish on a server that does not
          // have the marketplace yet, promising something that cannot work.
          floatingActionButton: !_answered
              ? null
              : BrutalButton(
                  color: Brutal.pink,
                  onPressed: _sell,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add, size: 20),
                      const SizedBox(width: 6),
                      Text(t['marketSell'], style: Brutal.label.copyWith(fontSize: 15)),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _header(Strings t) {
    final s = widget.session;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(t['marketTitle'], style: Brutal.display.copyWith(fontSize: 34))),
              const SizedBox(width: 10),
              if (s.signedIn) ...[
                _HeaderButton(
                  icon: Icons.chat_bubble_outline,
                  color: s.unreadCount > 0 ? kHot : Brutal.paper,
                  badge: s.unreadCount,
                  tooltip: t['marketInbox'],
                  onTap: _inbox,
                ),
                const SizedBox(width: 8),
              ],
              _HeaderButton(
                icon: s.signedIn ? Icons.person_outline : Icons.login,
                color: s.signedIn ? Brutal.cyan : Brutal.yellow,
                tooltip: s.signedIn ? t['marketAccount'] : t['marketLogin'],
                onTap: _account,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(t['marketSub'], style: Brutal.body.copyWith(fontSize: 14, color: Brutal.ink.withValues(alpha: 0.7))),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Brutal.paper,
              border: Brutal.outline,
              boxShadow: Brutal.shadow(dx: 4, dy: 4),
            ),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _reload(),
              style: Brutal.body.copyWith(fontSize: 16),
              cursorColor: Brutal.ink,
              decoration: InputDecoration(
                hintText: t['marketSearch'],
                hintStyle: Brutal.body.copyWith(fontSize: 16, color: Brutal.ink.withValues(alpha: 0.4)),
                prefixIcon: const Icon(Icons.search, color: Brutal.ink),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                for (final (sort, label) in [
                  (ListingSort.newest, t['marketSortNew']),
                  (ListingSort.priceAsc, t['marketSortCheap']),
                  (ListingSort.priceDesc, t['marketSortDear']),
                ]) ...[
                  _SortChip(label: label, active: _sort == sort, onTap: () => _setSort(sort)),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          // The server echoes what it applied. If that is not what was asked
          // for, say so, rather than show unsorted results under a sort label.
          if (!_loading && _error == null && _appliedSort != _sort)
            _Hint(text: t['marketSortNotApplied']),
          if (!_loading && _error == null && _search.text.trim().isNotEmpty && _appliedQ.isEmpty)
            _Hint(text: t['marketSearchNotApplied']),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  List<Widget> _body(Strings t) {
    if (_loading) {
      return const [SliverFillRemaining(hasScrollBody: false, child: Loading())];
    }
    final error = _error;
    if (error != null) {
      final unavailable = error is ApiException && error.code == 'unavailable';
      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
            child: unavailable
                ? MarketNotice(
                    title: t['marketUnavailableTitle'],
                    body: t['marketUnavailableBody'],
                    action: BrutalButton(
                      color: Brutal.yellow,
                      onPressed: () => launchUrl(
                        Uri.parse(Links.marketplace(t.code)),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: Center(child: Text(t['marketOpenWeb'], style: Brutal.label)),
                    ),
                  )
                : ErrorState(message: marketError(t, error), onRetry: _reload),
          ),
        ),
      ];
    }
    if (_items.isEmpty) {
      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
          sliver: SliverToBoxAdapter(
            child: Text(
              _search.text.trim().isEmpty ? t['marketEmpty'] : t['marketNoMatch'],
              textAlign: TextAlign.center,
              style: Brutal.heading.copyWith(fontSize: 20),
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverLayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.crossAxisExtent > 600 ? 3 : 2;
            const gap = 14.0;
            final tile = (constraints.crossAxisExtent - gap * (columns - 1)) / columns;
            // Square photo plus price and two lines of title, grown with the
            // system text size so a large-font phone does not clip titles.
            final text = MediaQuery.textScalerOf(context).scale(1) * 82;
            return SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: gap,
                crossAxisSpacing: gap,
                mainAxisExtent: tile + text,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => ListingCard(listing: _items[i], onTap: () => _open(_items[i])),
                childCount: _items.length,
              ),
            );
          },
        ),
      ),
      if (_loadingMore)
        const SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
        ),
    ];
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color,
                border: Brutal.outline,
                boxShadow: Brutal.shadow(dx: 3, dy: 3),
              ),
              child: Icon(icon, size: 22),
            ),
            if (badge > 0) Positioned(right: -8, top: -8, child: UnreadBadge(count: badge)),
          ],
        ),
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: active ? Brutal.ink : Brutal.paper,
        border: Brutal.outline,
      ),
      child: Text(
        label,
        style: Brutal.label.copyWith(fontSize: 12, color: active ? Brutal.paper : Brutal.ink),
      ),
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Text(text, style: Brutal.body.copyWith(fontSize: 13, color: Brutal.ink.withValues(alpha: 0.65))),
  );
}
