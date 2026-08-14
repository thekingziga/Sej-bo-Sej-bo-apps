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
  static const _kVotePrefix = 'vote_';
  static const _kCommentVotePrefix = 'cvote_';
  static const _kFeedCache = 'feed_cache';
  static const _kFeedCachedAt = 'feed_cached_at';
  static const _kMyComments = 'my_comments';

  /// How many of our own comment ids to keep. The list only drives a "YOU" tag,
  /// so an unbounded one would grow forever to decorate threads nobody revisits.
  static const _maxRememberedComments = 300;

  static Future<Prefs> load() async => Prefs._(await SharedPreferences.getInstance());

  // -------------------------------------------------------------- language

  Lang get lang => _p.getString(_kLang) == 'sl' ? Lang.sl : Lang.en;

  Future<void> setLang(Lang l) => _p.setString(_kLang, l == Lang.sl ? 'sl' : 'en');

  // ------------------------------------------------------------- device id

  /// A random id minted on first launch and sent with votes so the server can
  /// reject duplicates. This is soft protection, not security: anyone can clear
  /// app data and vote again. The server must rate-limit by IP as well - see
  /// docs/API_PROMPT.md.
  String get deviceId {
    final existing = _p.getString(_kDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final r = Random.secure();
    final id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    _p.setString(_kDeviceId, id);
    return id;
  }

  // ----------------------------------------------------------------- votes

  /// -1, 0 or 1. Kept locally so the buttons show your own choice immediately,
  /// including offline and before the server round trip lands.
  int voteFor(int postId) => _p.getInt('$_kVotePrefix$postId') ?? 0;

  Future<void> setVote(int postId, int value) async {
    if (value == 0) {
      await _p.remove('$_kVotePrefix$postId');
    } else {
      await _p.setInt('$_kVotePrefix$postId', value);
    }
  }

  /// Same as [voteFor], for a comment. Kept under its own key prefix: comment
  /// ids and post ids are separate sequences, so sharing one would have comment
  /// 7 inherit post 7's vote.
  int commentVoteFor(int commentId) => _p.getInt('$_kCommentVotePrefix$commentId') ?? 0;

  Future<void> setCommentVote(int commentId, int value) async {
    if (value == 0) {
      await _p.remove('$_kCommentVotePrefix$commentId');
    } else {
      await _p.setInt('$_kCommentVotePrefix$commentId', value);
    }
  }

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
