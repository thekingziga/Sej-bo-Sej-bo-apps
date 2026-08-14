import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n.dart';
import 'models.dart';
import 'prefs.dart';
import 'report.dart';
import 'theme.dart';
import 'widgets.dart';

/// The comment thread under a post: list, pager and composer.
///
/// Built as a plain Column rather than its own scrollable, because it lives
/// inside the detail screen's ListView - a nested scroll view here would need
/// a fixed height, and a thread has no natural one.
class CommentsSection extends StatefulWidget {
  const CommentsSection({
    super.key,
    required this.api,
    required this.postId,
    this.prefs,
    this.onCountChanged,
  });

  final Api api;
  final int postId;
  final Prefs? prefs;

  /// Fires with the new total after a successful post, so the detail screen can
  /// move its counter without refetching the post.
  final ValueChanged<int>? onCountChanged;

  @override
  State<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  final _items = <Comment>[];
  final _controller = TextEditingController();
  final _focus = FocusNode();

  int _page = 1;
  bool _hasNext = false;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _sending = false;
  String? _loadError;
  String? _sendError;
  Set<int> _mine = const {};

  /// Mirror of the persisted comment votes, so the buttons show your own choice
  /// without a Prefs read on every rebuild.
  final _votes = <int, int>{};

  @override
  void initState() {
    super.initState();
    _mine = widget.prefs?.myComments ?? const {};
    // Keeps the send button's enabled state in sync with the field.
    _controller.addListener(_onTyped);
    _load();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTyped)
      ..dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTyped() => setState(() {});

  bool get _canSend => _controller.text.trim().isNotEmpty && !_sending;

