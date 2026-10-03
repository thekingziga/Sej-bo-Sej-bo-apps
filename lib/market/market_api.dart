part of '../api.dart';

/// The marketplace endpoints, as docs/API_REQUEST_marketplace.md specifies.
///
/// A part of `api.dart` rather than a library of its own so it shares [Api]'s
/// transport - the client, timeouts, the device id, upload progress and magic
/// byte sniffing - without that file growing by another five hundred lines.
///
/// Every authenticated call takes the token explicitly. [Api] holds no login
/// state: that belongs to `MarketSession`, which is the one place that knows
/// when a token has died.
extension MarketApi on Api {
  static const _unreachable = 'Could not reach sejbosejbo.fyi. Check your connection.';

  /// Sends one marketplace request and returns its JSON, or null for a 204.
  ///
  /// The server's own `{error, code}` is surfaced as-is: the message is
  /// localised (hence `lang` on every call) and shown verbatim, the code is
  /// what callers branch on.
  ///
  /// A response that is not JSON means this server does not have the endpoint
  /// at all: unknown `/api/v1` routes answer with a redirect to the website's
  /// HTML 404 page, which a GET follows to a 404 and a POST stops at as a 302.
  /// Both become `code: "unavailable"`, so the app can say "not here yet"
  /// instead of failing to parse a web page.
  Future<Map<String, dynamic>?> _market(
    String method,
    String path, {
    String? token,
    String lang = 'en',
    Map<String, String>? query,
    Object? json,
  }) async {
    final req = http.Request(method, _uri(path, {...?query, 'lang': lang}))
      ..headers.addAll(_headers)
      ..followRedirects = false;
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (json != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(json);
    }

    late http.Response res;
    try {
      res = await http.Response.fromStream(await _client.send(req).timeout(Api._timeout));
    } catch (_) {
      throw ApiException(_unreachable);
    }
    return _decodeMarket(res);
  }

