import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n.dart';

import 'models.dart';
import 'theme.dart';

/// Renders a post's visual: a real photo, a text-only "story" card, or - in demo
/// mode, where posts carry no image URL - a branded placeholder that still looks
/// deliberate rather than broken.
class PostMedia extends StatelessWidget {
  const PostMedia({
    super.key,
    required this.post,
    required this.accent,
    this.compact = true,
    this.fit = BoxFit.cover,
  });

  final Post post;
  final Color accent;
  final bool compact;

  /// cover for grid tiles (fills the square), contain on the detail screen so
  /// the whole image is visible - tall screenshots were being cropped.
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final url = post.imageUrl;

    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: fit,
        loadingBuilder: (c, child, progress) => progress == null
            ? child
            : Container(
                color: Brutal.paperDeep,
                child: const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 3, color: Brutal.ink),
                  ),
                ),
              ),
        errorBuilder: (c, e, s) => _Placeholder(post: post, accent: accent, compact: compact),
      );
    }

    if (post.kind == 'story') {
      return Container(
        color: Brutal.yellow,
        padding: EdgeInsets.all(compact ? 10 : 22),
        alignment: Alignment.center,
        child: Text(
          post.description.isEmpty
              ? 'A text-only Sejbosejbo of mysterious origin.'
              : post.description,
          textAlign: TextAlign.center,
          maxLines: compact ? 4 : 12,
          overflow: TextOverflow.ellipsis,
          style: Brutal.body.copyWith(fontSize: compact ? 13 : 20, fontWeight: FontWeight.w700),
        ),
      );
    }

    return _Placeholder(post: post, accent: accent, compact: compact);
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.post, required this.accent, required this.compact});

  final Post post;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: accent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: -14,
            bottom: -14,
            child: Opacity(
              opacity: 0.32,
              child: Image.asset(
                'assets/img/logo.png',
                width: compact ? 92 : 190,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(compact ? 9 : 20),
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                post.title.toUpperCase(),
                maxLines: compact ? 3 : 5,
                overflow: TextOverflow.ellipsis,
                style: Brutal.display.copyWith(fontSize: compact ? 15 : 30),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Gallery / dashboard tile. Slightly rotated by index for the scrapbook feel.
///
/// The media flexes to fill whatever height is left after the caption, so the
/// card can never overflow - which means **callers must give it a bounded
/// height** (a grid `mainAxisExtent`, or a SizedBox around a Row).
///
/// An earlier version pinned the media square with AspectRatio and took the
/// tile height from a fixed `childAspectRatio`. That overflowed on narrow
/// phones: the caption's height is fixed, but the tile's scales with width, so
/// any ratio tuned on a 414pt screen breaks on a 360pt one.
class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.post, required this.index, required this.onTap});

  final Post post;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Brutal.accentFor(index);
    // Deterministic tilt so the layout does not jitter between rebuilds.
    final tilt = ((index % 3) - 1) * 0.012;

    return GestureDetector(
      onTap: onTap,
      child: Transform.rotate(
        angle: tilt,
        child: Container(
          decoration: BoxDecoration(
            color: Brutal.paper,
            border: Brutal.outline,
            boxShadow: Brutal.shadow(dx: 4, dy: 4),
          ),
          padding: const EdgeInsets.all(7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(border: Border.all(color: Brutal.ink, width: 2)),
                  child: ClipRect(child: PostMedia(post: post, accent: accent)),
                ),
              ),
              const SizedBox(height: 7),
              if (post.pinned || post.featured) ...[
                Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  children: [
                    if (post.pinned) BrutalTag(L10n.of(context)['pinned'], color: Brutal.cyan),
                    if (post.featured) BrutalTag(L10n.of(context)['featured']),
                  ],
                ),
                const SizedBox(height: 5),
              ],
              Text(
                post.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Brutal.heading.copyWith(fontSize: 15),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  // Score only, not the vote buttons: at ~184pt wide the two
                  // chips would fall below a comfortable tap target. Voting
                  // lives on the hero, the detail screen and the hall of fame.
                  ScorePill(score: post.score),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      relativeDate(post.createdAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Brutal.body.copyWith(
                        fontSize: 12,
                        color: Brutal.ink.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Net score, coloured by sign. Lime when the crowd agrees it is Sejbosejbo,
/// red when they think it is not, grey at zero.
class ScorePill extends StatelessWidget {
  const ScorePill({super.key, required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final color = score > 0
        ? Brutal.lime
        : score < 0
        ? Brutal.danger
        : Brutal.paperDeep;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: color, border: Border.all(color: Brutal.ink, width: 2)),
      child: Text(
        score > 0 ? '+$score' : '$score',
        style: Brutal.display.copyWith(fontSize: 13),
      ),
    );
  }
}

/// SEJ BO / SEJ NE BO. Optimistic: the count moves the instant you tap and
/// reverts if the server disagrees, because a vote that visibly lags feels broken.
class VoteBar extends StatelessWidget {
  const VoteBar({
    super.key,
    required this.post,
    required this.myVote,
    required this.onVote,
    this.compact = false,
  });

  final Post post;

  /// -1, 0 or 1.
  final int myVote;

  /// Receives the new value; tapping your existing choice again passes 0 (undo).
  final ValueChanged<int> onVote;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    // Wrap, not Row: "SEJ NE BO" plus a five-digit count is wide, and on a
    // 360pt phone the pair does not fit on one line inside a bordered card.
    return Wrap(
      spacing: compact ? 6 : 8,
      runSpacing: 8,
      children: [
        _VoteChip(
          label: t['voteUp'],
          count: post.upvotes,
          active: myVote == 1,
          color: Brutal.lime,
          compact: compact,
          onTap: () => onVote(myVote == 1 ? 0 : 1),
        ),
        _VoteChip(
          label: t['voteDown'],
          count: post.downvotes,
          active: myVote == -1,
          color: Brutal.danger,
          compact: compact,
          onTap: () => onVote(myVote == -1 ? 0 : -1),
        ),
      ],
    );
  }
}

class _VoteChip extends StatelessWidget {
  const _VoteChip({
    required this.label,
    required this.count,
    required this.active,
    required this.color,
    required this.compact,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool active;
  final Color color;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fs = compact ? 10.0 : 13.0;
    return Semantics(
      button: true,
      selected: active,
      label: '$label $count',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 11, vertical: compact ? 4 : 8),
          decoration: BoxDecoration(
            color: active ? color : Brutal.paper,
            border: Border.all(color: Brutal.ink, width: compact ? 2 : 3),
            boxShadow: active ? Brutal.shadow(dx: 2, dy: 2) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: Brutal.label.copyWith(fontSize: fs)),
              SizedBox(width: compact ? 5 : 7),
              Text('$count', style: Brutal.display.copyWith(fontSize: fs + 3)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rank medal for the Hall of Fame.
class RankBadge extends StatelessWidget {
  const RankBadge({super.key, required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    const colors = [Brutal.yellow, Brutal.cyan, Brutal.orange];
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors[(rank - 1).clamp(0, colors.length - 1)],
        border: Brutal.outline,
        boxShadow: Brutal.shadow(dx: 2, dy: 2),
      ),
      child: Text('$rank', style: Brutal.display.copyWith(fontSize: 17)),
    );
  }
}

String relativeDate(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return '${d.day}.${d.month}.${d.year}';
}

/// Full-bleed error state with a retry.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    // Scrollable: server messages can run long, and this often renders inside a
    // short Expanded slot where a plain centred Column would overflow.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: BrutalBox(
          color: Brutal.danger,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(t['errorTitle'], style: Brutal.label.copyWith(fontSize: 17)),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: Brutal.body.copyWith(fontSize: 15)),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                BrutalButton(onPressed: onRetry, color: Brutal.paper, child: Text(t['tryAgain'])),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class Loading extends StatelessWidget {
  const Loading({super.key, this.label = 'MEASURING SEJBOSEJBO...'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(strokeWidth: 4, color: Brutal.ink),
          ),
          const SizedBox(height: 14),
          Text(label, style: Brutal.label.copyWith(fontSize: 13)),
        ],
      ),
    );
  }
}

/// Sticky brand header used at the top of every scrollable screen.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, required this.title, this.subtitle, this.showLogo = true});

  final String title;
  final String? subtitle;
  final bool showLogo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showLogo) ...[
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
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title.toUpperCase(), style: Brutal.display.copyWith(fontSize: 30)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: Brutal.body.copyWith(
                        fontSize: 13,
                        color: Brutal.ink.withValues(alpha: 0.65),
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
