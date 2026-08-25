import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:file_selector/file_selector.dart' as fs;
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

  /// An audio or video pick. Kept apart from [_preview] because there is no
  /// image to show for it, and because a 500MB video must never be read into
  /// memory just to draw a thumbnail - only its path is held.
  _PickedMedia? _media;

  /// Bytes sent so far and the total, while an upload is in flight. A 500MB
  /// file takes minutes on mobile data, and an upload with no visible movement
  /// is indistinguishable from a hung one.
  double? _progress;

  @override
  void dispose() {
    _title.dispose();
    _story.dispose();
    super.dispose();
  }

  /// Typing anything clears a previous failure.
  ///
  /// The error box holds the server's own words - "Add a title and either an
  /// image/GIF or a story." - and picking a file cleared it, but typing did
  /// not. So a rejected submit left its complaint on screen while the user
  /// fixed exactly what it complained about, which reads as the app refusing
  /// input it has already accepted.
  void _onEdited() => setState(() => _error = null);

  /// Keyed off [_preview], not [_picked]: a pasted image has bytes but no XFile,
  /// so checking _picked would silently refuse to submit clipboard images.
  bool get _valid =>
      _title.text.trim().isNotEmpty &&
      (_story.text.trim().isNotEmpty || _preview != null || _media != null);

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await _picker.pickImage(source: source, maxWidth: 2400, imageQuality: 88);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _picked = file;
        _preview = bytes;
        _media = null; // one file per post
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open that image.');
    }
  }

  /// Picks an audio or video file. Deliberately reads only the size, never the
  /// contents: createPost streams from the path.
  Future<void> _pickMedia() async {
    try {
      final file = await fs.openFile(
        acceptedTypeGroups: const [
          fs.XTypeGroup(
            label: 'Audio & video',
            extensions: ['mp3', 'm4a', 'ogg', 'wav', 'weba', 'mp4', 'webm', 'mov'],
            mimeTypes: ['audio/*', 'video/*'],
            uniformTypeIdentifiers: ['public.audio', 'public.movie'],
          ),
        ],
      );
      if (file == null) return;
      final size = await file.length();
      if (!mounted) return;
      setState(() {
        _media = _PickedMedia(path: file.path, name: file.name, bytes: size);
        _picked = null;
        _preview = null;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not open that file.');
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

  /// Opens the crop/rotate editor on whatever is currently selected. Works for
  /// both picked files and pasted bytes - pasted images have no path, so they
  /// are written to a temp file first.
  Future<void> _edit() async {
    final bytes = _preview;
    if (bytes == null) return;
    final t = L10n.of(context);
    try {
      var path = _picked?.path;
      if (path == null) {
        final tmp = await File(
          '${Directory.systemTemp.path}/sejbo_edit_${DateTime.now().millisecondsSinceEpoch}.png',
        ).writeAsBytes(bytes);
        path = tmp.path;
      }

      final cropped = await ImageCropper().cropImage(
        sourcePath: path,
        compressQuality: 92,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: t['editPhoto'],
            toolbarColor: Brutal.yellow,
            toolbarWidgetColor: Brutal.ink,
            backgroundColor: Brutal.ink,
            activeControlsWidgetColor: Brutal.pink,
            // Free by default so tall screenshots are not forced square.
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
          ),
          IOSUiSettings(title: t['editPhoto'], aspectRatioLockEnabled: false),
        ],
      );
      if (cropped == null || !mounted) return;

      final edited = await File(cropped.path).readAsBytes();
      if (!mounted) return;
      setState(() {
        _preview = edited;
        // The edited file is the new source of truth; drop the original XFile
        // so submit() uploads the edit, not the untouched original.
        _picked = XFile(cropped.path);
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = t['editFailed']);
    }
  }

  Future<void> _submit() async {
    if (!_valid || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final media = _media;
      // Bytes only for clipboard images and on web. Everything else streams
      // from a path - reading a 500MB video into memory to upload it would
      // take the app out with it.
      final useBytes = media == null && (kIsWeb || _picked == null);
      final post = await widget.api.createPost(
        title: _title.text.trim(),
        description: _story.text.trim(),
        mediaPath: media?.path ?? (useBytes ? null : _picked!.path),
        mediaBytes: useBytes ? _preview : null,
        mediaName: media?.name ?? _picked?.name ?? 'pasted.png',
        lang: L10n.of(context).code,
        onProgress: (sent, total) {
          if (mounted && total > 0) setState(() => _progress = sent / total);
        },
      );
      if (!mounted) return;
      setState(() {
        _title.clear();
        _story.clear();
        _picked = null;
        _preview = null;
        _media = null;
      });
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _progress = null;
        });
      }
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
                  // image_picker only implements the camera source on iOS and
                  // Android. On Windows/macOS/Linux the button was showing but
                  // could never work, so hide it rather than offer a dead end.
                  showCamera:
                      !kIsWeb &&
                      (defaultTargetPlatform == TargetPlatform.iOS ||
                          defaultTargetPlatform == TargetPlatform.android),
                  onCamera: () => _pick(ImageSource.camera),
                  onGallery: () => _pick(ImageSource.gallery),
                  onPaste: _pasteFromClipboard,
                  onEdit: _edit,
                  media: _media,
                  onFile: _pickMedia,
                  onClear: () => setState(() {
                    _picked = null;
                    _preview = null;
                    _media = null;
                  }),
                ),
                const SizedBox(height: 22),
                _Field(
                  label: t['labelTitle'],
                  hint: t['hintTitle'],
                  controller: _title,
                  maxLength: 120,
                  onChanged: (_) => _onEdited(),
                ),
                const SizedBox(height: 18),
                _Field(
                  label: t['labelStory'],
                  hint: t['hintStory'],
                  controller: _story,
                  maxLength: 1200,
                  maxLines: 5,
                  onChanged: (_) => _onEdited(),
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
                      // Percentage, not a spinner. A 500MB video is minutes of
                      // work, and a spinner that never moves is how a user
                      // decides the app has hung and kills it mid-upload.
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: Brutal.ink,
                                value: _progress,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _progress == null
                                  ? t['uploading']
                                  : '${t['uploading']} ${(_progress! * 100).round()}%',
                              style: const TextStyle(fontSize: 15),
                            ),
                          ],
                        )
                      : Text(t['submitButton'], style: const TextStyle(fontSize: 17)),
                ),
                if (_sending && _media != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    t['uploadSlow'],
                    textAlign: TextAlign.center,
                    style: Brutal.body.copyWith(
                      fontSize: 12,
                      color: Brutal.ink.withValues(alpha: 0.6),
                    ),
                  ),
                ],
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
    required this.showCamera,
    required this.onCamera,
    required this.onGallery,
    required this.onPaste,
    required this.onEdit,
    required this.onClear,
    required this.media,
    required this.onFile,
  });

  final Uint8List? preview;

  /// An audio or video pick, shown as a chip rather than a thumbnail - there
  /// is nothing to draw, and decoding a 500MB file for a preview is not worth
  /// the memory.
  final _PickedMedia? media;
  final VoidCallback onFile;
  final bool showCamera;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onPaste;
  final VoidCallback onEdit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);

    final picked = media;
    if (picked != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrutalBox(
            color: Brutal.cyan,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.movie_creation_outlined, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        picked.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Brutal.heading.copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(picked.sizeLabel, style: Brutal.body.copyWith(fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              BrutalButton(
                color: Brutal.cyan,
                onPressed: onFile,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Text(t['change']),
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
                color: Brutal.yellow,
                onPressed: onEdit,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Text(t['edit']),
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
                if (showCamera)
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
                BrutalButton(
                  color: Brutal.pink,
                  onPressed: onFile,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Text(t['file']),
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


/// An audio or video pick: path and size only, never contents.
class _PickedMedia {
  const _PickedMedia({required this.path, required this.name, required this.bytes});

  final String path;
  final String name;
  final int bytes;

  String get sizeLabel {
    const mb = 1024 * 1024;
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}
