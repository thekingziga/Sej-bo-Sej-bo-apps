import 'dart:async';
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
  ApiException(this.message, {this.statusCode, this.retryAfter});

  final String message;
  final int? statusCode;

  /// How long until a rate limit frees up, when the server said so. Computed
  /// server-side from a sliding window, so it is when a slot genuinely opens -
  /// worth showing as a countdown rather than letting the user hammer the
  /// button, which only extends the block.
  final Duration? retryAfter;

  @override
  String toString() => message;

  /// Reads the limit from a 429. The header is authoritative and is present on
  /// every limited endpoint; the JSON body carries the same number and is the
  /// fallback for any proxy that strips headers.
  static Duration? _retryAfterOf(http.Response res) {
    final header = int.tryParse(res.headers['retry-after'] ?? '');
    if (header != null && header > 0) return Duration(seconds: header);
    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final body = (j['retry_after_seconds'] as num?)?.toInt();
      if (body != null && body > 0) return Duration(seconds: body);
    } catch (_) {}
    return null;
  }

  /// Builds the exception for a rate-limited response, preferring the server's
  /// own wording since it is already human-readable and localised to the limit
  /// that was actually hit.
  factory ApiException.rateLimited(http.Response res, String fallback) {
    var message = fallback;
    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      if (j['error'] is String) message = j['error'] as String;
    } catch (_) {}
    return ApiException(message, statusCode: 429, retryAfter: _retryAfterOf(res));
  }
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

  /// Sent on **reads as well as writes**. The server keys `my_vote` off this
  /// header, and omits the field entirely without it - so a read that skipped
  /// the header would come back permanently "unknown" and the vote buttons
  /// would render blank for content this device has already voted on.
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
      final previous = _demoPostVotes[postId] ?? 0;
      final next = applyVoteDelta(p.upvotes, p.downvotes, previous, value);
      _demoPostVotes[postId] = value;
      final updated = p.copyWith(upvotes: next.up, downvotes: next.down, myVote: value);
      _demoPosts[_demoPosts.indexOf(p)] = updated;
      return updated;
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

  /// One page of a post's comment thread.
  ///
  /// [perPage] is clamped to what the server allows rather than sent blind, so
  /// asking for 500 returns a predictable 100 instead of quietly disagreeing
  /// with the pager. The returned page carries the sort the server *applied*,
  /// which is not necessarily the one requested.
  Future<CommentPage> comments(
    int postId, {
    int page = 1,
    int perPage = 50,
    CommentSort sort = CommentSort.oldest,
  }) async {
    if (_demo) return _demoComments(postId, page, sort);
    return CommentPage.fromJson(
      await _getJson('/posts/$postId/comments', {
        'page': '$page',
        'per_page': '${perPage.clamp(1, CommentPage.maxPerPage)}',
        'sort': sort.wire,
      }),
    );
  }

  /// Posts an anonymous comment and returns it as the server stored it.
  ///
  /// The device id goes along - optional here, unlike voting - purely so this
  /// install can recognise its own comments later. The server never exposes it,
  /// so comments stay anonymous to everyone including us.
  Future<Comment> addComment(int postId, String body) async {
    final text = body.trim();
    if (text.isEmpty) throw ApiException('Write something first.');
    if (text.length > Comment.maxLength) {
      throw ApiException('That is longer than ${Comment.maxLength} characters.');
    }

    if (_demo) {
      await Future<void>.delayed(const Duration(milliseconds: 320));
      final list = _demoThreads.putIfAbsent(postId, () => []);
      final c = Comment(
        id: DateTime.now().millisecondsSinceEpoch,
        postId: postId,
        body: text,
        createdAt: DateTime.now(),
      );
      list.add(c);
      return c;
    }

    late http.Response res;
    try {
      res = await _client
          .post(
            _uri('/posts/$postId/comments'),
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode({'body': text}),
          )
          .timeout(_timeout);
    } catch (_) {
      throw ApiException('Could not post your comment. Check your connection.');
    }

    if (res.statusCode == 429) {
      throw ApiException.rateLimited(res, 'Slow down - too many comments from this network.');
    }
    if (res.statusCode == 404) {
      throw ApiException('That post no longer exists.', statusCode: 404);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      // The 400s carry a useful message ("Comment is too long (max 1000
      // characters).") - prefer the server's wording over inventing our own.
      String msg = 'Comment rejected (${res.statusCode}).';
      try {
        final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        if (j['error'] is String) msg = j['error'] as String;
      } catch (_) {}
      throw ApiException(msg, statusCode: res.statusCode);
    }

    return Comment.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// Votes on a comment. Same semantics as [vote]: 1, -1, or 0 to withdraw.
  ///
  /// Unlike posting a comment, the device id is **required** here - the server
  /// 400s without a valid one. That is checked up front rather than discovered
  /// from a failed request, because a missing [prefs] is a wiring mistake in
  /// this app, not something the user can act on.
  Future<Comment> voteComment(int commentId, int value) async {
    if (_demo) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return _demoVoteComment(commentId, value);
    }

    if (prefs == null) {
      throw ApiException('Cannot vote without a device id.');
    }

    late http.Response res;
    try {
      res = await _client
          .post(
            _uri('/comments/$commentId/vote'),
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode({'value': value}),
          )
          .timeout(_timeout);
    } catch (_) {
      throw ApiException('Could not register your vote. Check your connection.');
    }

    if (res.statusCode == 429) {
      throw ApiException.rateLimited(res, 'Slow down - too many votes from this network.');
    }
    if (res.statusCode == 404) {
      throw ApiException('That comment no longer exists.', statusCode: 404);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException('Vote rejected (${res.statusCode}).', statusCode: res.statusCode);
    }
    return Comment.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// Flags a post for manual review. Required by Google Play's UGC policy and
  /// Apple Guideline 1.2 - an app hosting user content must let users report it
  /// from inside the app.
  ///
  /// Deliberately sends no device id: the server treats repeat reports from one
  /// device as a stronger signal rather than abuse, unlike voting.
  Future<void> reportPost(int postId, ReportReason reason, {String? details}) =>
      report(ReportTarget.post, postId, reason, details: details);

  /// Same, for a comment. Comments are user content too, so the store policies
  /// that force in-app reporting cover them just as much as posts do.
  Future<void> reportComment(int commentId, ReportReason reason, {String? details}) =>
      report(ReportTarget.comment, commentId, reason, details: details);

  Future<void> report(
    ReportTarget target,
    int id,
    ReportReason reason, {
    String? details,
  }) async {
    if (_demo) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return;
    }

    late http.Response res;
    try {
      res = await _client
          .post(
            _uri('/${target.path}/$id/report'),
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
      throw ApiException.rateLimited(res, 'Too many reports from this network.');
    }
    if (res.statusCode == 404) {
      throw ApiException(
        target == ReportTarget.comment
            ? 'That comment no longer exists.'
            : 'That post no longer exists.',
        statusCode: 404,
      );
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

  /// Registers this install's FCM token for new-post notifications.
  ///
  /// Idempotent - re-registering only refreshes `last_seen` - so it is called
  /// on every launch and on every token rotation.
  ///
  /// Returns the server's `delivery_enabled`, which reports whether it has
  /// Firebase credentials yet. **The caller must not gate registration on it
  /// or show the user an error**: tokens collected while delivery is off are
  /// kept, and those installs get the first notification once it is switched
  /// on.
  Future<bool> registerPush({
    required String token,
    required String platform,
    required String lang,
  }) async {
    if (_demo) return false;
    final res = await _client
        .post(
          _uri('/push/register'),
          headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
          body: jsonEncode({'token': token, 'platform': platform, 'lang': lang}),
        )
        .timeout(_timeout);

    if (res.statusCode == 429) {
      throw ApiException.rateLimited(res, 'Too many attempts. Try again later.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String msg = 'Could not turn notifications on (${res.statusCode}).';
      try {
        final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        if (j['error'] is String) msg = j['error'] as String;
      } catch (_) {}
      throw ApiException(msg, statusCode: res.statusCode);
    }
    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return j['delivery_enabled'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Stops notifications for this token. Called when the user turns them off.
  Future<void> unregisterPush(String token) async {
    if (_demo) return;
    final res = await _client
        .post(
          _uri('/push/unregister'),
          headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
          body: jsonEncode({'token': token}),
        )
        .timeout(_timeout);
    if (res.statusCode == 429) {
      throw ApiException.rateLimited(res, 'Too many attempts. Try again later.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(
        'Could not turn notifications off (${res.statusCode}).',
        statusCode: res.statusCode,
      );
    }
  }

  /// Asks the server to mint a signed device id.
  ///
  /// Returns null on any failure, including the 10-per-hour mint limit, so the
  /// caller can keep using the locally generated id - which the server still
  /// accepts. Never call this on every launch: a new id each time reads as a
  /// new person and throws away the user's voting history.
  Future<String?> mintDeviceId() async {
    if (_demo) return null;
    late http.Response res;
    try {
      res = await _client
          .post(_uri('/device'), headers: {'Accept': 'application/json'})
          .timeout(_timeout);
    } catch (_) {
      return null;
    }
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final id = j['device_id'];
      return (id is String && id.trim().isNotEmpty) ? id.trim() : null;
    } catch (_) {
      return null;
    }
  }

  /// Asks the server which app versions it still supports.
  ///
  /// Returns null on **any** failure - endpoint missing, server down, offline,
  /// malformed JSON. That is deliberate and is the most important line in this
  /// method: the caller uses the result to decide whether to lock the user out,
  /// so a check that failed closed would brick every install the moment the Pi
  /// hiccupped, with no way to ship a fix except through the store.
  Future<AppRelease?> release() async {
    if (_demo) return null;
    try {
      return AppRelease.fromJson(await _getJson('/app-version'));
    } catch (_) {
      return null;
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

  /// What the server accepts, per kind. Checked before a byte leaves the
  /// device: discovering a 413 after pushing 500MB up a phone connection is a
  /// uniquely miserable way to learn a file is too big.
  static const maxImageBytes = 100 * 1024 * 1024;
  static const maxAudioVideoBytes = 500 * 1024 * 1024;

  /// Multipart upload. [mediaPath] is a local file path; null means text-only.
  /// On web, pass [mediaBytes] + [mediaName] instead.
  ///
  /// The wire field is still called `image` for every kind - that is the
  /// server's name for it, not a claim about the contents.
  ///
  /// [onProgress] receives bytes sent and the total. A 500MB video takes
  /// minutes on mobile data, and an upload with no visible movement is
  /// indistinguishable from a hung one.
  Future<Post> createPost({
    required String title,
    required String description,
    String? mediaPath,
    Uint8List? mediaBytes,
    String? mediaName,
    String lang = 'en',
    void Function(int sent, int total)? onProgress,
  }) async {
    if (_demo) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      throw ApiException(
        'Demo mode: the upload endpoint does not exist yet. '
        'Ship the API, then set API_BASE_URL.',
      );
    }

    // lang so the server's own 413/415 wording comes back in the user's
    // language - those messages are shown verbatim.
    final req = http.MultipartRequest('POST', _uri('/posts', {'lang': lang}))
      ..fields['title'] = title
      ..fields['description'] = description;

    // The content type must be set explicitly. package:http defaults every
    // multipart file to application/octet-stream, which the server's filter
    // rejects outright - that bug made every upload fail regardless of file.
    MediaType? type;
    int size = 0;

    if (mediaBytes != null) {
      type = _sniffMediaType(mediaBytes);
      size = mediaBytes.length;
      req.files.add(
        http.MultipartFile.fromBytes(
          'image',
          mediaBytes,
          filename: mediaName ?? 'upload.jpg',
          contentType: type,
        ),
      );
    } else if (mediaPath != null && !kIsWeb) {
      final file = File(mediaPath);
      // Sniff the magic bytes rather than trusting the extension: a picker can
      // hand back .jpg for a PNG, and the server re-encodes video overnight so
      // an extension is never the contract.
      final head = await file.openRead(0, 16).expand((c) => c).toList();
      type = _sniffMediaType(Uint8List.fromList(head));
      size = await file.length();
      req.files.add(
        await http.MultipartFile.fromPath('image', file.path, contentType: type),
      );
    }

    if (type != null) {
      final ceiling = type.type == 'image' ? maxImageBytes : maxAudioVideoBytes;
      if (size > ceiling) {
        throw ApiException(
          'That file is ${_mb(size)} - the limit for ${type.type} is ${_mb(ceiling)}.',
          statusCode: 413,
        );
      }
    }

    late http.StreamedResponse streamed;
    try {
      // _client.send, not req.send(): BaseRequest.send() spins up its own
      // one-shot Client, which bypasses the injected client (so uploads could
      // not be tested) and discards the connection pool on every upload.
      streamed = await _client.send(_withProgress(req, onProgress));
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Upload failed. Check your connection and try again.');
    }

    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      // 413 names the size and the ceiling, 415 names the type, 429 the wait -
      // all already localised, so they are shown exactly as sent.
      String msg = 'Upload rejected (${streamed.statusCode}).';
      Duration? retryAfter;
      try {
        final j = jsonDecode(body) as Map<String, dynamic>;
        if (j['error'] is String) msg = j['error'] as String;
        final secs = (j['retry_after_seconds'] as num?)?.toInt();
        if (secs != null && secs > 0) retryAfter = Duration(seconds: secs);
      } catch (_) {}
      retryAfter ??= () {
        final h = int.tryParse(streamed.headers['retry-after'] ?? '');
        return h != null && h > 0 ? Duration(seconds: h) : null;
      }();
      throw ApiException(msg, statusCode: streamed.statusCode, retryAfter: retryAfter);
    }
    return Post.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  static String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(0)}MB';

  /// Re-streams a finalized multipart body, counting bytes on the way past and
  /// aborting only if the transfer *stalls*.
  ///
  /// A total-duration timeout is the wrong tool here: 500MB up a phone
  /// connection legitimately takes many minutes, and killing a healthy slow
  /// upload is worse than the hang it guards against. Silence is the real
  /// failure signal, so the clock resets on every chunk.
  http.BaseRequest _withProgress(
    http.MultipartRequest req,
    void Function(int sent, int total)? onProgress,
  ) {
    if (onProgress == null) return req;

    // finalize() FIRST, and only then copy the headers. MultipartRequest does
    // not know its own boundary until it is finalized - that is the line where
    // it writes `content-type: multipart/form-data; boundary=...` into its
    // headers. Copying them before that produced a request with no content
    // type at all: every byte of the file arrived, the server could not parse a
    // single field out of it, and answered "Add a title and either an image/GIF
    // or a story." That is what broke every upload from 1.16.0, when this
    // wrapper was added - not just video, and not just large files.
    final body = req.finalize();
    final total = req.contentLength;
    final out = http.StreamedRequest(req.method, req.url)
      ..headers.addAll(req.headers)
      ..contentLength = total;

    var sent = 0;
    Timer? stall;
    void resetStall() {
      stall?.cancel();
      stall = Timer(_uploadStall, () {
        out.sink.addError(ApiException('Upload stalled. Check your connection.'));
        out.sink.close();
      });
    }

    resetStall();
    body.listen(
      (chunk) {
        sent += chunk.length;
        onProgress(sent, total);
        resetStall();
        out.sink.add(chunk);
      },
      onError: (Object e) {
        stall?.cancel();
        out.sink.addError(e);
        out.sink.close();
      },
      onDone: () {
        stall?.cancel();
        out.sink.close();
      },
      cancelOnError: true,
    );
    return out;
  }

  /// No progress for this long means the connection is gone, not slow.
  static const _uploadStall = Duration(seconds: 60);

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
    if (res.statusCode == 429) {
      throw ApiException.rateLimited(res, 'Too many attempts. Try again shortly.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      // 503 is the designed state until Stripe keys are configured, not a
      // failure the user caused - the UI hides tipping rather than blaming them.
      String msg = res.statusCode == 503
          ? 'Tipping is not switched on yet.'
          : 'Checkout failed (${res.statusCode}).';
      try {
        final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        if (j['error'] is String) msg = j['error'] as String;
      } catch (_) {}
      throw ApiException(msg, statusCode: res.statusCode);
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final url = j['url'] as String?;
    if (url == null || url.isEmpty) throw ApiException('Server did not return a checkout URL.');
    return url;
  }

  /// Hands a store receipt to the server so the donation can be recorded and,
  /// critically, verified against Apple/Google rather than trusted from the client.
  ///
  /// Throws on failure, and the distinction between the failures matters more
  /// here than anywhere else in this file, because the caller decides whether
  /// to finish the store transaction based on it:
  ///
  /// - `400` - the store looked at the receipt and rejected it. **Final**: the
  ///   same token gets the same answer for ever, so retrying is pointless.
  ///   What to do with the transaction then differs by rail - see
  ///   `DonationGateway._abandonRejected`.
  /// - `503` - this provider is not configured on the server yet. No verdict
  ///   was reached; the money may well be real.
  /// - anything else (429, other 5xx, offline) - also no verdict. The store was
  ///   unreachable, rate-limited us, or our credentials lapsed. Do not finish,
  ///   so the plugin replays it on the next launch and we get another go.
  ///
  /// The distinction that matters is 400 against everything else, not success
  /// against failure. Treating a rejection as transient retries a dead receipt
  /// for ever; treating an outage as a rejection refunds a real tip.
  ///
  /// The server ignores duplicate tokens, so replaying is safe and cannot
  /// double-count.
  Future<void> verifyStorePurchase({
    required String platform,
    required String productId,
    required String token,
  }) async {
    if (_demo) return;

    late http.Response res;
    try {
      res = await _client
          .post(
            _uri('/donations/$platform/verify'),
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({'product_id': productId, 'token': token}),
          )
          .timeout(_timeout);
    } catch (_) {
      throw ApiException('Could not reach the server to confirm your tip.');
    }

    if (res.statusCode == 429) {
      throw ApiException.rateLimited(res, 'Too many attempts. Try again shortly.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String msg = res.statusCode == 503
          ? 'Tipping is not switched on yet on this platform.'
          : 'Could not confirm your tip (${res.statusCode}).';
      try {
        final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        if (j['error'] is String) msg = j['error'] as String;
      } catch (_) {}
      throw ApiException(msg, statusCode: res.statusCode);
    }
  }

  /// Identifies a file from its magic bytes.
  ///
  /// Never from the extension: a picker hands back .jpg for PNGs, and the
  /// server re-encodes large video overnight, so the extension can change
  /// while the post's kind does not.
  static MediaType _sniffMediaType(Uint8List b) {
    bool at(int offset, List<int> sig) {
      if (b.length < offset + sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (b[offset + i] != sig[i]) return false;
      }
      return true;
    }

    bool starts(List<int> sig) => at(0, sig);

    // --- images
    if (starts([0x89, 0x50, 0x4E, 0x47])) return MediaType('image', 'png');
    if (starts([0x47, 0x49, 0x46, 0x38])) return MediaType('image', 'gif');
    if (starts([0xFF, 0xD8, 0xFF])) return MediaType('image', 'jpeg');

    // --- RIFF containers: WEBP and WAV share the first four bytes, so the
    // form type at offset 8 is what actually distinguishes them.
    if (starts([0x52, 0x49, 0x46, 0x46])) {
      if (at(8, [0x57, 0x45, 0x42, 0x50])) return MediaType('image', 'webp');
      if (at(8, [0x57, 0x41, 0x56, 0x45])) return MediaType('audio', 'wav');
    }

    // --- ISO base media: mp4, mov and m4a all carry "ftyp" at offset 4 and
    // differ only by the brand that follows, so the brand decides whether this
    // is a video or an audio post.
    if (at(4, [0x66, 0x74, 0x79, 0x70])) {
      if (at(8, [0x4D, 0x34, 0x41])) return MediaType('audio', 'mp4'); // M4A
      if (at(8, [0x71, 0x74, 0x20, 0x20])) return MediaType('video', 'quicktime'); // qt
      return MediaType('video', 'mp4');
    }

    // --- Matroska / WebM. The same container carries audio-only files, but
    // video/webm is the safe read: the server accepts both and a player can
    // handle a video stream that happens to have no picture.
    if (starts([0x1A, 0x45, 0xDF, 0xA3])) return MediaType('video', 'webm');

    // --- other audio
    if (starts([0x4F, 0x67, 0x67, 0x53])) return MediaType('audio', 'ogg');
    if (starts([0x49, 0x44, 0x33])) return MediaType('audio', 'mpeg'); // ID3-tagged mp3
    if (b.length >= 2 && b[0] == 0xFF && (b[1] & 0xE0) == 0xE0) {
      return MediaType('audio', 'mpeg'); // bare mp3 frame sync
    }

    // Falls back to JPEG, which is what phone cameras produce and what the
    // overwhelming majority of uploads are. A genuine miss earns a 415 naming
    // the type, which is a clearer failure than guessing wider.
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

  /// Demo threads live for the session only - enough to exercise the composer,
  /// the empty state and the optimistic append without a server.
  static final _demoThreads = <int, List<Comment>>{};

  /// Demo mode's stand-in for the server's per-device vote table, so my_vote
  /// and the counts behave the way production does.
  static final _demoPostVotes = <int, int>{};

  Future<CommentPage> _demoComments(int postId, int page, CommentSort sort) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final all = [...?_demoThreads[postId]];
    if (sort == CommentSort.top) {
      // Same tie-break as the server: oldest first, so paging is stable.
      all.sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        return byScore != 0 ? byScore : a.createdAt.compareTo(b.createdAt);
      });
    }
    return CommentPage(
      items: all,
      page: page,
      total: all.length,
      hasNext: false,
      sort: sort,
    );
  }

  /// Demo mode keeps its own vote ledger so the counts actually move and stay
  /// moved. Returning the comment unchanged would make every tap flash and then
  /// snap back, since the UI replaces its optimistic guess with this response.
  static final _demoCommentVotes = <int, int>{};

  static Comment _demoVoteComment(int id, int value) {
    for (final thread in _demoThreads.values) {
      for (var i = 0; i < thread.length; i++) {
        if (thread[i].id != id) continue;
        final previous = _demoCommentVotes[id] ?? 0;
        final next = applyVoteDelta(thread[i].upvotes, thread[i].downvotes, previous, value);
        _demoCommentVotes[id] = value;
        thread[i] = thread[i].copyWith(upvotes: next.up, downvotes: next.down, myVote: value);
        return thread[i];
      }
    }
    throw ApiException('That comment no longer exists.', statusCode: 404);
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
