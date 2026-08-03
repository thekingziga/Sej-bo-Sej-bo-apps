import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n.dart';
import 'models.dart';
import 'theme.dart';

/// In-app content reporting.
///
/// This is not a nice-to-have: Google Play's User Generated Content policy and
/// Apple's Guideline 1.2 both require an app that hosts user submissions to
/// provide a way to flag them from inside the app. Without it the listing can
/// be rejected or pulled after the fact.
///
/// Opens as a modal sheet so it works from any screen without a route change.
Future<void> showReportSheet(BuildContext context, {required Api api, required Post post}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReportSheet(api: api, post: post),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.api, required this.post});

  final Api api;
  final Post post;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  ReportReason? _reason;
  final _details = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  String _label(Strings t, ReportReason r) => switch (r) {
    ReportReason.spam => t['reasonSpam'],
    ReportReason.inappropriate => t['reasonInappropriate'],
    ReportReason.harassment => t['reasonHarassment'],
    ReportReason.copyright => t['reasonCopyright'],
    ReportReason.other => t['reasonOther'],
  };

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });

    final t = L10n.of(context);
    try {
      await widget.api.reportPost(widget.post.id, reason, details: _details.text);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Brutal.lime,
          content: Text(
            t['reportThanks'],
            style: Brutal.body.copyWith(fontSize: 15, color: Brutal.ink),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    // Padding for the keyboard, so the details field is never covered.
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Brutal.paper,
            border: Border.all(color: Brutal.ink, width: 4),
            boxShadow: Brutal.shadow(dx: 6, dy: 6),
          ),
          padding: const EdgeInsets.all(18),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t['reportTitle'], style: Brutal.display.copyWith(fontSize: 24)),
                const SizedBox(height: 6),
                Text(
                  t['reportSub'],
                  style: Brutal.body.copyWith(
                    fontSize: 14,
                    color: Brutal.ink.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 16),

                for (final r in ReportReason.values) ...[
                  _ReasonRow(
                    label: _label(t, r),
                    selected: _reason == r,
                    onTap: () => setState(() => _reason = r),
                  ),
                  const SizedBox(height: 8),
                ],

                const SizedBox(height: 8),
                Text(t['reportDetails'], style: Brutal.label.copyWith(fontSize: 12)),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: Brutal.paper,
                    border: Brutal.outline,
                    boxShadow: Brutal.shadow(dx: 3, dy: 3),
                  ),
                  child: TextField(
                    controller: _details,
                    maxLength: 500,
                    maxLines: 3,
                    style: Brutal.body.copyWith(fontSize: 15),
                    cursorColor: Brutal.ink,
                    decoration: InputDecoration(
                      hintText: t['reportDetailsHint'],
                      hintStyle: Brutal.body.copyWith(
                        fontSize: 15,
                        color: Brutal.ink.withValues(alpha: 0.35),
                      ),
                      counterText: '',
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
                    ),
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  BrutalBox(
                    color: Brutal.danger,
                    dx: 3,
                    dy: 3,
                    padding: const EdgeInsets.all(12),
                    child: Text(_error!, style: Brutal.body.copyWith(fontSize: 14)),
                  ),
                ],

                const SizedBox(height: 16),
                BrutalButton(
                  expand: true,
                  // Disabled until a reason is picked: the server 400s without
                  // one, so there is no point letting the request leave.
                  color: _reason == null ? Brutal.paperDeep : Brutal.danger,
                  onPressed: _reason == null || _sending ? null : _send,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 3, color: Brutal.ink),
                        )
                      : Text(t['reportSend']),
                ),
                const SizedBox(height: 10),
                BrutalButton(
                  expand: true,
                  color: Brutal.paper,
                  onPressed: _sending ? null : () => Navigator.of(context).pop(),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(t['reportCancel']),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReasonRow extends StatelessWidget {
  const _ReasonRow({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? Brutal.yellow : Brutal.paper,
          border: Brutal.outline,
          boxShadow: selected ? Brutal.shadow(dx: 3, dy: 3) : null,
        ),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: selected ? Brutal.ink : Brutal.paper,
                border: Border.all(color: Brutal.ink, width: 3),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: Brutal.heading.copyWith(fontSize: 15))),
          ],
        ),
      ),
    );
  }
}
