import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'detail.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api, required this.onSeeAll, required this.onUpload});

  final Api api;
  final VoidCallback onSeeAll;
  final VoidCallback onUpload;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<Feed> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.feed();
  }

  Future<void> _refresh() async {
    final f = widget.api.feed();
    setState(() => _future = f);
    await f.catchError((_) => throw Exception());
  }

  void _open(Post p) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostDetailScreen(post: p)));

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: FutureBuilder<Feed>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Loading();
          }
          if (snap.hasError) {
            return ErrorState(message: '${snap.error}', onRetry: _refresh);
          }
          final feed = snap.data!;
          final hero = feed.posts.isNotEmpty ? feed.posts.first : null;
          final rest = feed.posts.skip(1).take(3).toList();

          return RefreshIndicator(
            onRefresh: _refresh,
            color: Brutal.ink,
            backgroundColor: Brutal.yellow,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 28),
              children: [
                const BrandHeader(title: 'Sejbosejbo', subtitle: 'Officially certifying stupidity'),

                if (widget.api.isDemo)
                  const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 14), child: _DemoBanner()),

                Entrance(index: 0, child: _StatStrip(stats: feed.stats)),
                const SizedBox(height: 22),

                if (hero != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Entrance(
                      index: 1,
                      child: _HeroPost(post: hero, onTap: () => _open(hero)),
                    ),
                  ),
                  const SizedBox(height: 26),
                ],

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Entrance(index: 2, child: _ChaosButton(api: widget.api)),
                ),
                const SizedBox(height: 26),

                if (rest.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SectionHead(
                      title: 'More chaos',
                      action: 'see all',
                      onAction: widget.onSeeAll,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Entrance(
                      index: 3,
                      enabled: false,
                      // PostCard flexes its media into the leftover height, so
                      // it needs a bounded one; a bare Row inside a ListView is
                      // vertically unbounded.
                      child: SizedBox(
                        height: 232,
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
                  ),
                  const SizedBox(height: 28),
                ],

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Entrance(index: 4, enabled: false, child: _QuoteCard(quote: feed.quote)),
                ),
                const SizedBox(height: 22),

                if (feed.daily != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Entrance(
                      index: 5,
                      enabled: false,
                      child: _DailyAward(post: feed.daily!, onTap: () => _open(feed.daily!)),
                    ),
                  ),
                const SizedBox(height: 26),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Entrance(
                    index: 6,
                    enabled: false,
                    child: BrutalButton(
                      expand: true,
                      color: Brutal.pink,
                      onPressed: widget.onUpload,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: const Text('SUBMIT A SEJBOSEJBO', style: TextStyle(fontSize: 19)),
                    ),
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

class _DemoBanner extends StatelessWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context) {
    return BrutalBox(
      color: Brutal.lime,
      dx: 3,
      dy: 3,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 17)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'DEMO DATA — the website API is not live yet',
              style: Brutal.label.copyWith(fontSize: 12),
            ),
          ),
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
    final days = stats.daysSinceLast;
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _StatTile(value: '${stats.visits}', label: 'Visitors', color: Brutal.cyan),
          _StatTile(value: '${stats.uploads}', label: 'Archived', color: Brutal.yellow),
          _StatTile(value: days == null ? '∞' : '$days', label: 'Days since', color: Brutal.pink),
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
  const _HeroPost({required this.post, required this.onTap});

  final Post post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: Brutal.ink,
                boxShadow: Brutal.shadow(dx: 3, dy: 3, color: Brutal.orange),
              ),
              child: Text(
                'LATEST SEJBOSEJBO',
                style: Brutal.label.copyWith(fontSize: 12, color: Brutal.paper),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: Brutal.paper,
              border: Border.all(color: Brutal.ink, width: 4),
              boxShadow: Brutal.shadow(dx: 7, dy: 7),
            ),
            padding: const EdgeInsets.all(9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Container(
                    decoration: BoxDecoration(border: Border.all(color: Brutal.ink, width: 2)),
                    child: ClipRect(
                      child: PostMedia(post: post, accent: Brutal.orange, compact: false),
                    ),
                  ),
                ),
                const SizedBox(height: 11),
                Text(post.title, style: Brutal.display.copyWith(fontSize: 26)),
                if (post.description.isNotEmpty && !post.isStory) ...[
                  const SizedBox(height: 5),
                  Text(
                    post.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Brutal.body.copyWith(fontSize: 14),
                  ),
                ],
                const SizedBox(height: 7),
                Row(
                  children: [
                    if (post.featured) ...[const BrutalTag('featured'), const SizedBox(width: 7)],
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
        ),
      ],
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
  String _text = 'Press it. You know you want to.';
  bool _busy = false;

  @override
  void dispose() {
    _wobble.dispose();
    super.dispose();
  }

  Future<void> _press() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _text = 'Measuring Sejbosejbo...';
    });
    _wobble.forward(from: 0);
    try {
      final phrase = await widget.api.randomPhrase();
      if (mounted) setState(() => _text = phrase);
    } catch (_) {
      if (mounted) setState(() => _text = 'Calibrating stupidity detector failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedBuilder(
          animation: _wobble,
          builder: (context, child) {
            final t = _wobble.value;
            final angle = math.sin(t * math.pi * 3) * 0.03 * (1 - t);
            return Transform.rotate(angle: angle, child: child);
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
            key: ValueKey(_text),
            color: Brutal.paper,
            dx: 3,
            dy: 3,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Text(
              _text,
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
  const _QuoteCard({required this.quote});

  final String quote;

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
          Text('RANDOM QUOTE', style: Brutal.label.copyWith(fontSize: 11)),
          const SizedBox(height: 7),
          Text('“$quote”', style: Brutal.heading.copyWith(fontSize: 22)),
        ],
      ),
    );
  }
}

class _DailyAward extends StatelessWidget {
  const _DailyAward({required this.post, required this.onTap});

  final Post post;
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
                  Text("TODAY'S AWARD", style: Brutal.label.copyWith(fontSize: 11)),
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