  Map<String, dynamic>? _decodeMarket(http.Response res) {
    final type = res.headers['content-type'] ?? '';
    final isJson = type.contains('json');

    if (res.statusCode == 204) return null;
    if (res.statusCode >= 300 && res.statusCode < 400 || (!isJson && res.statusCode >= 400)) {
      throw ApiException(
        'The marketplace is not available in the app yet.',
        statusCode: res.statusCode,
        code: 'unavailable',
      );
    }

    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map) body = decoded.cast<String, dynamic>();
    } catch (_) {}

    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (body == null) {
        throw ApiException('The marketplace is not available in the app yet.', code: 'unavailable');
      }
      return body;
    }

    final message = body?['error'] is String ? body!['error'] as String : 'Server said no (${res.statusCode}).';
    final code = body?['code'] as String?;
    if (res.statusCode == 429) {
      throw ApiException(
        message,
        statusCode: 429,
        code: code,
        retryAfter: ApiException._retryAfterOf(res),
      );
    }
    throw ApiException(message, statusCode: res.statusCode, code: code ?? (res.statusCode == 401 ? 'unauthorized' : null));
  }

  _MarketDemo get _md => _marketDemos[this] ??= _MarketDemo();

  // ---------------------------------------------------------------- browse

  Future<ListingPage> listings({
    int page = 1,
    int perPage = 24,
    String q = '',
    ListingSort sort = ListingSort.newest,
    String? token,
    String lang = 'en',
  }) async {
    final per = perPage.clamp(1, ListingPage.maxPerPage);
    if (_demo) return _md.page(page, per, q, sort, token);
    final j = await _market('GET', '/listings', token: token, lang: lang, query: {
      'page': '$page',
      'per_page': '$per',
      if (q.trim().isNotEmpty) 'q': q.trim(),
      'sort': sort.wire,
    });
    return ListingPage.fromJson(j!);
  }

  Future<Listing> listing(int id, {String? token, String lang = 'en'}) async {
    if (_demo) return _md.listing(id, token);
    return Listing.fromJson((await _market('GET', '/listings/$id', token: token, lang: lang))!);
  }

  Future<void> reportListing(int id, MarketReportReason reason, {String? details, String lang = 'en'}) async {
    if (_demo) return;
    await _market('POST', '/listings/$id/report', lang: lang, json: {
      'reason': reason.name,
      if ((details ?? '').trim().isNotEmpty) 'details': details!.trim(),
    });
  }

  // ----------------------------------------------------------------- login

  /// Asks for a code by email. Answers the same way whether or not the
  /// address has an account; so does this.
  Future<void> requestLoginCode(String email, {String lang = 'en'}) async {
    if (_demo) return;
    await _market('POST', '/auth/code', lang: lang, json: {'email': email.trim(), 'lang': lang});
  }

  Future<({String token, Me me})> verifyLoginCode(String email, String code, {String lang = 'en'}) async {
    if (_demo) return _md.verify(email, code);
    final j = (await _market('POST', '/auth/verify', lang: lang, json: {
      'email': email.trim(),
      'code': code.trim(),
    }))!;
    return (token: j['token'] as String, me: Me.fromJson((j['user'] as Map).cast<String, dynamic>()));
  }

  Future<void> logout(String token) async {
    if (_demo) return _md.logout();
    await _market('POST', '/auth/logout', token: token);
  }

  Future<Me> me(String token, {String lang = 'en'}) async {
    if (_demo) return _md.requireMe(token);
    return Me.fromJson((await _market('GET', '/me', token: token, lang: lang))!);
  }

  Future<Me> updateMe(String token, {String? name, bool? notify, String lang = 'en'}) async {
    if (_demo) return _md.updateMe(token, name: name, notify: notify);
    return Me.fromJson((await _market('PATCH', '/me', token: token, lang: lang, json: {
      if (name != null) 'name': name.trim(),
      'notify': ?notify,
    }))!);
  }

  Future<void> deleteAccount(String token, {String lang = 'en'}) async {
    if (_demo) return _md.deleteAccount(token);
    await _market('DELETE', '/me', token: token, lang: lang);
  }

  // --------------------------------------------------------------- selling

  /// Publishes a listing. The photo is required and must be an image - the
  /// website's own form takes nothing else - so anything else is refused here
  /// before a byte is sent.
  Future<Listing> createListing({
    required String token,
    required String title,
    required String description,
    required int? priceCents,
    String? photoPath,
    Uint8List? photoBytes,
    String? photoName,
    String lang = 'en',
    void Function(int sent, int total)? onProgress,
  }) async {
    if (_demo) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      return _md.create(token, title, description, priceCents);
    }

    final req = http.MultipartRequest('POST', _uri('/listings', {'lang': lang}))
      ..headers.addAll(_headers)
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['title'] = title.trim()
      ..fields['description'] = description.trim()
      ..fields['price'] = Money.toWire(priceCents);

    MediaType type;
    int size;
    if (photoBytes != null) {
      type = Api._sniffMediaType(photoBytes);
      size = photoBytes.length;
      req.files.add(http.MultipartFile.fromBytes('photo', photoBytes,
          filename: photoName ?? 'photo.jpg', contentType: type));
    } else if (photoPath != null && !kIsWeb) {
      final file = File(photoPath);
      final head = await file.openRead(0, 16).expand((c) => c).toList();
      type = Api._sniffMediaType(Uint8List.fromList(head));
      size = await file.length();
      req.files.add(await http.MultipartFile.fromPath('photo', file.path, contentType: type));
    } else {
      throw ApiException('Add a photo.', statusCode: 400, code: 'missing');
    }

    if (type.type != 'image') {
      throw ApiException('Listings take a photo, not ${type.type}.', statusCode: 415);
    }
    if (size > Api.maxImageBytes) {
      throw ApiException(
        'That photo is ${Api._mb(size)} - the limit is ${Api._mb(Api.maxImageBytes)}.',
        statusCode: 413,
      );
    }

    late http.StreamedResponse streamed;
    try {
      streamed = await _client.send(_withProgress(req, onProgress));
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Upload failed. Check your connection and try again.');
    }
    final res = await http.Response.fromStream(streamed);
    return Listing.fromJson(_decodeMarket(res)!);
  }

  Future<Listing> markSold(int id, {required String token, String lang = 'en'}) async {
    if (_demo) return _md.markSold(id);
    return Listing.fromJson((await _market('POST', '/listings/$id/sold', token: token, lang: lang))!);
  }

  Future<void> deleteListing(int id, {required String token, String lang = 'en'}) async {
    if (_demo) return _md.remove(id);
    await _market('DELETE', '/listings/$id', token: token, lang: lang);
  }

  Future<List<Listing>> myListings({required String token, String lang = 'en'}) async {
    if (_demo) return _md.mine(token);
    final j = (await _market('GET', '/me/listings', token: token, lang: lang))!;
    return [for (final e in j['items'] as List) Listing.fromJson((e as Map).cast<String, dynamic>())];
  }

  // ---------------------------------------------------------- conversations

  Future<List<Conversation>> conversations({required String token, String lang = 'en'}) async {
    if (_demo) return _md.inbox();
    final j = (await _market('GET', '/conversations', token: token, lang: lang))!;
    return [for (final e in j['items'] as List) Conversation.fromJson((e as Map).cast<String, dynamic>())];
  }

  /// First contact with a seller: creates the buyer's thread, or appends to it
  /// if there already is one. Text, an offer, or both.
  Future<({int conversationId, MarketMessage message})> messageSeller(
    int listingId, {
    required String token,
    String body = '',
    int? offerCents,
    String lang = 'en',
  }) async {
    if (_demo) return _md.start(listingId, body, offerCents);
    final j = (await _market('POST', '/listings/$listingId/messages', token: token, lang: lang, json: {
      if (body.trim().isNotEmpty) 'body': body.trim(),
      if (offerCents != null) 'offer': Money.toWire(offerCents),
    }))!;
    return (
      conversationId: (j['conversation_id'] as num).toInt(),
      message: MarketMessage.fromJson((j['message'] as Map).cast<String, dynamic>()),
    );
  }

  /// A thread, oldest message first. With [after], only messages newer than
  /// that id - what the open thread polls with, so an idle poll is cheap.
  Future<({Conversation conversation, List<MarketMessage> messages})> thread(
    int id, {
    required String token,
    int? after,
    String lang = 'en',
  }) async {
    if (_demo) return _md.thread(id, after);
    final j = (await _market('GET', '/conversations/$id', token: token, lang: lang, query: {
      if (after != null) 'after': '$after',
    }))!;
    return (
      conversation: Conversation.fromJson((j['conversation'] as Map).cast<String, dynamic>()),
      messages: [
        for (final e in j['messages'] as List) MarketMessage.fromJson((e as Map).cast<String, dynamic>()),
      ],
    );
  }

  Future<MarketMessage> sendMessage(
    int conversationId, {
    required String token,
    String body = '',
    int? offerCents,
    String lang = 'en',
  }) async {
    if (_demo) return _md.send(conversationId, body, offerCents);
    return MarketMessage.fromJson((await _market('POST', '/conversations/$conversationId/messages',
        token: token,
        lang: lang,
        json: {
          if (body.trim().isNotEmpty) 'body': body.trim(),
          if (offerCents != null) 'offer': Money.toWire(offerCents),
        }))!);
  }

  Future<MarketMessage> answerOffer(
    int conversationId,
    int messageId, {
    required bool accept,
    required String token,
    String lang = 'en',
  }) async {
    if (_demo) return _md.answer(conversationId, messageId, accept);
    return MarketMessage.fromJson((await _market('POST', '/conversations/$conversationId/offers/$messageId',
        token: token, lang: lang, json: {'accept': accept}))!);
  }

  Future<void> reportConversation(
    int conversationId,
    MarketReportReason reason, {
    required String token,
    String? details,
    String lang = 'en',
  }) async {
    if (_demo) return;
    await _market('POST', '/conversations/$conversationId/report', token: token, lang: lang, json: {
      'reason': reason.name,
      if ((details ?? '').trim().isNotEmpty) 'details': details!.trim(),
    });
  }

  Future<void> blockInConversation(int conversationId, {required String token, String lang = 'en'}) async {
    if (_demo) return _md.block(conversationId);
    await _market('POST', '/conversations/$conversationId/block', token: token, lang: lang);
  }

  Future<List<BlockedUser>> blockedUsers({required String token, String lang = 'en'}) async {
    if (_demo) return List.of(_md.blocks);
    final j = (await _market('GET', '/me/blocks', token: token, lang: lang))!;
    return [for (final e in j['items'] as List) BlockedUser.fromJson((e as Map).cast<String, dynamic>())];
  }

  Future<void> unblock(int userId, {required String token, String lang = 'en'}) async {
    if (_demo) return _md.blocks.removeWhere((b) => b.userId == userId);
    await _market('DELETE', '/me/blocks/$userId', token: token, lang: lang);
  }
}

