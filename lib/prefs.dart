import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'l10n.dart';

/// Everything the app remembers between launches. Deliberately one small class
/// over SharedPreferences - there is no account system and nothing here is
/// sensitive.
class Prefs {
  Prefs._(this._p);

  final SharedPreferences _p;

  static const _kLang = 'lang';
  static const _kDeviceId = 'device_id';
  static const _kFeedCache = 'feed_cache';
  static const _kFeedCachedAt = 'feed_cached_at';
  static const _kMyComments = 'my_comments';
  static const _kPushOn = 'push_enabled';
  static const _kPushToken = 'push_token';

  /// How many of our own comment ids to keep. The list only drives a "YOU" tag,
  /// so an unbounded one would grow forever to decorate threads nobody revisits.
  static const _maxRememberedComments = 300;

  static Future<Prefs> load() async => Prefs._(await SharedPreferences.getInstance());

  // -------------------------------------------------------------- language

  Lang get lang => _p.getString(_kLang) == 'sl' ? Lang.sl : Lang.en;

  Future<void> setLang(Lang l) => _p.setString(_kLang, l == Lang.sl ? 'sl' : 'en');

  // ------------------------------------------------------------- device id

  /// Ids the server minted and signed itself carry this prefix.
  static const _signedPrefix = 'v1_';

  /// Whether the stored id is one the server signed.
  ///
  /// A locally generated id is just a string the client chose, so anyone could
  /// send a fresh one per request and vote without limit. The server will
  /// eventually refuse unsigned ids outright; until then both work.
  bool get hasSignedDeviceId => (_p.getString(_kDeviceId) ?? '').startsWith(_signedPrefix);

  /// Replaces the stored id with one the server minted.
  ///
  /// Note this changes who the server thinks this install is, so any votes cast
  /// under the old id stop being attributed to it. That is unavoidable when
  /// moving from a self-chosen id to a signed one, and is the lesser cost:
  /// keeping the old id would break voting entirely once the server starts
  /// requiring signatures.
  Future<void> setDeviceId(String id) => _p.setString(_kDeviceId, id);

  /// The id sent with votes, comments and reads.
  ///
  /// Falls back to a locally generated random id, which the server still
  /// accepts, when it has never managed to mint a signed one - offline first
  /// run, or the mint endpoint being rate limited.
  String get deviceId {
    final existing = _p.getString(_kDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final r = Random.secure();
    final id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    _p.setString(_kDeviceId, id);
    return id;
  }

  // ----------------------------------------------------------------- votes
  //
  // There is no local vote ledger any more. The server returns `my_vote` on
  // every read that carries an X-Device-Id, so the app asks rather than
  // remembers. The old ledger was wrong on a fresh install - reinstall and
  // every post read as unvoted, which also let you vote a second time.

  // -------------------------------------------------------------- comments

  /// Ids of comments written on this device. Comments are anonymous on the
  /// wire - the server never says who wrote what - so the only way to badge
  /// your own is to remember them locally.
  Set<int> get myComments =>
      (_p.getStringList(_kMyComments) ?? const []).map(int.tryParse).nonNulls.toSet();

  Future<void> rememberComment(int id) async {
    final list = _p.getStringList(_kMyComments) ?? <String>[];
    if (list.contains('$id')) return;
    list.add('$id');
    if (list.length > _maxRememberedComments) {
      list.removeRange(0, list.length - _maxRememberedComments);
    }
    await _p.setStringList(_kMyComments, list);
  }

  // ---------------------------------------------------------- notifications

  /// Whether the user wants new-post notifications.
  ///
  /// Defaults to true: permission is still asked for separately by the OS, so
  /// this only records a later decision to turn them back off. A null here
  /// would be indistinguishable from "off" and would silently opt everyone out.
  bool get pushEnabled => _p.getBool(_kPushOn) ?? true;

  Future<void> setPushEnabled(bool on) => _p.setBool(_kPushOn, on);

  /// The last FCM token we registered, kept so it can be unregistered even
  /// after Firebase has rotated or deleted the live one.
  String? get pushToken => _p.getString(_kPushToken);

  Future<void> setPushToken(String? token) async {
    if (token == null) {
      await _p.remove(_kPushToken);
    } else {
      await _p.setString(_kPushToken, token);
    }
  }

  // ----------------------------------------------------------- feed cache

  Future<void> cacheFeed(Map<String, dynamic> json) async {
    await _p.setString(_kFeedCache, jsonEncode(json));
    await _p.setInt(_kFeedCachedAt, DateTime.now().millisecondsSinceEpoch);
  }

  Map<String, dynamic>? get cachedFeed {
    final raw = _p.getString(_kFeedCache);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  DateTime? get cachedFeedAt {
    final ms = _p.getInt(_kFeedCachedAt);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }
}
