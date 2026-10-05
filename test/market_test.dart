import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sejbosejbo/api.dart';
import 'package:sejbosejbo/l10n.dart';
import 'package:sejbosejbo/market/models.dart';
import 'package:sejbosejbo/market/screens/chat.dart';
import 'package:sejbosejbo/market/screens/market.dart';
import 'package:sejbosejbo/market/session.dart';
import 'package:sejbosejbo/market/widgets.dart';
import 'package:sejbosejbo/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sejbosejbo/theme.dart';

/// A server that answers one canned response per path and records what it got.
class _Server {
  _Server(this.routes);

  /// Path (without /api/v1) -> (status, body, headers).
  final Map<String, (int, Object?, Map<String, String>)> routes;
  final requests = <http.BaseRequest>[];
  final bodies = <String>[];

  Api api({Prefs? prefs}) => Api(
    baseUrl: 'https://example.test',
    useDemoData: false,
    prefs: prefs,
    client: MockClient.streaming((req, bytes) async {
      requests.add(req);
      bodies.add(utf8.decode(await bytes.toBytes(), allowMalformed: true));
      final path = req.url.path.replaceFirst('/api/v1', '');
      final (status, body, headers) =
          routes[path] ?? (404, '<html>not found</html>', {'content-type': 'text/html'});
      final text = body is String ? body : jsonEncode(body);
      return http.StreamedResponse(
        Stream.value(utf8.encode(text)),
        status,
        headers: {'content-type': 'application/json', ...headers},
      );
    }),
  );
}

Map<String, dynamic> _listingJson({int id = 1, int? price = 2500, String status = 'active'}) => {
  'id': id,
  'title': 'Kolo',
  'description': 'Rides.',
  'price_cents': price,
  'image_url': null,
  'status': status,
  'seller': {'name': 'ana'},
  'created_at': '2026-10-01T10:00:00.000Z',
  'expires_at': '2026-10-31T10:00:00.000Z',
};

const _me = {'email': 'z@example.com', 'name': 'ziga', 'lang': 'sl', 'notify': true, 'unread_count': 2};

