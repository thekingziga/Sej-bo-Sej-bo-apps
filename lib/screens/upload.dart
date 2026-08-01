import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
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

  bool get _valid =>
      _title.text.trim().isNotEmpty && (_story.text.trim().isNotEmpty || _picked != null);

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

  Future<void> _submit() async {
    if (!_valid || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final post = await widget.api.createPost(
        title: _title.text.trim(),
        description: _story.text.trim(),
        imagePath: kIsWeb ? null : _picked?.path,
        imageBytes: kIsWeb ? _preview : null,
        imageName: _picked?.name,
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
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 34),
        children: [
          const BrandHeader(
            title: 'Submit',
            subtitle: 'Image, GIF, or just a cursed story. Anonymous by design.',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PickerZone(
                  preview: _preview,
                  onCamera: () => _pick(ImageSource.camera),
                  onGallery: () => _pick(ImageSource.gallery),
                  onClear: () => setState(() {
                    _picked = null;
                    _preview = null;
                  }),
                ),
                const SizedBox(height: 22),
                _Field(
                  label: 'Title',
                  hint: 'Microwaved a salad',
                  controller: _title,
                  maxLength: 120,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 18),
                _Field(
                  label: 'Description or story',
                  hint: 'What happened? Why was it like this?',
                  controller: _story,
                  maxLength: 1200,
                  maxLines: 5,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                if (!_valid)
                  Text(
                    'Needs a title, plus either a photo or a story.',
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
                      : const Text('SUBMIT THIS SEJBOSEJBO', style: TextStyle(fontSize: 17)),
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
    required this.onClear,
  });

  final Uint8List? preview;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
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
          Row(
            children: [
              BrutalButton(
                color: Brutal.cyan,
                onPressed: onGallery,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: const Text('CHANGE'),
              ),
              const SizedBox(width: 10),
              BrutalButton(
                color: Brutal.danger,
                onPressed: onClear,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: const Text('REMOVE'),
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
              'ADD A PHOTO OR GIF',
              textAlign: TextAlign.center,
              style: Brutal.label.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 3),
            Text(
              'optional — a story alone also counts',
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
                    child: const Text('CAMERA'),
                  ),
                BrutalButton(
                  color: Brutal.cyan,
                  onPressed: onGallery,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: const Text('LIBRARY'),
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