/// Demo state lives beside each [Api] rather than in a global, so one test's
/// sign-in never leaks into the next one's fresh instance.
final _marketDemos = Expando<_MarketDemo>('marketDemo');

/// A small in-memory marketplace, so every screen runs - and can be tested -
/// before the server has the endpoints. It follows the server's rules where
/// the screens depend on them: one live offer per thread, only the other side
/// answers, no messaging your own listing, nothing on a sold listing.
class _MarketDemo {
  static const _token = 'demo-token';

  int _nextListing = 100;
  int _nextConversation = 20;
  int _nextMessage = 1000;

  Me? _me;
  final blocks = <BlockedUser>[];
  final _convs = <int, _DemoThread>{};

  final _listings = <Map<String, dynamic>>[
    _l(1, 'Kolo, ki skoraj dela', 'Zavore so bolj predlog kot pravilo. Zvonec dela odlično.', 2500, 'ana', 1),
    _l(2, 'Kavč s preteklostjo', 'Ne sprašuj. Odvoz na tvoje stroške in tvojo odgovornost.', 0, 'marko', 2),
    _l(3, 'Lava lamp', 'Neuporabljena, ker je malo strašna ponoči.', null, 'petra', 3),
    _l(4, 'Garmin ura', 'Šteje korake, ki jih ne naredim.', 8000, 'jure', 4, sold: true),
    _l(5, 'Škatla kablov', 'Kabli, ki jih nihče več ne prepozna. Vsaj eden je za nekaj.', 500, 'luka', 5),
    _l(6, 'Sobna rastlina', 'Preživela je mene. Preživela bo tudi tebe.', 1250, 'nina', 6),
    _l(7, 'PS4 kontroler', 'Levi analog ima svoje mnenje.', 1500, 'tilen', 7),
    _l(8, 'Knjiga »Kako nehati odlašati«', 'Še nisem prebral. Bom.', null, 'ana', 8),
  ];