void main() {
  group('money matches the website exactly', () {
    test('formats like Intl sl-SI and en-IE', () {
      expect(Money.format(2500, 'sl'), '25,00 €');
      expect(Money.format(2500, 'en'), '€25.00');
      expect(Money.format(125099, 'sl'), '1.250,99 €');
      expect(Money.format(125099, 'en'), '€1,250.99');
      expect(Money.format(5, 'en'), '€0.05');
    });

    test('null is "make an offer" and 0 is "free" - never collapsed', () {
      expect(marketPrice(Strings.en, null), 'make an offer');
      expect(marketPrice(Strings.sl, null), 'po dogovoru');
      expect(marketPrice(Strings.en, 0), 'free');
      expect(marketPrice(Strings.sl, 0), 'zastonj');
    });

    test('parses what people type, the way the server does', () {
      expect(Money.parse('12').cents, 1200);
      expect(Money.parse('12,5').cents, 1250); // Slovenians write a comma
      expect(Money.parse('12.50').cents, 1250);
      expect(Money.parse(' 12 € ').cents, 1200);
      expect(Money.parse('').ok, isTrue);
      expect(Money.parse('').cents, isNull);
      for (final bad in ['12.555', 'abc', '12,', '-5', '10000000']) {
        expect(Money.parse(bad).ok, isFalse, reason: bad);
      }
    });

    test('goes on the wire with a dot, blank for offers', () {
      expect(Money.toWire(1250), '12.50');
      expect(Money.toWire(5), '0.05');
      expect(Money.toWire(0), '0.00');
      expect(Money.toWire(null), '');
    });

    test('display names follow the website NAME_RE', () {
      for (final ok in ['ziga', 'žiga.v', 'Ana_B', 'abc']) {
        expect(Me.nameRule.hasMatch(ok), isTrue, reason: ok);
      }
      for (final bad in ['ab', '-ziga', 'ziga-', 'a' * 25, 'with space']) {
        expect(Me.nameRule.hasMatch(bad), isFalse, reason: bad);
      }
    });
  });

  group('offers', () {
    MarketMessage offer({required bool mine, OfferStatus status = OfferStatus.pending}) => MarketMessage(
      id: 1,
      mine: mine,
      body: '',
      offerCents: 2000,
      offerStatus: status,
      createdAt: DateTime(2026),
    );

    test('only the other side answers, only while pending, only while for sale', () {
      expect(offer(mine: false).canAnswer(listingActive: true), isTrue);
      expect(offer(mine: true).canAnswer(listingActive: true), isFalse);
      expect(offer(mine: false).canAnswer(listingActive: false), isFalse);
      for (final s in [OfferStatus.accepted, OfferStatus.declined, OfferStatus.superseded]) {
        expect(offer(mine: false, status: s).canAnswer(listingActive: true), isFalse, reason: s.name);
      }
    });

    test('a newer offer supersedes the pending one (demo follows the server rule)', () async {
      final api = Api(useDemoData: true);
      final s = MarketSession(api: api, store: MemoryTokenStore());
      await s.verifyCode('z@example.com', '123456');
      await s.setName('sejbotester');
      final inbox = await s.authed((t) => api.conversations(token: t));
      final buying = inbox.firstWhere((c) => c.role == ConversationRole.buyer);
      await s.authed((t) => api.sendMessage(buying.id, token: t, offerCents: 2000));
      await s.authed((t) => api.sendMessage(buying.id, token: t, offerCents: 2200));
      final thread = await s.authed((t) => api.thread(buying.id, token: t));
      final offers = thread.messages.where((m) => m.isOffer).toList();
      expect(offers.map((m) => m.offerStatus), [OfferStatus.superseded, OfferStatus.pending]);
    });
  });

  group('the wire contract', () {
    test('a public browse sends no token, and every call carries lang', () async {
      final server = _Server({
        '/listings': (200, {'items': [_listingJson()], 'page': 1, 'has_next': false, 'sort': 'new', 'q': ''}, {}),
      });
      final page = await server.api().listings(lang: 'sl');
      expect(page.items.single.title, 'Kolo');
      final req = server.requests.single;
      expect(req.headers.containsKey('Authorization'), isFalse);
      expect(req.url.queryParameters['lang'], 'sl');
    });

    test('authenticated calls carry the bearer token', () async {
      final server = _Server({'/me': (200, _me, {})});
      final me = await server.api().me('tok_1', lang: 'en');
      expect(me.name, 'ziga');
      expect(me.unreadCount, 2);
      expect(server.requests.single.headers['Authorization'], 'Bearer tok_1');
    });

    test('the server echo decides which sort is shown, not the request', () async {
      // The website shipped with no sort at all; a server that ignores it
      // says "new", and the screen must not label unsorted results as sorted.
      final server = _Server({
        '/listings': (200, {'items': [], 'page': 1, 'has_next': false, 'sort': 'new', 'q': ''}, {}),
      });
      final page = await server.api().listings(sort: ListingSort.priceAsc, q: 'kolo');
      expect(server.requests.single.url.queryParameters['sort'], 'price_asc');
      expect(page.sort, ListingSort.newest);
      expect(page.q, '');
    });

    test('errors keep the server wording and its machine code', () async {
      final server = _Server({
        '/me': (409, {'error': 'To ime je zasedeno.', 'code': 'taken'}, {}),
      });
      await expectLater(
        () => server.api().updateMe('tok', name: 'ana'),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', 'To ime je zasedeno.')
            .having((e) => e.code, 'code', 'taken')
            .having((e) => e.statusCode, 'status', 409)),
      );
    });

    test('a 401 always reads as unauthorized, even with no body code', () async {
      final server = _Server({'/me': (401, {'error': 'nope'}, {})});
      await expectLater(
        () => server.api().me('dead'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'unauthorized')),
      );
    });

    test('an endpoint that does not exist yet reads as "unavailable", not a crash', () async {
      // What sejbosejbo.fyi does today for an unknown /api/v1 path: a GET is
      // redirected to the HTML 404 page, a POST stops at the 302.
      final html404 = _Server({});
      await expectLater(
        () => html404.api().listings(),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'unavailable')),
      );
      final redirect = _Server({
        '/auth/code': (302, 'Found. Redirecting to /404', {'content-type': 'text/plain', 'location': '/404'}),
      });
      await expectLater(
        () => redirect.api().requestLoginCode('z@example.com'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'unavailable')),
      );
    });

    test('a listing photo goes up as "photo", with the boundary, and the price as text', () async {
      final server = _Server({'/listings': (201, _listingJson(id: 9, price: 1250), {})});
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, ...List.filled(64, 0)]);
      final created = await server.api().createListing(
        token: 'tok',
        title: 'Kolo',
        description: '',
        priceCents: 1250,
        photoBytes: jpeg,
        onProgress: (_, _) {},
      );
      expect(created, isA<Published<Listing>>().having((r) => r.value.id, 'id', 9));
      final req = server.requests.single;
      expect(req.headers['Authorization'], 'Bearer tok');
      // The same multipart boundary bug that broke uploads in 1.16.0 would
      // break selling too; this path goes through the same progress wrapper.
      expect(req.headers['content-type'], startsWith('multipart/form-data; boundary='));
      final body = server.bodies.single;
      expect(body, contains('name="photo"'));
      expect(body, contains('name="price"\r\n\r\n12.50'));
    });

    test('202 held is a result, not an error, and X-Device-Id goes along', () async {
      // Website 1.43: a listing can be held for review. Its public page 404s,
      // so the app must not try to open it. 1.44: the device id feeds the
      // safety log and device bans.
      SharedPreferences.setMockInitialValues({});
      final prefs = await Prefs.load();
      final server = _Server({
        '/listings': (202, {'status': 'held', 'id': 12, 'message': 'Oglas čaka na pregled.'}, {}),
      });
      final r = await server.api(prefs: prefs).createListing(
        token: 'tok',
        title: 'Kolo',
        description: '',
        priceCents: 0,
        photoBytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, ...List.filled(64, 0)]),
      );
      expect(r, isA<Held<Listing>>().having((r) => r.message, 'message', 'Oglas čaka na pregled.'));
      expect(server.requests.single.headers['X-Device-Id'], prefs.deviceId);
    });

    test('403 banned on a listing shows the server wording as-is', () async {
      final server = _Server({
        '/listings': (403, {'error': 'Tvoj račun je blokiran.', 'code': 'banned'}, {}),
      });
      final e = await server
          .api()
          .createListing(
            token: 'tok',
            title: 'Kolo',
            description: '',
            priceCents: 0,
            photoBytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, ...List.filled(64, 0)]),
          )
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(e, isA<ApiException>().having((e) => e.code, 'code', 'banned'));
      expect(marketError(Strings.sl, e!), 'Tvoj račun je blokiran.');
    });

    test('my listings read hidden and held', () async {
      final server = _Server({
        '/me/listings': (200, {
          'items': [
            {..._listingJson(id: 1), 'hidden': true, 'held': true},
            {..._listingJson(id: 2), 'hidden': true, 'held': false},
            _listingJson(id: 3),
          ],
        }, {}),
      });
      final mine = await server.api().myListings(token: 'tok');
      expect([for (final l in mine) (l.hidden, l.held)], [(true, true), (true, false), (false, false)]);
    });

    test('a listing photo must be a photo - refused before anything is sent', () async {
      final server = _Server({});
      final mp3 = Uint8List.fromList([0x49, 0x44, 0x33, ...List.filled(64, 0)]);
      await expectLater(
        () => server.api().createListing(token: 't', title: 'x', description: '', priceCents: 0, photoBytes: mp3),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 415)),
      );
      expect(server.requests, isEmpty);
    });
  });

  group('the session', () {
    test('logging in remembers the token', () async {
      final store = MemoryTokenStore();
      final s = MarketSession(api: Api(useDemoData: true), store: store);
      await s.verifyCode('z@example.com', '123456');
      expect(s.signedIn, isTrue);
      expect(s.ready, isFalse, reason: 'no name yet');
      expect(await store.read(), isNotNull);
    });

    test('a token the server rejects ends the session and is forgotten', () async {
      final store = MemoryTokenStore('dead');
      final server = _Server({'/me': (401, {'error': 'x', 'code': 'unauthorized'}, {})});
      final s = MarketSession(api: server.api(), store: store);
      await s.restore();
      expect(s.signedIn, isFalse);
      expect(await store.read(), isNull);
    });

    test('an unreachable server does not log anyone out', () async {
      // Opening the app on a train must not cost people their login.
      final store = MemoryTokenStore('good');
      final api = Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        client: MockClient((_) async => throw Exception('offline')),
      );
      final s = MarketSession(api: api, store: store);
      await s.restore();
      expect(s.signedIn, isTrue);
      expect(await store.read(), 'good');
    });

    test('a 401 anywhere ends the session, and the caller still sees the error', () async {
      final server = _Server({'/conversations': (401, {'error': 'x'}, {})});
      final s = MarketSession(api: server.api(), store: MemoryTokenStore())
        ..debugSignIn('tok', Me.fromJson(_me));
      await expectLater(
        () => s.authed((t) => server.api().conversations(token: t)),
        throwsA(isA<ApiException>()),
      );
      expect(s.signedIn, isFalse);
    });

    test('deleting an account that the server failed to delete keeps you signed in', () async {
      // Otherwise the person believes the account is gone while it still
      // exists, with their listings and messages in it.
      final server = _Server({'/me': (500, {'error': 'database on fire'}, {})});
      final store = MemoryTokenStore('tok');
      final s = MarketSession(api: server.api(), store: store)..debugSignIn('tok', Me.fromJson(_me));
      await expectLater(() => s.deleteAccount(), throwsA(isA<ApiException>()));
      expect(s.signedIn, isTrue);
      expect(await store.read(), 'tok');
    });
  });

  group('screens', () {
    Future<void> pump(WidgetTester tester, Widget child, {Lang lang = Lang.en}) async {
      tester.view.physicalSize = const Size(414, 896);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        L10n(
          strings: Strings.of(lang),
          onChange: (_) {},
          child: MaterialApp(theme: Brutal.theme(), home: child),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('the market shows listings, with sold ones stamped', (tester) async {
      final api = Api(useDemoData: true);
      await pump(tester, MarketScreen(api: api, session: MarketSession(api: api, store: MemoryTokenStore())));
      expect(find.text('Kolo, ki skoraj dela'), findsOneWidget);
      expect(find.text('€25.00'), findsWidgets);
      // Garmin ura is sold in the demo data, and sorted far enough down that
      // it needs a scroll.
      await tester.scrollUntilVisible(find.text('Garmin ura'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('SOLD'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a server without the API shows the website fallback', (tester) async {
      final api = _Server({}).api();
      await pump(tester, MarketScreen(api: api, session: MarketSession(api: api, store: MemoryTokenStore())));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('NOT IN THE APP YET'), findsOneWidget);
      expect(find.text('OPEN ON THE WEBSITE'), findsOneWidget);
      // And no SELL button promising something that cannot work.
      expect(find.text('SELL'), findsNothing);
    });

    testWidgets('an offer card offers ACCEPT only to the side that can answer', (tester) async {
      MarketMessage m({required bool mine}) => MarketMessage(
        id: 1,
        mine: mine,
        body: '',
        offerCents: 700,
        offerStatus: OfferStatus.pending,
        createdAt: DateTime(2026),
      );
      await pump(
        tester,
        Scaffold(
          body: Column(
            children: [
              MessageBubble(message: m(mine: false), listingActive: true, onAnswer: (_) {}),
              MessageBubble(message: m(mine: true), listingActive: true, onAnswer: (_) {}),
            ],
          ),
        ),
      );
      expect(find.text('ACCEPT'), findsOneWidget);
      expect(find.text('€7.00'), findsNWidgets(2));
    });

    testWidgets('a new thread says hello to the seller and sends the first message', (tester) async {
      final api = Api(useDemoData: true);
      final session = MarketSession(api: api, store: MemoryTokenStore());
      // Real time, not the widget test's fake clock: the demo login waits a
      // moment like a real one would, and nothing would ever advance it here.
      final listing = (await tester.runAsync(() async {
        await session.verifyCode('z@example.com', '123456');
        await session.setName('sejbotester');
        return api.listing(1);
      }))!;
      await pump(
        tester,
        ChatScreen(api: api, session: session, newThreadListing: listing),
      );
      expect(find.textContaining('Say hi to ana'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Je še na voljo?');
      await tester.tap(find.text('SEND'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Je še na voljo?'), findsOneWidget);
      // Leave before the demo's scripted reply timer fires.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
    });
  });
}
