import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pasteboard/pasteboard.dart';

import '../api.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets.dart';
import 'detail.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key, required this.api});

  final Api api;

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _title = TextEditingController();
  final _story = TextEditingController();
  final _picker = ImagePicker();

  XFile? _picked;
  Uint8List? _preview;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _story.dispose();
    super.dispose();
  }

  /// Keyed off [_preview], not [_picked]: a pasted image has bytes but no XFile,
  /// so checking _picked would silently refuse to submit clipboard images.
  bool get _valid =>
      _title.text.trim().isNotEmpty && (_story.text.trim().isNotEmpty || _preview != null);

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await _picker.pickImage(source: source, maxWidth: 2400, imageQuality: 88);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _picked = file;
        _preview = bytes;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open that image.');
    }
  }

  /// Paste an image straight off the system clipboard - screenshot, copy, paste.
  /// This is the whole point on desktop, where there is no photo library.
  Future<void> _pasteFromClipboard() async {
    final t = L10n.of(context);
    try {
      final bytes = await Pasteboard.image;
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        setState(() => _error = t['clipboardEmpty']);
        return;
      }
      setState(() {
        _picked = null; // clipboard bytes have no XFile backing
        _preview = bytes;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = t['clipboardEmpty']);
    }
  }

  Future<void> _submit() async {
    if (!_valid || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      // Send raw bytes on web, and whenever the image came from the clipboard
      // (no file on disk to point at). Otherwise stream the picked file.
      final useBytes = kIsWeb || _picked == null;
      final post = await widget.api.createPost(
        title: _title.text.trim(),
        description: _story.text.trim(),
        imagePath: useBytes ? null : _picked!.path,
        imageBytes: useBytes ? _preview : null,
        imageName: _picked?.name ?? 'pasted.png',
      );
      if (!mounted) return;
      setState(() {
        _title.clear();
        _story.clear();
        _picked = null;
        _preview = null;
      });
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 34),
        children: [
          BrandHeader(title: t['uploadTitle'], subtitle: t['uploadSub']),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              // stretch, not start: the picker zone and the image preview size
              // themselves to their content, so with `start` they came out
              // narrower than the text fields below and the column looked ragged.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PickerZone(
                  preview: _preview,
                  onCamera: () => _pick(ImageSource.camera),
                  onGallery: () => _pick(ImageSource.gallery),
                  onPaste: _pasteFromClipboard,
                  onClear: () => setState(() {
                    _picked = null;
                    _preview = null;
                  }),
                ),
                const SizedBox(height: 22),
                _Field(
                  label: t['labelTitle'],
                  hint: t['hintTitle'],
                  controller: _title,
                  maxLength: 120,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 18),
                _Field(
                  label: t['labelStory'],
                  hint: t['hintStory'],
                  controller: _story,
                  maxLength: 1200,
                  maxLines: 5,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                if (!_valid)
                  Text(
                    t['needsMore'],
                    style: Brutal.body.copyWith(
                      fontSize: 13,
                      color: Brutal.ink.withValues(alpha: 0.6),
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  BrutalBox(
                    color: Brutal.danger,
                    dx: 3,
                    dy: 3,
                    padding: const EdgeInsets.all(13),
                    child: Text(_error!, style: Brutal.body.copyWith(fontSize: 14)),
                  ),
                ],
                const SizedBox(height: 20),
                BrutalButton(
                  expand: true,
                  color: _valid ? Brutal.pink : Brutal.paperDeep,
                  onPressed: _valid && !_sending ? _submit : null,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: _sending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 3, color: Brutal.ink),
                        )
                      : Text(t['submitButton'], style: const TextStyle(fontSize: 17)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerZone extends StatelessWidget {
  const _PickerZone({
    required this.preview,
    required this.onCamera,
    required this.onGallery,
    required this.onPaste,
    required this.onClear,
  });

  final Uint8List? preview;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onPaste;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    if (preview != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Brutal.ink, width: 4),
              boxShadow: Brutal.shadow(dx: 6, dy: 6),
            ),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Image.memory(preview!, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              BrutalButton(
                color: Brutal.cyan,
                onPressed: onGallery,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Text(t['change']),
              ),
              BrutalButton(
                color: Brutal.lime,
                onPressed: onPaste,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Text(t['paste']),
              ),
              BrutalButton(
                color: Brutal.danger,
                onPressed: onClear,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Text(t['remove']),
              ),
            ],
          ),
        ],
      );
    }

    // Dashed drop-zone, echoing the website's dashed example box.
    //
    // Sized by its content rather than a fixed height, and the buttons Wrap:
    // at 360pt the two buttons plus their hard shadows do not fit on one line,
    // and a fixed 190pt box could not hold them once they took two.
    return CustomPaint(
      painter: _DashPainter(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📸', style: TextStyle(fontSize: 38)),
            const SizedBox(height: 10),
            Text(
              t['addPhoto'],
              textAlign: TextAlign.center,
              style: Brutal.label.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 3),
            Text(
              t['addPhotoSub'],
              textAlign: TextAlign.center,
              style: Brutal.body.copyWith(fontSize: 12, color: Brutal.ink.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 12,
              children: [
                if (!kIsWeb)
                  BrutalButton(
                    color: Brutal.yellow,
                    onPressed: onCamera,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    child: Text(t['camera']),
                  ),
                BrutalButton(
                  color: Brutal.cyan,
                  onPressed: onGallery,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Text(t['library']),
                ),
                BrutalButton(
                  color: Brutal.lime,
                  onPressed: onPaste,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Text(t['paste']),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Brutal.ink
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    const dash = 12.0, gap = 8.0;
    final path = Path()..addRect(Offset.zero & size);
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, (d + dash).clamp(0, m.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    required this.maxLength,
    this.maxLines = 1,
    this.onChanged,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final int maxLength;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: Brutal.label.copyWith(fontSize: 13)),
        const SizedBox(height: 7),
        Container(
          decoration: BoxDecoration(
            color: Brutal.paper,
            border: Brutal.outline,
            boxShadow: Brutal.shadow(dx: 4, dy: 4),
          ),
          child: TextField(
            controller: controller,
            maxLength: maxLength,
            maxLines: maxLines,
            onChanged: onChanged,
            style: Brutal.body.copyWith(fontSize: 17),
            cursorColor: Brutal.ink,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: Brutal.body.copyWith(
                fontSize: 17,
                color: Brutal.ink.withValues(alpha: 0.35),
              ),
              counterText: '',
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
            ),
          ),
        ),
      ],
    );
  }
}
