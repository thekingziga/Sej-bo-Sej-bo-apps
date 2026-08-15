import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../comments.dart';
import '../l10n.dart';
import '../models.dart';
import '../prefs.dart';
import '../report.dart';
import '../theme.dart';
import '../widgets.dart';

class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, required this.post, this.api, this.prefs})
    : id = null;

  /// Deep-link entry point: opens on an id and fetches the post itself.
  const PostDetailScreen.byId({
    super.key,
    required Api this.api,
    required Prefs this.prefs,
    required int this.id,
  }) : post = null;

  final Post? post;
  final int? id;
  final Api? api;
  final Prefs? prefs;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  Post? _post;
  int _myVote = 0;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    if (_post != null) {
      _myVote = _post!.myVote ?? 0;
    } else {
      _fetch();
    }
  }

  Future<void> _fetch() async {
    final api = widget.api;
    final id = widget.id;
    if (api == null || id == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await api.posts(perPage: 50);
      final found = page.items.where((p) => p.id == id).firstOrNull;
      if (!mounted) return;
      setState(() {
        _post = found;
        _myVote = found?.myVote ?? 0;
        if (found == null) _error = 'That Sejbosejbo could not be found.';
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _vote(int value) async {
    final post = _post;
    final api = widget.api;
    if (post == null) return;

    // Optimistic: move the counts now, revert if the server disagrees.
    final previous = _myVote;
    final before = post;
    setState(() {
      _myVote = value;
      _post = _applyVoteLocally(post, previous, value);
    });

    if (api == null) return;
    try {
      final updated = await api.vote(post.id, value);
      if (mounted) {
        setState(() {
          _post = updated;
          _myVote = updated.myVote ?? value;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _myVote = previous;
        _post = before;
      });
    }
  }

  /// Applies the delta of moving from [from] to [to] without waiting on the API.
  static Post _applyVoteLocally(Post p, int from, int to) {
    final next = applyVoteDelta(p.upvotes, p.downvotes, from, to);
    return p.copyWith(upvotes: next.up, downvotes: next.down);
  }

  Future<void> _share() async {
    final post = _post;
    if (post == null) return;
    final t = L10n.of(context);
    final url = post.shareUrl(widget.api?.baseUrl ?? '');
    await SharePlus.instance.share(
      ShareParams(text: '${post.title} — ${t['shareText']}\n$url', subject: post.title),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final post = _post;

    return Scaffold(
      backgroundColor: Brutal.paper,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              title: post == null ? 'SEJBOSEJBO' : 'SEJBOSEJBO #${post.id}',
              onBack: () => Navigator.of(context).maybePop(),
              onShare: post == null ? null : _share,
              shareLabel: t['share'],
            ),
            Expanded(
              child: _loading
                  ? const Loading()
                  : post == null
                  ? ErrorState(message: _error ?? '...', onRetry: _fetch)
                  : _body(post, t),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(Post post, Strings t) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
    children: [
      Text(post.title, style: Brutal.display.copyWith(fontSize: 36)),
      const SizedBox(height: 14),
      Container(
        decoration: BoxDecoration(
          color: Brutal.paperDeep,
          border: Border.all(color: Brutal.ink, width: 4),
          boxShadow: Brutal.shadow(dx: 7, dy: 7),
        ),
        // BoxFit.contain, not cover. Most posts are phone screenshots - tall
        // and narrow - and cover was cropping the top and bottom off, which is
        // usually where the punchline is. Capped at 78% of the screen so a very
        // tall image still leaves the votes and title reachable.
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: 180,
            maxHeight: MediaQuery.of(context).size.height * 0.78,
          ),
          child: PostMedia(
            post: post,
            accent: Brutal.orange,
            compact: false,
            fit: BoxFit.contain,
          ),
        ),
      ),
      // Audio and video are built server-side and ship behind a flag. An older
      // install must not pretend it can play them - it sends the user to the
      // website, which always can.
      if (post.isUnsupported) ...[
        const SizedBox(height: 14),
        BrutalBox(
          color: Brutal.yellow,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t['unsupportedTitle'], style: Brutal.label.copyWith(fontSize: 14)),
              const SizedBox(height: 6),
              Text(t['unsupportedBody'], style: Brutal.body.copyWith(fontSize: 14)),
              const SizedBox(height: 12),
              BrutalButton(
                color: Brutal.paper,
                onPressed: () => launchUrl(
                  Uri.parse(post.shareUrl(widget.api?.baseUrl ?? '')),
                  mode: LaunchMode.externalApplication,
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(t['openOnWeb'], style: Brutal.label.copyWith(fontSize: 13)),
              ),
            ],
          ),
        ),
      ],
      if (post.description.isNotEmpty && !post.isStory) ...[
        const SizedBox(height: 18),
        Text(post.description, style: Brutal.body.copyWith(fontSize: 17)),
      ],
      const SizedBox(height: 20),
      VoteBar.forPost(post: post, myVote: _myVote, onVote: _vote),
      const SizedBox(height: 16),
      Row(
        children: [
          if (post.featured) ...[BrutalTag(t['featured']), const SizedBox(width: 8)],
          if (post.pinned) ...[
            BrutalTag(t['pinned'], color: Brutal.cyan),
            const SizedBox(width: 8),
          ],
          Text(
            relativeDate(post.createdAt),
            style: Brutal.body.copyWith(fontSize: 13, color: Brutal.ink.withValues(alpha: 0.65)),
          ),
        ],
      ),
      const SizedBox(height: 20),
      // Required by Play's UGC policy and Apple Guideline 1.2: users must be
      // able to flag content from inside the app.
      Align(
        alignment: Alignment.centerLeft,
        child: BrutalButton(
          color: Brutal.paper,
          onPressed: widget.api == null
              ? null
              : () => showReportSheet(context, api: widget.api!, id: post.id),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.flag_outlined, size: 15),
              const SizedBox(width: 6),
              Text(t['report'], style: Brutal.label.copyWith(fontSize: 12)),
            ],
          ),
        ),
      ),
      const SizedBox(height: 28),
      if (widget.api != null) ...[
        CommentsSection(
          // Keyed by post id so opening a different post from a deep link
          // rebuilds the thread instead of showing the previous post's.
          key: ValueKey('comments-${post.id}'),
          api: widget.api!,
          postId: post.id,
          prefs: widget.prefs,
          onCountChanged: (n) {
            if (mounted) setState(() => _post = _post?.copyWith(commentCount: n));
          },
        ),
        const SizedBox(height: 28),
      ],
      Transform.rotate(
        angle: -0.03,
        child: BrutalBox(
          color: Brutal.lime,
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
          child: Center(
            child: Text(
              t['officially'],
              textAlign: TextAlign.center,
              style: Brutal.display.copyWith(fontSize: 26),
            ),
          ),
        ),
      ),
    ],
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.onBack,
    required this.onShare,
    required this.shareLabel,
  });

  final String title;
  final VoidCallback onBack;
  final VoidCallback? onShare;
  final String shareLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 16, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
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
          Expanded(child: Text(title, style: Brutal.label.copyWith(fontSize: 14))),
          if (onShare != null)
            BrutalButton(
              color: Brutal.cyan,
              onPressed: onShare,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.ios_share, size: 15),
                  const SizedBox(width: 5),
                  Text(shareLabel, style: Brutal.label.copyWith(fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
