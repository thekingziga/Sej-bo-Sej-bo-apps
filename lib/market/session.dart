import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api.dart';
import 'models.dart';

/// Where the marketplace login token is kept between launches.
abstract interface class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

/// The Android Keystore / iOS Keychain, not shared preferences: the token is a
/// credential for someone's listings and private messages, and preferences are
/// plain text that Android's auto-backup copies off the device.
///
/// Every failure reads as "not signed in". A Keystore key does not survive a
/// restore onto a new phone, so after one the stored value cannot be decrypted;
/// `resetOnError` (the default) wipes it, and the catch covers whatever else a
/// platform can throw. The cost is one more login - never a crash.
class SecureTokenStore implements TokenStore {
  const SecureTokenStore();

  static const _key = 'market_token';
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read() async {
    try {
      final v = await _storage.read(key: _key);
      return (v == null || v.isEmpty) ? null : v;
    } catch (_) {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(String token) async {
    try {
      await _storage.write(key: _key, value: token);
    } catch (_) {
      // Signed in for this run, but not remembered. Not worth failing a login over.
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}

/// For tests, and for anywhere without a keystore.
class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this._token]);
  String? _token;

  @override
  Future<String?> read() async => _token;
  @override
  Future<void> write(String token) async => _token = token;
  @override
  Future<void> clear() async => _token = null;
}

/// Who is signed in to the marketplace, if anyone.
///
/// The one place that knows when a token has died. Every authenticated call
/// goes through [authed], so a 401 anywhere - an expired session, a password
/// change on another device, an account deleted on the website - signs the app
/// out once, here, instead of each screen discovering it differently.
class MarketSession extends ChangeNotifier {
  MarketSession({required this.api, this.store = const SecureTokenStore()});

  final Api api;
  final TokenStore store;

  String? _token;
  Me? _me;
  bool _restored = false;

  /// Holding a token. The account itself ([me]) can still be unknown: after an
  /// offline start the token is kept but has not been read back yet.
  bool get signedIn => _token != null;

  /// Signed in, account known, display name picked - what selling and
  /// messaging need.
  bool get ready => signedIn && (_me?.hasName ?? false);

  /// True once [restore] has finished, so a screen can tell "not signed in"
  /// from "not checked yet" and not flash a login button at someone who is.
  bool get restored => _restored;

  Me? get me => _me;
  int get unreadCount => _me?.unreadCount ?? 0;

  bool? _available;

  /// Whether this server has the marketplace at all. Null until asked.
  ///
  /// The tab only appears once this is true, so an app released before the
  /// website ships the API shows no marketplace rather than a tab that says
  /// "not yet" - and the day the API goes live, installs that are already out
  /// there light it up on their next launch, with no app update.
  bool? get available => _available;

  /// Asks the server, cheaply, whether the marketplace exists. Only a definite
  /// answer changes anything: "unavailable" hides it, any listings show it, and
  /// an offline start leaves things as they were rather than flapping the tab.
  Future<void> probe({String lang = 'en'}) async {
    try {
      await api.listings(perPage: 1, lang: lang);
      if (_available != true) {
        _available = true;
        notifyListeners();
      }
    } on ApiException catch (e) {
      if (e.code == 'unavailable' && _available != false) {
        _available = false;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Picks up a token from a previous run and checks it still works.
  ///
  /// Only a definite "no" signs out. If the server cannot be reached the token
  /// is kept and the user still looks signed in - an app opened on a train must
  /// not log people out.
  Future<void> restore({String lang = 'en'}) async {
    try {
      final token = await store.read();
      if (token == null) return;
      _token = token;
      try {
        _me = await api.me(token, lang: lang);
      } on ApiException catch (e) {
        if (_isDead(e)) {
          await _forget();
        } else {
          // Unreachable or not deployed: keep the token, so the person stays
          // signed in. The account is read back the next time it is needed.
          _me = null;
        }
      }
    } finally {
      _restored = true;
      notifyListeners();
    }
  }

  Future<void> requestCode(String email, {String lang = 'en'}) =>
      api.requestLoginCode(email, lang: lang);

  Future<void> verifyCode(String email, String code, {String lang = 'en'}) async {
    final r = await api.verifyLoginCode(email, code, lang: lang);
    _token = r.token;
    _me = r.me;
    await store.write(r.token);
    notifyListeners();
  }

  Future<void> setName(String name, {String lang = 'en'}) async {
    _me = await authed((t) => api.updateMe(t, name: name, lang: lang));
    notifyListeners();
  }

  Future<void> setNotify(bool on, {String lang = 'en'}) async {
    _me = await authed((t) => api.updateMe(t, notify: on, lang: lang));
    notifyListeners();
  }

  /// Makes sure the account is known before something that needs the name.
  /// Throws if it cannot be read - offline, say - so the caller can say so.
  Future<Me> ensureMe({String lang = 'en'}) async {
    final known = _me;
    if (known != null) return known;
    final me = await authed((t) => api.me(t, lang: lang));
    _me = me;
    notifyListeners();
    return me;
  }

  /// Re-reads the account, mostly for the unread badge. Silent on failure.
  Future<void> refresh({String lang = 'en'}) async {
    final token = _token;
    if (token == null) return;
    try {
      _me = await authed((t) => api.me(t, lang: lang));
      notifyListeners();
    } catch (_) {}
  }

  /// Signs out here and tells the server to revoke the token. The local half
  /// always happens, even offline: the person asked to be signed out.
  Future<void> signOut() async {
    final token = _token;
    await _forget();
    if (token != null) {
      try {
        await api.logout(token);
      } catch (_) {}
    }
  }

  /// Deletes the account on the server - listings, photos, conversations,
  /// messages - and then forgets it here. Unlike [signOut], the server half
  /// must succeed first: if it fails, the person is still signed in and can see
  /// that their account still exists, instead of believing it is gone.
  Future<void> deleteAccount({String lang = 'en'}) async {
    await authed((t) => api.deleteAccount(t, lang: lang));
    await _forget();
  }

  /// Runs an authenticated call. A 401 means the token is gone for good, so
  /// the session ends and the error still reaches the caller to show.
  Future<T> authed<T>(Future<T> Function(String token) call) async {
    final token = _token;
    if (token == null) {
      throw ApiException('Please log in.', statusCode: 401, code: 'unauthorized');
    }
    try {
      return await call(token);
    } on ApiException catch (e) {
      if (_isDead(e)) await _forget();
      rethrow;
    }
  }

  static bool _isDead(ApiException e) => e.statusCode == 401 || e.code == 'unauthorized';

  Future<void> _forget() async {
    _token = null;
    _me = null;
    await store.clear();
    notifyListeners();
  }

  /// Lets a test start signed in without a round trip.
  @visibleForTesting
  void debugSignIn(String token, Me me) {
    _token = token;
    _me = me;
    _restored = true;
    notifyListeners();
  }
}
