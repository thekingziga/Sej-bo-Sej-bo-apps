import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n.dart';
import '../models.dart';
import '../prefs.dart';
import '../theme.dart';
import '../widgets.dart';
import 'detail.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    required this.prefs,
    required this.onSeeAll,
    required this.onUpload,
  });

  final Api api;
  final Prefs prefs;
  final VoidCallback onSeeAll;
  final VoidCallback onUpload;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<Feed> _future;
  Post? _hero;
  int _heroVote = 0;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<Feed> _fetch() async {
    final feed = await widget.api.feed(lang: widget.prefs.lang == Lang.sl ? 'sl' : 'en');
    if (feed.posts.isNotEmpty) {
      _hero = feed.posts.first;
      _heroVote = widget.prefs.voteFor(_hero!.id);
    }
    return feed;
  }

  Future<void> _refresh() async {
    final f = _fetch();
    setState(() => _future = f);
    await f.catchError((_) => throw Exception());
  }

  void _open(Post p) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PostDetailScreen(post: p, api: widget.api, prefs: widget.prefs),
    ),
  );

  Future<void> _voteHero(int value) async {
    final post = _hero;
    if (post == null) return;
    final previous = _heroVote;
    final before = post;

    setState(() {
      _heroVote = value;
      _hero = _applyVote(post, previous, value);
    });
    await widget.prefs.setVote(post.id, value);

    try {
      final updated = await widget.api.vote(post.id, value);
      if (mounted) setState(() => _hero = updated);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _heroVote = previous;
        _hero = before;
      });
      await widget.prefs.setVote(post.id, previous);
    }
  }

  static Post _applyVote(Post p, int from, int to) {
    var up = p.upvotes, down = p.downvotes;
    if (from == 1) up--;
    if (from == -1) down--;
    if (to == 1) up++;
    if (to == -1) down++;
    return p.copyWith(upvotes: up.clamp(0, 1 << 30), downvotes: down.clamp(0, 1 << 30));
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);

    return SafeArea(
      bottom: false,
      child: FutureBuilder<Feed>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Loading(label: t['measuring']);
          }
          if (snap.hasError) {
            return ErrorState(message: '${snap.error}', onRetry: _refresh);
          }
          final feed = snap.data!;
          final hero = _hero ?? (feed.posts.isNotEmpty ? feed.posts.first : null);
          final rest = feed.posts.skip(1).take(3).toList();

          return RefreshIndicator(
            onRefresh: _refresh,
            color: Brutal.ink,
            backgroundColor: Brutal.yellow,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 28),
              children: [
                _Header(subtitle: t['brandSub']),

                if (widget.api.isDemo)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: _Banner(text: t['demoBanner'], color: Brutal.lime),
                  )
                else if (widget.api.servedFromCache)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: _Banner(text: t['offlineBanner'], color: Brutal.paperDeep),
                  ),

                Entrance(index: 0, child: _StatStrip(stats: feed.stats)),
                const SizedBox(height: 22),

                if (hero != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Entrance(
                      index: 1,
                      child: _HeroPost(
                        post: hero,
                        myVote: _heroVote,
                        onVote: _voteHero,
                        onTap: () => _open(hero),
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                ],

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Entrance(index: 2, child: _ChaosButton(api: widget.api)),
                ),
                const SizedBox(height: 26),

                if (feed.top.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SectionHead(
                      title: t['hallOfFame'],
                      action: t['seeAll'],
                      onAction: widget.onSeeAll,
                    ),
                  ),
                  for (var i = 0; i < feed.top.length; i++)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: _RankRow(
                        rank: i + 1,
                        post: feed.top[i],
                        onTap: () => _open(feed.top[i]),
                      ),
                    ),
                  const SizedBox(height: 22),
                ],

                if (rest.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SectionHead(title: t['moreChaos']),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: SizedBox(
                      // PostCard flexes its media into the leftover height, so
                      // it needs a bounded one; a bare Row inside a ListView is
                      // vertically unbounded.
                      height: 240,
                      child: Row(
                        children: [
                          for (var i = 0; i < rest.length; i++) ...[
                            if (i > 0) const SizedBox(width: 10),
                            Expanded(
                              child: PostCard(
                                post: rest[i],
                                index: i + 1,
                                onTap: () => _open(rest[i]),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                ],

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _QuoteCard(quote: feed.quote, label: t['randomQuote']),
                ),
                const SizedBox(height: 22),

                if (feed.daily != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _DailyAward(
                      post: feed.daily!,
                      label: t['todaysAward'],
                      onTap: () => _open(feed.daily!),
                    ),
                  ),
                const SizedBox(height: 26),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: BrutalButton(
                    expand: true,
                    color: Brutal.pink,
                    onPressed: widget.onUpload,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(t['submitCta'], style: const TextStyle(fontSize: 19)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Brand header with the EN/SL switch, mirroring the website's topbar.
class _Header extends StatelessWidget {
  const _Header({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final change = L10n.changerOf(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              border: Brutal.outline,
              boxShadow: Brutal.shadow(dx: 3, dy: 3),
            ),
            padding: const EdgeInsets.all(3),
            child: Image.asset(
              'assets/img/logo.png',
              width: 40,
              height: 40,
              errorBuilder: (_, _, _) => const SizedBox(width: 40, height: 40),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('SEJBOSEJBO', style: Brutal.display.copyWith(fontSize: 28)),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Brutal.body.copyWith(
                      fontSize: 13,
                      color: Brutal.ink.withValues(alpha: 0.65),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(color: Brutal.yellow, border: Brutal.outline),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final l in Lang.values)
                  GestureDetector(
                    onTap: () => change(l),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                      color: t.lang == l ? Brutal.ink : Colors.transparent,
                      child: Text(
                        l == Lang.en ? 'ENG' : 'SLO',
                        style: Brutal.label.copyWith(
                          fontSize: 11,
                          color: t.lang == l ? Brutal.paper : Brutal.ink,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return BrutalBox(
      color: color,
      dx: 3,
      dy: 3,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 17)),
          const SizedBox(width: 9),
          Expanded(child: Text(text, style: Brutal.label.copyWith(fontSize: 12))),
        ],
      ),
    );
  }
}

class _StatStrip extends StatelessWidget {
  const _StatStrip({required this.stats});

  final Stats stats;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final days = stats.daysSinceLast;
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _StatTile(value: '${stats.visits}', label: t['visitors'], color: Brutal.cyan),
          _StatTile(value: '${stats.uploads}', label: t['archived'], color: Brutal.yellow),
          _StatTile(
            value: days == null ? '∞' : '$days',
            label: t['daysSince'],
            color: Brutal.pink,
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label, required this.color});

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 11),
      child: BrutalBox(
        color: color,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Brutal.display.copyWith(fontSize: 38)),
            const SizedBox(height: 2),
            Text(label.toUpperCase(), style: Brutal.label.copyWith(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _HeroPost extends StatelessWidget {
  const _HeroPost({
    required this.post,
    required this.myVote,
    required this.onVote,
    required this.onTap,
  });

  final Post post;
  final int myVote;
  final ValueChanged<int> onVote;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: Brutal.ink,
            boxShadow: Brutal.shadow(dx: 3, dy: 3, color: Brutal.orange),
          ),
          child: Text(
            t['latest'],
            style: Brutal.label.copyWith(fontSize: 12, color: Brutal.paper),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Brutal.paper,
            border: Border.all(color: Brutal.ink, width: 4),
            boxShadow: Brutal.shadow(dx: 7, dy: 7),
          ),
          padding: const EdgeInsets.all(9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: onTap,
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Container(
                    decoration: BoxDecoration(border: Border.all(color: Brutal.ink, width: 2)),
                    child: ClipRect(
                      child: PostMedia(post: post, accent: Brutal.orange, compact: false),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 11),
              GestureDetector(
                onTap: onTap,
                child: Text(post.title, style: Brutal.display.copyWith(fontSize: 26)),
              ),
              if (post.description.isNotEmpty && !post.isStory) ...[
                const SizedBox(height: 5),
                Text(
                  post.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Brutal.body.copyWith(fontSize: 14),
                ),
              ],
              const SizedBox(height: 12),
              VoteBar(post: post, myVote: myVote, onVote: onVote),
              const SizedBox(height: 9),
              Row(
                children: [
                  if (post.featured) ...[BrutalTag(t['featured']), const SizedBox(width: 7)],
                  Text(
                    relativeDate(post.createdAt),
                    style: Brutal.body.copyWith(
                      fontSize: 12,
                      color: Brutal.ink.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One row of the Hall of Fame.
class _RankRow extends StatelessWidget {
  const _RankRow({required this.rank, required this.post, required this.onTap});

  final int rank;
  final Post post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: BrutalBox(
        dx: 4,
        dy: 4,
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            RankBadge(rank: rank),
            const SizedBox(width: 11),
            SizedBox(
              width: 52,
              height: 52,
              child: Container(
                decoration: BoxDecoration(border: Border.all(color: Brutal.ink, width: 2)),
                child: ClipRect(
                  child: PostMedia(post: post, accent: Brutal.accentFor(rank)),
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    post.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Brutal.heading.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  ScorePill(score: post.score),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The website's big pink button, ported. Fetches a random phrase and wobbles.
class _ChaosButton extends StatefulWidget {
  const _ChaosButton({required this.api});

  final Api api;

  @override
  State<_ChaosButton> createState() => _ChaosButtonState();
}

class _ChaosButtonState extends State<_ChaosButton> with SingleTickerProviderStateMixin {
  late final AnimationController _wobble = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  String? _text;
  bool _busy = false;

  @override
  void dispose() {
    _wobble.dispose();
    super.dispose();
  }

  Future<void> _press() async {
    if (_busy) return;
    final t = L10n.of(context);
    setState(() {
      _busy = true;
      _text = t['measuring'];
    });
    _wobble.forward(from: 0);
    try {
      final phrase = await widget.api.randomPhrase(lang: t.code);
      if (mounted) setState(() => _text = phrase);
    } catch (_) {
      if (mounted) setState(() => _text = t['measureFailed']);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final text = _text ?? t['pressIt'];

    return Column(
      children: [
        AnimatedBuilder(
          animation: _wobble,
          builder: (context, child) {
            final v = _wobble.value;
            return Transform.rotate(
              angle: math.sin(v * math.pi * 3) * 0.03 * (1 - v),
              child: child,
            );
          },
          child: BrutalButton(
            expand: true,
            color: Brutal.pink,
            onPressed: _press,
            padding: const EdgeInsets.symmetric(vertical: 26),
            child: const Text('SEJBOSEJBO', style: TextStyle(fontSize: 34, letterSpacing: 1)),
          ),
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: BrutalBox(
            key: ValueKey(text),
            dx: 3,
            dy: 3,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: Brutal.heading.copyWith(fontSize: 17),
            ),
          ),
        ),
      ],
    );
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({required this.quote, required this.label});

  final String quote;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (quote.isEmpty) return const SizedBox.shrink();
    return BrutalBox(
      color: Brutal.cyan,
      rotation: -0.008,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Brutal.label.copyWith(fontSize: 11)),
          const SizedBox(height: 7),
          Text('“$quote”', style: Brutal.heading.copyWith(fontSize: 22)),
        ],
      ),
    );
  }
}

class _DailyAward extends StatelessWidget {
  const _DailyAward({required this.post, required this.label, required this.onTap});

  final Post post;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: BrutalBox(
        color: Brutal.yellow,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Text('🏆', style: TextStyle(fontSize: 34)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: Brutal.label.copyWith(fontSize: 11)),
                  const SizedBox(height: 3),
                  Text(
                    post.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Brutal.heading.copyWith(fontSize: 19),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward, size: 22),
          ],
        ),
      ),
    );
  }
}
