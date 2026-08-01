import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

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
  Api({String? baseUrl, http.Client? client, bool? useDemoData})
    : baseUrl = (baseUrl ?? const String.fromEnvironment('API_BASE_URL')).trim(),
      _client = client ?? http.Client() {
    _demo = useDemoData ?? this.baseUrl.isEmpty;
  }

  final String baseUrl;
  final http.Client _client;
  late final bool _demo;

  static const _timeout = Duration(seconds: 12);

  bool get isDemo => _demo;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl/api/v1$path').replace(queryParameters: query);

  Future<Map<String, dynamic>> _getJson(String path, [Map<String, String>? query]) async {
    late http.Response res;
    try {
      res = await _client
          .get(_uri(path, query), headers: {'Accept': 'application/json'})
          .timeout(_timeout);
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
    if (_demo) return _demoFeed();
    return Feed.fromJson(await _getJson('/feed', {'lang': lang}));
  }

  Future<PostPage> posts({int page = 1, int perPage = 24, String lang = 'en'}) async {
    if (_demo) return _demoPage(page);
    return PostPage.fromJson(
      await _getJson('/posts', {'page': '$page', 'per_page': '$perPage', 'lang': lang}),
    );
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

    if (imageBytes != null) {
      req.files.add(
        http.MultipartFile.fromBytes('image', imageBytes, filename: imageName ?? 'upload.jpg'),
      );
    } else if (imagePath != null && !kIsWeb) {
      req.files.add(await http.MultipartFile.fromPath('image', File(imagePath).path));
    }

    late http.StreamedResponse streamed;
    try {
      streamed = await req.send().timeout(const Duration(seconds: 60));
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
  }) => Post(
    id: id,
    title: title,
    description: desc,
    kind: img ? 'image' : 'story',
    imageUrl: null, // demo mode draws placeholders instead of fetching
    featured: feat,
    pinned: false,
    createdAt: _now.subtract(Duration(days: daysAgo, hours: id * 3)),
  );

  static final _demoPosts = <Post>[
    _p(
      9,
      'Microwaved a salad',
      'It was warm. It was wrong. It was Sejbosejbo.',
      daysAgo: 0,
      feat: true,
    ),
    _p(
      8,
      'Installed Chrome to download Edge',
      'Then installed Edge to download Chrome.',
      daysAgo: 1,
    ),
    _p(
      7,
      'Asked if Wi-Fi is wireless electricity',
      'He was serious. That is the problem.',
      img: false,
      daysAgo: 2,
    ),
    _p(6, 'Put the router in the fridge', 'To cool down the internet.', daysAgo: 3),
    _p(5, 'Printed an email to scan it', 'And then emailed the scan back.', img: false, daysAgo: 5),
    _p(4, 'Bought a screen protector for a mirror', 'No further questions.', daysAgo: 8),
    _p(3, 'Googled "how to google"', 'It worked, which is the tragedy.', img: false, daysAgo: 11),
    _p(
      2,
      'Charged a wireless mouse to use it wirelessly',
      'With a cable. For six hours.',
      daysAgo: 14,
    ),
    _p(
      1,
      'Turned it off and on again. Forever.',
      'Still going. Send help.',
      img: false,
      daysAgo: 21,
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
    );
  }

  Future<PostPage> _demoPage(int page) async {
    await Future<void>.delayed(const Duration(milliseconds: 380));
    const per = 6;
    final start = (page - 1) * per;
    if (start >= _demoPosts.length) {
      return PostPage(items: const [], page: page, hasNext: false);
    }
    final end = (start + per).clamp(0, _demoPosts.length);
    return PostPage(
      items: _demoPosts.sublist(start, end),
      page: page,
      hasNext: end < _demoPosts.length,
    );
  }
}
