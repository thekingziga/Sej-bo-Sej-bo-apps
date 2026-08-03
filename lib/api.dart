import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'models.dart';
import 'prefs.dart';

/// Thrown for any non-2xx response or transport failure, with a message that is
/// safe to show the user.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Talks to the JSON API described in docs/API_PROMPT.md.
///
/// The endpoints do not exist on sejbosejbo.fyi yet. Until they ship, set
/// [useDemoData] (the default when [baseUrl] is empty) and the app runs on the
/// bundled sample feed so the UI is fully explorable.
class Api {
  Api({String? baseUrl, http.Client? client, bool? useDemoData, this.prefs})
    : baseUrl = (baseUrl ?? const String.fromEnvironment('API_BASE_URL')).trim(),
      _client = client ?? http.Client() {
    _demo = useDemoData ?? this.baseUrl.isEmpty;
  }

  final String baseUrl;
  final http.Client _client;
  late final bool _demo;

  /// Optional: supplies the device id for vote dedup and backs the offline cache.
  final Prefs? prefs;

  static const _timeout = Duration(seconds: 12);

  bool get isDemo => _demo;

  /// True when the last feed() call fell back to the cache.
  bool servedFromCache = false;

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    if (prefs != null) 'X-Device-Id': prefs!.deviceId,
  };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl/api/v1$path').replace(queryParameters: query);

  Future<Map<String, dynamic>> _getJson(String path, [Map<String, String>? query]) async {
    late http.Response res;
    try {
      res = await _client.get(_uri(path, query), headers: _headers).timeout(_timeout);
    } catch (e) {
      throw ApiException('Could not reach sejbosejbo.fyi. Check your connection.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException('Server said no (${res.statusCode}).', statusCode: res.statusCode);
    }
    try {
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Server sent something that was not JSON.');
    }
  }

  Future<Feed> feed({String lang = 'en'}) async {
    servedFromCache = false;
    if (_demo) return _demoFeed();

    try {
      final json = await _getJson('/feed', {'lang': lang});
      await prefs?.cacheFeed(json);
      return Feed.fromJson(json);
    } on ApiException {
      // Offline or server down: fall back to whatever we last saw rather than
      // dumping the user on an error screen. Rethrows if there is no cache.
      final cached = prefs?.cachedFeed;
      if (cached == null) rethrow;
      servedFromCache = true;
      return Feed.fromJson(cached);
    }
  }

  Future<PostPage> posts({
    int page = 1,
    int perPage = 24,
    String lang = 'en',
    PostSort sort = PostSort.newest,
  }) async {
    if (_demo) return _demoPage(page, sort);
    return PostPage.fromJson(
      await _getJson('/posts', {
        'page': '$page',
        'per_page': '$perPage',
        'lang': lang,
        'sort': sort.wire,
      }),
    );
  }

  /// Casts or clears a vote. [value] is 1 ("sej bo"), -1 ("sej ne bo") or 0 to
  /// undo. Returns the post with the server's authoritative counts.
  Future<Post> vote(int postId, int value) async {
    if (_demo) {
      await Future<void>.delayed(const Duration(milliseconds: 220));
      final p = _demoPosts.firstWhere((e) => e.id == postId);
      return p.copyWith(
        upvotes: p.upvotes + (value == 1 ? 1 : 0),
        downvotes: p.downvotes + (value == -1 ? 1 : 0),
      );
    }

    late http.Response res;
    try {
      res = await _client
          .post(
            _uri('/posts/$postId/vote'),
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode({'value': value}),
          )
          .timeout(_timeout);
    } catch (_) {
      throw ApiException('Could not register your vote. Check your connection.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException('Vote rejected (${res.statusCode}).', statusCode: res.statusCode);
    }
    return Post.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// Flags a post for manual review. Required by Google Play's UGC policy and
  /// Apple Guideline 1.2 - an app hosting user content must let users report it
  /// from inside the app.
  ///
  /// Deliberately sends no device id: the server treats repeat reports from one
  /// device as a stronger signal rather than abuse, unlike voting.
  Future<void> reportPost(int postId, ReportReason reason, {String? details}) async {
    if (_demo) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return;
    }

    late http.Response res;
    try {
      res = await _client
          .post(
            _uri('/posts/$postId/report'),
            headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
            body: jsonEncode({
              'reason': reason.wire,
              if (details != null && details.trim().isNotEmpty)
                'details': details.trim().substring(0, details.trim().length.clamp(0, 500)),
            }),
          )
          .timeout(_timeout);
    } catch (_) {
      throw ApiException('Could not send the report. Check your connection.');
    }

    if (res.statusCode == 429) {
      throw ApiException('Too many reports from this network. Try again later.', statusCode: 429);
    }
    if (res.statusCode == 404) {
      throw ApiException('That post no longer exists.', statusCode: 404);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String msg = 'Report rejected (${res.statusCode}).';
      try {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        if (j['error'] is String) msg = j['error'] as String;
      } catch (_) {}
      throw ApiException(msg, statusCode: res.statusCode);
    }
  }

  Future<String> randomPhrase({String lang = 'en'}) async {
    if (_demo) {
      _demoPhraseIndex = (_demoPhraseIndex + 1) % _demoPhrases.length;
      await Future<void>.delayed(const Duration(milliseconds: 260));
      return _demoPhrases[_demoPhraseIndex];
    }
    final j = await _getJson('/random-phrase', {'lang': lang});
    return (j['phrase'] ?? '') as String;
  }

  /// Multipart upload. [imagePath] is a local file path; null means text-only.
  /// On web, pass [imageBytes] + [imageName] instead.
  Future<Post> createPost({
    required String title,
    required String description,
    String? imagePath,
    Uint8List? imageBytes,
    String? imageName,
  }) async {
    if (_demo) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      throw ApiException(
        'Demo mode: the upload endpoint does not exist yet. '
        'Ship the API, then set API_BASE_URL.',
      );
    }

    final req = http.MultipartRequest('POST', _uri('/posts'))
      ..fields['title'] = title
      ..fields['description'] = description;

    // The content type must be set explicitly. package:http defaults every
    // multipart file to application/octet-stream, and the server's filter only
    // accepts image/jpeg|png|gif|webp - so uploads were rejected with "Only
    // images and GIFs are allowed" no matter what the user actually picked.
    if (imageBytes != null) {
      req.files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: imageName ?? 'upload.jpg',
          contentType: _sniffImageType(imageBytes),
        ),
      );
    } else if (imagePath != null && !kIsWeb) {
      final file = File(imagePath);
      // Sniff the magic bytes rather than trusting the extension: the picker
      // can hand back .jpg for a file that is actually a PNG or HEIC-converted.
      final head = await file.openRead(0, 16).expand((c) => c).toList();
      req.files.add(
        await http.MultipartFile.fromPath(
          'image',
          file.path,
          contentType: _sniffImageType(Uint8List.fromList(head)),
        ),
      );
    }

    late http.StreamedResponse streamed;
    try {
      // _client.send, not req.send(): BaseRequest.send() spins up its own
      // one-shot Client, which bypasses the injected client (so uploads could
      // not be tested) and discards the connection pool on every upload.
      streamed = await _client.send(req).timeout(const Duration(seconds: 60));
    } catch (_) {
      throw ApiException('Upload failed. Check your connection and try again.');
    }
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      String msg = 'Upload rejected (${streamed.statusCode}).';
      try {
        final j = jsonDecode(body) as Map<String, dynamic>;
        if (j['error'] is String) msg = j['error'] as String;
      } catch (_) {}
      throw ApiException(msg, statusCode: streamed.statusCode);
    }
    return Post.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// Asks the server for a Stripe Checkout URL. Desktop donation path.
  Future<String> createStripeCheckout({required String tierId}) async {
    if (_demo) {
      throw ApiException('Demo mode: no Stripe endpoint yet.');
    }
    late http.Response res;
    try {
      res = await _client
          .post(
            _uri('/donations/stripe/session'),
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({'tier_id': tierId}),
          )
          .timeout(_timeout);
    } catch (_) {
      throw ApiException('Could not start checkout. Check your connection.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException('Checkout failed (${res.statusCode}).', statusCode: res.statusCode);
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final url = j['url'] as String?;
    if (url == null || url.isEmpty) throw ApiException('Server did not return a checkout URL.');
    return url;
  }

  /// Hands a store receipt to the server so the donation can be recorded and,
  /// critically, verified against Apple/Google rather than trusted from the client.
  Future<void> verifyStorePurchase({
    required String platform,
    required String productId,
    required String token,
  }) async {
    if (_demo) return;
    try {
      await _client
          .post(
            _uri('/donations/$platform/verify'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'product_id': productId, 'token': token}),
          )
          .timeout(_timeout);
    } catch (_) {
      // Non-fatal: the store already took the money and the plugin will replay
      // unverified purchases on next launch.
    }
  }

  /// Identifies an image from its magic bytes. Falls back to JPEG, which is
  /// what phone cameras produce and what the server accepts most often - but
  /// the sniff should succeed for anything the picker or clipboard hands over.
  static MediaType _sniffImageType(Uint8List b) {
    bool starts(List<int> sig) {
      if (b.length < sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (b[i] != sig[i]) return false;
      }
      return true;
    }

    if (starts([0x89, 0x50, 0x4E, 0x47])) return MediaType('image', 'png');
    if (starts([0x47, 0x49, 0x46, 0x38])) return MediaType('image', 'gif');
    if (starts([0xFF, 0xD8, 0xFF])) return MediaType('image', 'jpeg');
    // WEBP is "RIFF" .... "WEBP" at offset 8.
    if (starts([0x52, 0x49, 0x46, 0x46]) &&
        b.length >= 12 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return MediaType('image', 'webp');
    }
    return MediaType('image', 'jpeg');
  }

  void close() => _client.close();

  // ---------------------------------------------------------------- demo data

  static int _demoPhraseIndex = 0;
  static const _demoPhrases = [
    'Certified Sejbosejbo',
    'Peak Sejbosejbo',
    'Brain.exe stopped working',
    'This cannot be unseen',
    'Maximum Sejbosejbo achieved',
    'Peak human intelligence',
    'Someone really thought this was a good idea',
  ];

  static final _now = DateTime.now();

  static Post _p(
    int id,
    String title,
    String desc, {
    bool img = true,
    int daysAgo = 0,
    bool feat = false,
    int up = 0,
    int down = 0,
  }) => Post(
    id: id,
    title: title,
    description: desc,
    kind: img ? 'image' : 'story',
    imageUrl: null, // demo mode draws placeholders instead of fetching
    featured: feat,
    pinned: false,
    createdAt: _now.subtract(Duration(days: daysAgo, hours: id * 3)),
    upvotes: up,
    downvotes: down,
  );

  static final _demoPosts = <Post>[
    _p(
      9,
      'Microwaved a salad',
      'It was warm. It was wrong. It was Sejbosejbo.',
      daysAgo: 0,
      feat: true,
      up: 128,
      down: 6,
    ),
    _p(
      8,
      'Installed Chrome to download Edge',
      'Then installed Edge to download Chrome.',
      daysAgo: 1,
      up: 342,
      down: 11,
    ),
    _p(
      7,
      'Asked if Wi-Fi is wireless electricity',
      'He was serious. That is the problem.',
      img: false,
      daysAgo: 2,
      up: 89,
      down: 24,
    ),
    _p(
      6,
      'Put the router in the fridge',
      'To cool down the internet.',
      daysAgo: 3,
      up: 511,
      down: 9,
    ),
    _p(
      5,
      'Printed an email to scan it',
      'And then emailed the scan back.',
      img: false,
      daysAgo: 5,
      up: 203,
      down: 41,
    ),
    _p(
      4,
      'Bought a screen protector for a mirror',
      'No further questions.',
      daysAgo: 8,
      up: 77,
      down: 3,
    ),
    _p(
      3,
      'Googled "how to google"',
      'It worked, which is the tragedy.',
      img: false,
      daysAgo: 11,
      up: 156,
      down: 12,
    ),
    _p(
      2,
      'Charged a wireless mouse to use it wirelessly',
      'With a cable. For six hours.',
      daysAgo: 14,
      up: 64,
      down: 18,
    ),
    _p(
      1,
      'Turned it off and on again. Forever.',
      'Still going. Send help.',
      img: false,
      daysAgo: 21,
      up: 22,
      down: 47,
    ),
  ];

  Future<Feed> _demoFeed() async {
    await Future<void>.delayed(const Duration(milliseconds: 420));
    return Feed(
      // Derived, not hardcoded, so the tile agrees with the "Nd ago" on the
      // hero card instead of contradicting it.
      stats: Stats(
        visits: 1337,
        uploads: _demoPosts.length,
        daysSinceLast: DateTime.now().difference(_demoPosts.first.createdAt).inDays,
      ),
      quote: "That's a certified Sejbosejbo.",
      daily: _demoPosts[2],
      posts: _demoPosts.take(4).toList(),
      top: _demoSorted(PostSort.top).take(3).toList(),
    );
  }

  static List<Post> _demoSorted(PostSort sort) {
    final list = [..._demoPosts];
    switch (sort) {
      case PostSort.newest:
        break; // already newest-first
      case PostSort.top:
        list.sort((a, b) => b.score.compareTo(a.score));
      case PostSort.featured:
        list.retainWhere((p) => p.featured);
    }
    return list;
  }

  Future<PostPage> _demoPage(int page, PostSort sort) async {
    await Future<void>.delayed(const Duration(milliseconds: 380));
    final source = _demoSorted(sort);
    const per = 6;
    final start = (page - 1) * per;
    if (start >= source.length) {
      return PostPage(items: const [], page: page, hasNext: false);
    }
    final end = (start + per).clamp(0, source.length);
    return PostPage(items: source.sublist(start, end), page: page, hasNext: end < source.length);
  }
}
