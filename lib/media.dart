import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'l10n.dart';
import 'models.dart';
import 'music.dart';
import 'theme.dart';

/// Players for the media kinds a post can carry.
///
/// These live on the detail screen only. A feed shows [MediaPoster] instead:
/// a video can be 500MB, and a list that eagerly opened every one would burn
/// a data plan just by being scrolled.
///
/// Everything here branches on `kind`, never on the URL extension - the server
/// re-encodes large videos overnight and the extension is not the contract.

/// Stand-in for a playable file in a list. Draws nothing from the network.
class MediaPoster extends StatelessWidget {
  const MediaPoster({super.key, required this.post, required this.compact});

  final Post post;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final audio = post.isAudio;
    return Container(
      color: audio ? Brutal.cyan : Brutal.ink,
      alignment: Alignment.center,
      padding: EdgeInsets.all(compact ? 8 : 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            audio ? Icons.graphic_eq : Icons.play_circle_fill,
            size: compact ? 34 : 64,
            color: audio ? Brutal.ink : Brutal.paper,
          ),
          if (!compact) ...[
            const SizedBox(height: 10),
            Text(
              post.title.toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Brutal.display.copyWith(
                fontSize: 20,
                color: audio ? Brutal.ink : Brutal.paper,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Streams a video. Nothing is fetched until [initState]; the file is streamed
/// progressively rather than downloaded, and playback starts only on a tap.
class PostVideoPlayer extends StatefulWidget {
  const PostVideoPlayer({super.key, required this.post, this.music});

  final Post post;

  /// Paused while this plays, so the theme music and a post are never audible
  /// at the same time.
  final Music? music;

  @override
  State<PostVideoPlayer> createState() => _PostVideoPlayerState();
}

class _PostVideoPlayerState extends State<PostVideoPlayer> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final url = widget.post.imageUrl;
    if (url == null || url.isEmpty) {
      setState(() => _failed = true);
      return;
    }
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await controller.initialize();
      await controller.setLooping(false);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onTick);
      setState(() => _controller = controller);
    } catch (_) {
      await controller.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  /// Hands the music back when the clip stops of its own accord.
  void _onTick() {
    final c = _controller;
    if (c == null) return;
    if (!c.value.isPlaying && !c.value.isBuffering) widget.music?.resume();
  }

  Future<void> _toggle() async {
    final c = _controller;
    if (c == null) return;
    if (c.value.isPlaying) {
      await c.pause();
      await widget.music?.resume();
    } else {
      await widget.music?.suspend();
      await c.play();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    widget.music?.resume();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return _MediaError(post: widget.post);

    final c = _controller;
    if (c == null) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: Brutal.ink,
          child: Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 3, color: Brutal.paper),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: _toggle,
      child: AspectRatio(
        aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(c),
            if (!c.value.isPlaying)
              const DecoratedBox(
                decoration: BoxDecoration(color: Colors.black38),
                child: Center(
                  child: Icon(Icons.play_circle_fill, size: 62, color: Brutal.paper),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: VideoProgressIndicator(
                c,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Brutal.orange,
                  bufferedColor: Brutal.paperDeep,
                  backgroundColor: Brutal.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Plays an audio post. Reuses audioplayers, already present for the theme
/// music, rather than adding a second audio stack.
class PostAudioPlayer extends StatefulWidget {
  const PostAudioPlayer({super.key, required this.post, this.music});

  final Post post;
  final Music? music;

  @override
  State<PostAudioPlayer> createState() => _PostAudioPlayerState();
}

class _PostAudioPlayerState extends State<PostAudioPlayer> {
  final _player = AudioPlayer();
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPlayerComplete.listen((_) {
      widget.music?.resume();
      if (mounted) {
        setState(() {
          _playing = false;
          _position = Duration.zero;
        });
      }
    });
  }

  Future<void> _toggle() async {
    final url = widget.post.imageUrl;
    if (url == null || url.isEmpty) {
      setState(() => _failed = true);
      return;
    }
    try {
      if (_playing) {
        await _player.pause();
        await widget.music?.resume();
      } else {
        await widget.music?.suspend();
        await _player.play(UrlSource(url));
      }
      if (mounted) setState(() => _playing = !_playing);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    widget.music?.resume();
    super.dispose();
  }

  static String _clock(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return _MediaError(post: widget.post);

    final total = _duration.inMilliseconds;
    final progress = total == 0 ? 0.0 : (_position.inMilliseconds / total).clamp(0.0, 1.0);

    return Container(
      color: Brutal.cyan,
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _toggle,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: Brutal.paper,
                    border: Brutal.outline,
                    boxShadow: Brutal.shadow(dx: 3, dy: 3),
                  ),
                  child: Icon(_playing ? Icons.pause : Icons.play_arrow, size: 28),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 12,
                      decoration: BoxDecoration(
                        color: Brutal.paper,
                        border: Border.all(color: Brutal.ink, width: 2),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: progress,
                        child: const ColoredBox(color: Brutal.orange),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_clock(_position)} / ${total == 0 ? '--:--' : _clock(_duration)}',
                      style: Brutal.body.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shown when a file will not open at all - a dead URL, an unsupported codec.
class _MediaError extends StatelessWidget {
  const _MediaError({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Brutal.paperDeep,
      padding: const EdgeInsets.all(22),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 34),
          const SizedBox(height: 10),
          Text(
            L10n.of(context)['mediaFailed'],
            textAlign: TextAlign.center,
            style: Brutal.body.copyWith(fontSize: 14),
          ),
        ],
      ),
    );
  }
}
