import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'prefs.dart';

/// The website's background theme, brought across.
///
/// Deliberately **off by default**, unlike the website. A browser cannot start
/// unmuted audio until the visitor clicks something, so the site's "default on"
/// is really "on once you interact". An app has no such brake: music at launch
/// would cut off whatever the user was already listening to, which is a far
/// ruder thing to do on a phone than in a tab.
class Music {
  Music(this.prefs);

  final Prefs prefs;

  /// Matches the website's 0.3 - loud enough to notice, quiet enough to talk
  /// over.
  static const volume = 0.3;

  static const _asset = 'audio/theme.m4a';

  AudioPlayer? _player;

  /// Held down while a post's own audio or video is playing. Distinct from the
  /// stored preference: the user still wants music, it just must not be
  /// audible underneath a clip they chose to play.
  bool _suspended = false;

  /// True while the track should be sounding. Not the same as "the user wants
  /// music": playback is suspended while the app is in the background, and
  /// this goes false without touching the stored preference.
  bool get playing => _player != null;

  bool get enabled => prefs.musicEnabled;

  Future<void> start() async {
    if (!enabled) return;
    await _play();
  }

  /// True while we are waiting for the player to initialize and play.
  bool _starting = false;

  Future<void> _play() async {
    if (_player != null || kIsWeb || _suspended || _starting) return;
    _starting = true;
    try {
      final player = AudioPlayer();
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setVolume(volume);
      await player.play(AssetSource(_asset));
      _player = player;
    } catch (_) {
      // A device that cannot play it is not a device that should crash over it.
      _player = null;
    } finally {
      _starting = false;
    }
  }

  Future<void> _stop() async {
    final player = _player;
    _player = null;
    if (player == null) return;
    try {
      await player.stop();
      await player.dispose();
    } catch (_) {}
  }

  /// User flipped the switch. Persists, so the choice survives a restart the
  /// way it does on the website.
  Future<void> setEnabled(bool on) async {
    await prefs.setMusicEnabled(on);
    if (on) {
      await _play();
    } else {
      await _stop();
    }
  }

  /// Silences the music for as long as something else is playing.
  ///
  /// Two audio streams at once is never what anyone wanted, and the theme
  /// under someone's video is the worst version of it.
  Future<void> suspend() async {
    _suspended = true;
    await _stop();
  }

  /// Gives the music back after a clip finishes, is paused, or its screen is
  /// closed. Does nothing if the user had music off to begin with.
  Future<void> resume() async {
    if (!_suspended) return;
    _suspended = false;
    if (enabled) await _play();
  }

  /// Called when the app leaves or returns to the foreground.
  ///
  /// Music that keeps playing after the app is backgrounded reads as the app
  /// having hijacked the phone, and it is the fastest way to earn an uninstall.
  Future<void> handleLifecycle({required bool foreground}) async {
    if (!enabled) return;
    if (foreground) {
      await _play();
    } else {
      await _stop();
    }
  }

  Future<void> dispose() => _stop();
}
