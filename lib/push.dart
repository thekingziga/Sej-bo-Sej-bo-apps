import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api.dart';
import 'l10n.dart';
import 'prefs.dart';

/// Fires when a notification is tapped, with the post id it points at.
typedef PostOpener = void Function(int postId);

/// New-post notifications.
///
/// Everything here is best-effort. Push is a nicety layered on an app that
/// works fine without it, so a missing Firebase config, a denied permission or
/// an offline register must never surface as an error or delay a launch.
class Push {
  Push({required this.api, required this.prefs, required this.onOpenPost});

  final Api api;
  final Prefs prefs;
  final PostOpener onOpenPost;

  /// Android drops notifications silently on 8+ if the channel does not exist
  /// before the first message arrives, so it is declared in the manifest and
  /// named here for FCM to target.
  static const channelId = 'sejbosejbo_posts';

  bool _started = false;

  /// True once the server confirmed it can actually deliver. Not used to gate
  /// anything - tokens registered while this is false are kept and receive the
  /// first notification once Firebase credentials are installed server-side.
  bool deliveryEnabled = false;

  Future<void> start() async {
    if (_started || kIsWeb) return;
    _started = true;

    try {
      await Firebase.initializeApp();
    } catch (_) {
      return; // No Firebase config in this build; nothing else can work.
    }

    try {
      final messaging = FirebaseMessaging.instance;

      // Android 13+ needs POST_NOTIFICATIONS; older Android grants implicitly.
      // Asking is harmless where it is already granted.
      final settings = await messaging.requestPermission();
      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;

      // Taps are wired up regardless of permission: a user who declined can
      // still be sent here by a deep link, and re-granting later needs no
      // second wiring.
      _wireTaps(messaging);

      if (!granted || !prefs.pushEnabled) return;
      await _registerCurrentToken(messaging);

      // Tokens rotate - on reinstall, restore, or at Firebase's discretion -
      // and a stale one is a notification that goes nowhere.
      messaging.onTokenRefresh.listen((token) {
        if (prefs.pushEnabled) _register(token);
      });
    } catch (_) {
      // Play Services missing, Firebase unreachable, permission dialog failing:
      // none are worth bothering the user about.
    }
  }

  void _wireTaps(FirebaseMessaging messaging) {
    // Tapped while the app was in the background but alive.
    FirebaseMessaging.onMessageOpenedApp.listen(_openFrom);

    // Tapped while the app was not running at all. This one is easy to miss:
    // the message is delivered once, at startup, and never appears on a stream.
    messaging.getInitialMessage().then((m) {
      if (m != null) _openFrom(m);
    });
  }

  void _openFrom(RemoteMessage message) {
    final raw = message.data['post_id'];
    final id = raw is String ? int.tryParse(raw) : (raw as num?)?.toInt();
    // Deliberately keyed off data.post_id rather than parsing data.url: the id
    // is the thing the app needs, and a URL could point anywhere.
    if (id != null) onOpenPost(id);
  }

  Future<void> _registerCurrentToken(FirebaseMessaging messaging) async {
    final token = await messaging.getToken();
    if (token != null) await _register(token);
  }

  Future<void> _register(String token) async {
    try {
      deliveryEnabled = await api.registerPush(
        token: token,
        platform: defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        lang: prefs.lang == Lang.sl ? 'sl' : 'en',
      );
      await prefs.setPushToken(token);
    } catch (_) {
      // Includes the 30/hour limit. Registration is idempotent and runs again
      // next launch, so there is nothing to retry in a loop over.
    }
  }

  /// Turns notifications on or off from settings.
  ///
  /// Returns whether the change stuck, so the UI can put a toggle back rather
  /// than claim a state the server does not share.
  Future<bool> setEnabled(bool on) async {
    await prefs.setPushEnabled(on);
    try {
      if (on) {
        await Firebase.initializeApp();
        final messaging = FirebaseMessaging.instance;
        final settings = await messaging.requestPermission();
        if (settings.authorizationStatus == AuthorizationStatus.denied) {
          await prefs.setPushEnabled(false);
          return false;
        }
        await _registerCurrentToken(messaging);
        return true;
      }

      // Unregister the token we last registered, not whatever Firebase reports
      // now - they can differ after a rotation, and the server knows the old one.
      final token = prefs.pushToken ?? await FirebaseMessaging.instance.getToken();
      if (token != null) await api.unregisterPush(token);
      await prefs.setPushToken(null);
      return true;
    } catch (_) {
      return false;
    }
  }
}