  /// Optimistic, with rollback - the same contract as post voting, because a
  /// count that visibly lags behind the tap reads as broken.
  Future<void> _vote(Comment comment, int value) async {
    final i = _items.indexWhere((c) => c.id == comment.id);
    if (i < 0) return;

    final previous = widget.prefs?.commentVoteFor(comment.id) ?? _votes[comment.id] ?? 0;
    final before = _items[i];
    final next = applyVoteDelta(before.upvotes, before.downvotes, previous, value);

    setState(() {
      _votes[comment.id] = value;
      _items[i] = before.copyWith(upvotes: next.up, downvotes: next.down);
    });
    await widget.prefs?.setCommentVote(comment.id, value);

    try {
      final updated = await widget.api.voteComment(comment.id, value);
      if (!mounted) return;
      final j = _items.indexWhere((c) => c.id == comment.id);
      if (j >= 0) setState(() => _items[j] = updated);
    } catch (_) {
      if (!mounted) return;
      final j = _items.indexWhere((c) => c.id == comment.id);
      setState(() {
        _votes[comment.id] = previous;
        if (j >= 0) _items[j] = before;
      });
      await widget.prefs?.setCommentVote(comment.id, previous);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final page = await widget.api.comments(widget.postId);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        for (final c in page.items) {
          _votes[c.id] = widget.prefs?.commentVoteFor(c.id) ?? 0;
        }
        _page = page.page;
        _hasNext = page.hasNext;
        _total = page.total;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _more() async {
    if (_loadingMore || !_hasNext) return;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.api.comments(widget.postId, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        for (final c in page.items) {
          _votes[c.id] = widget.prefs?.commentVoteFor(c.id) ?? 0;
        }
        _page = page.page;
        _hasNext = page.hasNext;
        _total = page.total;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = '$e');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _send() async {
    if (!_canSend) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });

    final t = L10n.of(context);
    try {
      final created = await widget.api.addComment(widget.postId, _controller.text);
      await widget.prefs?.rememberComment(created.id);
      if (!mounted) return;
      setState(() {
        // Appended, not refetched: the thread is oldest-first, so a new comment
        // always belongs at the end. Refetching would also throw away anything
        // the user has scrolled past.
        _items.add(created);
        _total += 1;
        _mine = {..._mine, created.id};
        _controller.clear();
        _sending = false;
      });
      _focus.unfocus();
      widget.onCountChanged?.call(_total);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Brutal.lime,
          content: Text(t['commentSent'], style: Brutal.body.copyWith(fontSize: 15)),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _sendError = '$e';
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(t['comments'].toUpperCase(), style: Brutal.label.copyWith(fontSize: 20)),
            const SizedBox(width: 8),
            if (!_loading)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: Brutal.cyan,
                  border: Border.all(color: Brutal.ink, width: 2),
                ),
                child: Text('$_total', style: Brutal.display.copyWith(fontSize: 14)),
              ),
          ],
        ),
        const SizedBox(height: 12),

        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3, color: Brutal.ink),
              ),
            ),
          )
        else if (_loadError != null && _items.isEmpty)
          BrutalBox(
            color: Brutal.danger,
            dx: 3,
            dy: 3,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t['commentsFailed'], style: Brutal.body.copyWith(fontSize: 14)),
                const SizedBox(height: 10),
                BrutalButton(
                  color: Brutal.paper,
                  onPressed: _load,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Text(t['tryAgain'], style: Brutal.label.copyWith(fontSize: 12)),
                ),
              ],
            ),
          )
        else if (_items.isEmpty)
          BrutalBox(
            color: Brutal.paperDeep,
            dx: 3,
            dy: 3,
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
            child: Text(
              t['commentsEmpty'],
              textAlign: TextAlign.center,
              style: Brutal.body.copyWith(fontSize: 15),
            ),
          )
        else
          for (var i = 0; i < _items.length; i++) ...[
            _CommentTile(
              comment: _items[i],
              mine: _mine.contains(_items[i].id),
              youLabel: t['commentYou'],
              myVote: _votes[_items[i].id] ?? 0,
              onVote: (v) => _vote(_items[i], v),
              onReport: () => showReportSheet(
                context,
                api: widget.api,
                id: _items[i].id,
                target: ReportTarget.comment,
              ),
              reportLabel: t['reportComment'],
            ),
            const SizedBox(height: 10),
          ],

        if (_hasNext) ...[
          const SizedBox(height: 2),
          BrutalButton(
            color: Brutal.paper,
            onPressed: _loadingMore ? null : _more,
            padding: const EdgeInsets.symmetric(vertical: 12),
            expand: true,
            child: _loadingMore
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 3, color: Brutal.ink),
                  )
                : Text(t['commentsMore'], style: Brutal.label.copyWith(fontSize: 13)),
          ),
        ],

        const SizedBox(height: 16),
        _Composer(
          controller: _controller,
          focus: _focus,
          hint: t['commentHint'],
          sendLabel: t['commentSend'],
          sending: _sending,
          onSend: _canSend ? _send : null,
        ),

        if (_sendError != null) ...[
          const SizedBox(height: 10),
          BrutalBox(
            color: Brutal.danger,
            dx: 3,
            dy: 3,
            padding: const EdgeInsets.all(12),
            child: Text(_sendError!, style: Brutal.body.copyWith(fontSize: 14)),
          ),
        ],
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.mine,
    required this.youLabel,
    required this.myVote,
    required this.onVote,
    required this.onReport,
    required this.reportLabel,
  });

  final Comment comment;
  final bool mine;
  final String youLabel;
  final int myVote;
  final ValueChanged<int> onVote;
  final VoidCallback onReport;
  final String reportLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: mine ? Brutal.yellow : Brutal.paper,
        border: Brutal.outline,
        boxShadow: Brutal.shadow(dx: 3, dy: 3),
      ),
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (mine) ...[BrutalTag(youLabel, color: Brutal.orange), const SizedBox(width: 7)],
              Expanded(
                child: Text(
                  relativeDate(comment.createdAt),
                  style: Brutal.body.copyWith(
                    fontSize: 12,
                    color: Brutal.ink.withValues(alpha: 0.6),
                  ),
                ),
              ),
              // Store policy again: user content needs a report path from
              // inside the app, and a comment is user content as much as a
              // post is. Icon-only to keep the tile header on one line.
              Semantics(
                button: true,
                label: reportLabel,
                child: GestureDetector(
                  onTap: onReport,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
                    child: Icon(
                      Icons.flag_outlined,
                      size: 15,
                      color: Brutal.ink.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // No maxLines: a comment is capped at 1000 characters server-side, so
          // the worst case is a tall tile, not an unbounded one.
          Text(comment.body, style: Brutal.body.copyWith(fontSize: 15)),
          const SizedBox(height: 10),
          // The same VoteBar as posts, in compact form: identical semantics,
          // including that re-tapping the active direction withdraws.
          VoteBar.forComment(comment: comment, myVote: myVote, onVote: onVote),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focus,
    required this.hint,
    required this.sendLabel,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final String hint;
  final String sendLabel;
  final bool sending;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Brutal.paper,
            border: Brutal.outline,
            boxShadow: Brutal.shadow(dx: 3, dy: 3),
          ),
          child: TextField(
            controller: controller,
            focusNode: focus,
            // Enforced here as well as server-side so an over-long comment is
            // stopped in the field rather than after a failed round trip.
            maxLength: Comment.maxLength,
            maxLines: 4,
            minLines: 2,
            textInputAction: TextInputAction.newline,
            style: Brutal.body.copyWith(fontSize: 15),
            cursorColor: Brutal.ink,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: Brutal.body.copyWith(
                fontSize: 15,
                color: Brutal.ink.withValues(alpha: 0.35),
              ),
              // The default counter only appears near the limit and sits
              // outside the border; the box below shows it consistently.
              counterText: '',
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (_, value, _) {
                  final used = value.text.characters.length;
                  final near = used > Comment.maxLength - 100;
                  return Text(
                    '$used / ${Comment.maxLength}',
                    style: Brutal.body.copyWith(
                      fontSize: 12,
                      color: near ? Brutal.ink : Brutal.ink.withValues(alpha: 0.5),
                      fontWeight: near ? FontWeight.w700 : FontWeight.w400,
                    ),
                  );
                },
              ),
            ),
            BrutalButton(
              color: onSend == null ? Brutal.paperDeep : Brutal.lime,
              onPressed: onSend,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 3, color: Brutal.ink),
                    )
                  : Text(sendLabel, style: Brutal.label.copyWith(fontSize: 14)),
            ),
          ],
        ),
      ],
    );
  }
}