  static Map<String, dynamic> _l(int id, String title, String desc, int? price, String seller, int daysAgo,
          {bool sold = false}) =>
      {
        'id': id,
        'title': title,
        'description': desc,
        'price_cents': price,
        'image_url': null,
        'status': sold ? 'sold' : 'active',
        'seller': {'name': seller},
        'created_at': DateTime.now().subtract(Duration(days: daysAgo)).toIso8601String(),
        'expires_at': DateTime.now().add(Duration(days: 30 - daysAgo)).toIso8601String(),
      };

  bool _signedIn(String? token) => token == _token && _me != null;

  Listing _out(Map<String, dynamic> raw, String? token) {
    final mine = _signedIn(token) && raw['seller']['name'] == _me!.name;
    final buyerThread = _convs.values
        .where((c) => c.listingId == raw['id'] && c.role == ConversationRole.buyer)
        .map((c) => c.id)
        .firstOrNull;
    return Listing.fromJson({...raw, 'is_mine': mine, 'my_conversation_id': mine ? null : buyerThread});
  }

  Map<String, dynamic> _find(int id) =>
      _listings.firstWhere((l) => l['id'] == id, orElse: () => throw ApiException('Not found.', statusCode: 404));

  ListingPage page(int page, int per, String q, ListingSort sort, String? token) {
    final needle = q.trim().toLowerCase();
    final all = _listings
        .where((l) => needle.isEmpty || '${l['title']} ${l['description']}'.toLowerCase().contains(needle))
        .toList();
    int price(Map l, {required bool nullsHigh}) =>
        (l['price_cents'] as int?) ?? (nullsHigh ? 1 << 40 : -1);
    switch (sort) {
      case ListingSort.newest:
        all.sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));
      case ListingSort.priceAsc:
        all.sort((a, b) => price(a, nullsHigh: true).compareTo(price(b, nullsHigh: true)));
      case ListingSort.priceDesc:
        // Null prices go last either way, as the spec asks.
        all.sort((a, b) {
          final x = a['price_cents'] as int?, y = b['price_cents'] as int?;
          if (x == null) return y == null ? 0 : 1;
          if (y == null) return -1;
          return y.compareTo(x);
        });
    }
    final start = (page - 1) * per;
    final slice = all.skip(start).take(per).map((l) => _out(l, token)).toList();
    return ListingPage(items: slice, page: page, hasNext: start + per < all.length, sort: sort, q: needle);
  }

  Listing listing(int id, String? token) => _out(_find(id), token);

  // login

  Future<({String token, Me me})> verify(String email, String code) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!RegExp(r'^\d{6}$').hasMatch(code.trim())) {
      throw ApiException('That code is not right. Check the email and try again.', statusCode: 400, code: 'bad_code');
    }
    _me = Me(email: email.trim(), name: null, lang: 'sl', notify: true, unreadCount: 0);
    return (token: _token, me: _me!);
  }

  void logout() {}

  Me requireMe(String token) {
    if (!_signedIn(token)) throw ApiException('Please log in again.', statusCode: 401, code: 'unauthorized');
    return _me!.copyWith(unreadCount: _convs.values.where((c) => c.unread).length);
  }

  Me updateMe(String token, {String? name, bool? notify}) {
    requireMe(token);
    if (name != null) {
      final clean = name.trim();
      if (!Me.nameRule.hasMatch(clean)) {
        throw ApiException('3-24 letters or digits, please.', statusCode: 400, code: 'invalid');
      }
      if (const {'admin', 'sejbo', 'sejbosejbo', 'ana', 'marko'}.contains(clean.toLowerCase())) {
        throw ApiException('That name is taken.', statusCode: 409, code: 'taken');
      }
      final first = !(_me!.hasName);
      _me = _me!.copyWith(name: clean);
      if (first) _seedFor(clean);
    }
    if (notify != null) _me = _me!.copyWith(notify: notify);
    return requireMe(token);
  }

  /// Gives a freshly named demo account something to look at: a listing of
  /// its own with an offer waiting on it, and a thread as a buyer.
  void _seedFor(String name) {
    final mine = _l(_nextListing++, 'Stara tipkovnica', 'Tipke Q, W in E so obrabljene od preveč igranja.', 1000,
        name, 0);
    _listings.insert(0, mine);
    _convs[_nextConversation] = _DemoThread(_nextConversation++, mine['id'] as int, ConversationRole.seller, 'marko')
      ..messages.addAll([
        _msg(false, 'Živjo, bi dal za 7?', null, null, minutesAgo: 40),
        _msg(false, '', 700, OfferStatus.pending, minutesAgo: 39),
      ])
      ..unread = true;
    _convs[_nextConversation] = _DemoThread(_nextConversation++, 1, ConversationRole.buyer, 'ana')
      ..messages.addAll([
        _msg(true, 'Je kolo še na voljo?', null, null, minutesAgo: 300),
        _msg(false, 'Ja! Pridi pogledat, zvonec je odličen.', null, null, minutesAgo: 290),
      ]);
  }

  MarketMessage _msg(bool mine, String body, int? offer, OfferStatus? status, {int minutesAgo = 0}) => MarketMessage(
    id: _nextMessage++,
    mine: mine,
    body: body,
    offerCents: offer,
    offerStatus: status,
    createdAt: DateTime.now().subtract(Duration(minutes: minutesAgo)),
  );

  void deleteAccount(String token) {
    requireMe(token);
    final name = _me!.name;
    _listings.removeWhere((l) => l['seller']['name'] == name);
    _convs.clear();
    blocks.clear();
    _me = null;
  }

  // selling

  Listing create(String token, String title, String description, int? price) {
    final me = requireMe(token);
    if (!me.hasName) throw ApiException('Pick a name first.', statusCode: 403, code: 'name_required');
    final raw = _l(_nextListing++, title.trim(), description.trim(), price, me.name!, 0);
    _listings.insert(0, raw);
    return _out(raw, token);
  }

  Listing markSold(int id) {
    final raw = _find(id)..['status'] = 'sold';
    return _out(raw, _token);
  }

  void remove(int id) => _listings.removeWhere((l) => l['id'] == id);

  List<Listing> mine(String token) {
    final me = requireMe(token);
    return [for (final l in _listings) if (l['seller']['name'] == me.name) _out(l, token)];
  }

  // conversations

  Conversation _summary(_DemoThread t) {
    final l = _find(t.listingId);
    final last = t.messages.last;
    return Conversation.fromJson({
      'id': t.id,
      'role': t.role.name,
      'other': {'name': t.other},
      'listing': {
        'id': l['id'],
        'title': l['title'],
        'price_cents': l['price_cents'],
        'image_url': l['image_url'],
        'status': l['status'],
      },
      'last_message': {'body': last.body, 'offer_cents': last.offerCents, 'mine': last.mine},
      'unread': t.unread,
      'last_message_at': last.createdAt.toIso8601String(),
    });
  }

  List<Conversation> inbox() {
    final blocked = blocks.map((b) => b.name).toSet();
    final out = [for (final t in _convs.values) if (!blocked.contains(t.other)) _summary(t)]
      ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    return out;
  }

  _DemoThread _thread(int id) =>
      _convs[id] ?? (throw ApiException('Not found.', statusCode: 404));

  void _guard(_DemoThread t, {required bool offer}) {
    if (blocks.any((b) => b.name == t.other)) {
      throw ApiException('This conversation is closed.', statusCode: 409, code: 'closed');
    }
    if (offer && _find(t.listingId)['status'] != 'active') {
      throw ApiException('That listing is no longer for sale.', statusCode: 409, code: 'closed');
    }
  }

  void _validate(String body, int? offer) {
    if (body.trim().isEmpty && offer == null) {
      throw ApiException('Write something or make an offer.', statusCode: 400, code: 'empty');
    }
  }

  ({int conversationId, MarketMessage message}) start(int listingId, String body, int? offer) {
    final l = _find(listingId);
    if (l['status'] != 'active') throw ApiException('That listing is no longer for sale.', statusCode: 409, code: 'closed');
    if (l['seller']['name'] == _me?.name) throw ApiException('That one is yours.', statusCode: 403, code: 'own');
    _validate(body, offer);
    final existing = _convs.values.where((c) => c.listingId == listingId && c.role == ConversationRole.buyer).firstOrNull;
    final t = existing ?? (_convs[_nextConversation] = _DemoThread(_nextConversation++, listingId, ConversationRole.buyer, l['seller']['name'] as String));
    return (conversationId: t.id, message: send(t.id, body, offer));
  }

  ({Conversation conversation, List<MarketMessage> messages}) thread(int id, int? after) {
    final t = _thread(id)..unread = false;
    return (
      conversation: _summary(t),
      messages: [for (final m in t.messages) if (after == null || m.id > after) m],
    );
  }

  MarketMessage send(int id, String body, int? offer) {
    final t = _thread(id);
    _validate(body, offer);
    _guard(t, offer: offer != null);
    if (offer != null) {
      for (var i = 0; i < t.messages.length; i++) {
        if (t.messages[i].offerStatus == OfferStatus.pending) {
          t.messages[i] = _with(t.messages[i], OfferStatus.superseded);
        }
      }
    }
    final m = _msg(true, body.trim(), offer, offer == null ? null : OfferStatus.pending);
    t.messages.add(m);
    // The other side answers a moment later, so the open thread's polling has
    // something to find - which is how that path gets exercised in demo mode.
    Timer(const Duration(seconds: 3), () {
      if (_convs.containsKey(id)) t.messages.add(_msg(false, 'Ok, se slišiva 👍', null, null));
    });
    return m;
  }

  static MarketMessage _with(MarketMessage m, OfferStatus s) => MarketMessage(
    id: m.id,
    mine: m.mine,
    body: m.body,
    offerCents: m.offerCents,
    offerStatus: s,
    createdAt: m.createdAt,
  );

  MarketMessage answer(int id, int messageId, bool accept) {
    final t = _thread(id);
    final i = t.messages.indexWhere((m) => m.id == messageId);
    final m = i < 0 ? null : t.messages[i];
    if (m == null || m.mine || m.offerStatus != OfferStatus.pending) {
      throw ApiException('That offer was already answered.', statusCode: 409, code: 'stale');
    }
    _guard(t, offer: true);
    return t.messages[i] = _with(m, accept ? OfferStatus.accepted : OfferStatus.declined);
  }

  void block(int id) {
    final t = _thread(id);
    if (!blocks.any((b) => b.name == t.other)) {
      blocks.add(BlockedUser(userId: 500 + blocks.length, name: t.other, blockedAt: DateTime.now()));
    }
  }
}

class _DemoThread {
  _DemoThread(this.id, this.listingId, this.role, this.other);

  final int id;
  final int listingId;
  final ConversationRole role;
  final String other;
  final messages = <MarketMessage>[];
  bool unread = false;
}
