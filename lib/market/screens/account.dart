import 'package:flutter/material.dart';

import '../../api.dart';
import '../../l10n.dart';
import '../../theme.dart';
import '../models.dart';
import '../session.dart';
import '../widgets.dart';
import 'listing.dart';
import 'login.dart';

/// The signed-in account: name, email notifications, your listings, who you
/// have blocked - and the two ways out, logging out and deleting it all.
///
/// Deleting is here, in the app, because Play requires it for any app that
/// lets people create an account; the website's /account page covers the
/// other half of that rule, deleting without the app.
///
/// Pops with true when anything the grid shows may have changed.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.api, required this.session});

  final Api api;
  final MarketSession session;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  List<Listing>? _mine;
  List<BlockedUser>? _blocked;
  bool _busy = false;
  bool _changed = false;
  String? _error;

  String get _lang => L10n.of(context).code;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final s = widget.session;
    try {
      final mine = await s.authed((t) => widget.api.myListings(token: t, lang: _lang));
      final blocked = await s.authed((t) => widget.api.blockedUsers(token: t, lang: _lang));
      if (mounted) {
        setState(() {
          _mine = mine;
          _blocked = blocked;
          _error = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.code == 'unauthorized') {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() => _error = marketError(L10n.of(context), e));
    }
  }

  Future<void> _do(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(marketError(L10n.of(context), e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => MarketLoginScreen(session: widget.session, nameOnly: true)),
    );
    _changed = true;
  }

  Future<void> _unblock(BlockedUser b) => _do(() async {
    await widget.session.authed((t) => widget.api.unblock(b.userId, token: t, lang: _lang));
    if (mounted) setState(() => _blocked = [...?_blocked]..removeWhere((x) => x.userId == b.userId));
  });

  Future<void> _logout() => _do(() async {
    await widget.session.signOut();
    if (mounted) Navigator.of(context).pop(true);
  });

  Future<void> _delete() async {
    final t = L10n.of(context);
    if (!await confirmBrutal(context, t['accountDeleteConfirm'], danger: true) || !mounted) return;
    await _do(() async {
      await widget.session.deleteAccount(lang: _lang);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['accountDeleted'])));
      Navigator.of(context).pop(true);
    });
  }

  Future<void> _open(Listing l) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ListingScreen(api: widget.api, session: widget.session, listingId: l.id, initial: l),
      ),
    );
    if (changed == true) {
      _changed = true;
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: ListenableBuilder(
        listenable: widget.session,
        builder: (context, _) {
          final me = widget.session.me;
          return Scaffold(
            backgroundColor: Brutal.paper,
            body: SafeArea(
              child: Column(
                children: [
                  MarketTopBar(title: t['accountTitle']),
                  Expanded(
                    child: RefreshIndicator(
                      color: Brutal.ink,
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                        children: [
                          Text(me?.name ?? '', style: Brutal.display.copyWith(fontSize: 36)),
                          const SizedBox(height: 4),
                          Text(me?.email ?? '', style: Brutal.body.copyWith(fontSize: 15)),
                          const SizedBox(height: 14),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: BrutalButton(
                              color: Brutal.cyan,
                              onPressed: _busy ? null : _rename,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              child: Text(t['accountName'], style: Brutal.label.copyWith(fontSize: 12)),
                            ),
                          ),
                          const SizedBox(height: 20),
                          BrutalBox(
                            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                            child: Row(
                              children: [
                                Expanded(child: Text(t['accountNotify'], style: Brutal.body.copyWith(fontSize: 15))),
                                Switch(
                                  value: me?.notify ?? true,
                                  activeTrackColor: Brutal.ink,
                                  onChanged: _busy
                                      ? null
                                      : (v) => _do(() => widget.session.setNotify(v, lang: _lang)),
                                ),
                              ],
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Text(_error!, style: Brutal.body.copyWith(color: Brutal.danger)),
                          ],
                          const SizedBox(height: 28),
                          _Heading(t['accountListings']),
                          ..._listings(t),
                          if ((_blocked ?? const []).isNotEmpty) ...[
                            const SizedBox(height: 28),
                            _Heading(t['accountBlocked']),
                            for (final b in _blocked!)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Expanded(child: Text(b.name, style: Brutal.heading.copyWith(fontSize: 17))),
                                    BrutalButton(
                                      color: Brutal.paper,
                                      onPressed: _busy ? null : () => _unblock(b),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      child: Text(t['accountUnblock'], style: Brutal.label.copyWith(fontSize: 12)),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                          const SizedBox(height: 36),
                          BrutalButton(
                            color: Brutal.paper,
                            onPressed: _busy ? null : _logout,
                            child: Center(child: Text(t['accountLogout'], style: Brutal.label.copyWith(fontSize: 15))),
                          ),
                          const SizedBox(height: 14),
                          BrutalButton(
                            color: Brutal.danger,
                            onPressed: _busy ? null : _delete,
                            child: Center(child: Text(t['accountDelete'], style: Brutal.label.copyWith(fontSize: 15))),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _listings(Strings t) {
    final mine = _mine;
    if (mine == null) {
      return const [Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))];
    }
    if (mine.isEmpty) {
      return [Text(t['accountNoListings'], style: Brutal.body.copyWith(fontSize: 15))];
    }
    final now = DateTime.now();
    return [
      for (final l in mine)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            // A hidden listing's public page 404s - say why instead.
            onTap: l.hidden
                ? () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(t[l.held ? 'listingHeldNote' : 'listingHiddenNote'])),
                  )
                : () => _open(l),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Brutal.paper,
                border: Brutal.outline,
                boxShadow: Brutal.shadow(dx: 3, dy: 3),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: ListingPhoto(url: l.imageUrl, sold: l.isSold, seed: l.id, stampSize: 8),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Brutal.heading.copyWith(fontSize: 16)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            PriceTag(cents: l.priceCents),
                            const SizedBox(width: 8),
                            if (l.hidden)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: kHot, border: Brutal.outline),
                                child: Text(
                                  t[l.held ? 'listingHeld' : 'listingHidden'],
                                  style: Brutal.label.copyWith(fontSize: 11),
                                ),
                              )
                            else if (l.isSold)
                              Text(t['marketSold'], style: Brutal.label.copyWith(fontSize: 11))
                            else if (l.expiresAt != null && l.expiresAt!.isBefore(now))
                              Text(t['accountExpired'], style: Brutal.body.copyWith(fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ];
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(text, style: Brutal.label.copyWith(fontSize: 14)),
  );
}
