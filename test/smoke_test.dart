import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sejbosejbo/api.dart';
import 'package:sejbosejbo/donations.dart';
import 'package:sejbosejbo/l10n.dart';
import 'package:sejbosejbo/main.dart';
import 'package:sejbosejbo/models.dart';
import 'package:sejbosejbo/prefs.dart';
import 'package:sejbosejbo/screens/detail.dart';
import 'package:sejbosejbo/theme.dart';
import 'package:sejbosejbo/store_update.dart';
import 'package:sejbosejbo/update_gate.dart';
import 'package:sejbosejbo/version.dart';
import 'package:sejbosejbo/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A widget test fails on a RenderFlex overflow, so simply pumping every screen
/// at several phone sizes is what guards the layout - that is how the gallery's
/// featured-card overflow was caught.
void main() {
  _uploadContentTypeTests();
  _reportTests();
  _commentTests();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<Prefs> pumpApp(
    WidgetTester tester, {
    Size size = const Size(414, 896),
    Lang lang = Lang.en,
  }) async {
    tester.view.physicalSize = size * tester.view.devicePixelRatio;
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    final prefs = await Prefs.load();
    final api = Api(useDemoData: true, prefs: prefs);
    addTearDown(api.close);
    final donations = DonationGateway(api);
    addTearDown(donations.dispose);

    await tester.pumpWidget(
      L10n(
        strings: Strings.of(lang),
        onChange: (_) {},
        child: MaterialApp(
          theme: Brutal.theme(),
          home: Shell(api: api, donations: donations, prefs: prefs),
        ),
      ),
    );
    // Demo endpoints are deliberately delayed; settle past them.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    return prefs;
  }

  testWidgets('shell renders with all four tabs', (tester) async {
    await pumpApp(tester);
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('GALLERY'), findsOneWidget);
    expect(find.text('UPLOAD'), findsOneWidget);
    expect(find.text('SUPPORT'), findsOneWidget);
  });

  testWidgets('dashboard shows stats and the latest post', (tester) async {
    await pumpApp(tester);
    expect(find.text('LATEST SEJBOSEJBO'), findsOneWidget);
    expect(find.text('VISITORS'), findsOneWidget);
    expect(find.text('Microwaved a salad'), findsWidgets);
  });

  testWidgets('every screen lays out without overflow on a small phone', (tester) async {
    // 360x640 is roughly the smallest Android still in circulation.
    await pumpApp(tester, size: const Size(360, 640));

    for (final label in ['GALLERY', 'UPLOAD', 'SUPPORT', 'HOME']) {
      await tester.tap(find.text(label));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull, reason: '$label tab overflowed or threw');
    }
  });

  testWidgets('post detail opens and shows the certification stamp', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Microwaved a salad').first);

    // Not pumpAndSettle: the IndexedStack keeps every tab alive, so the gallery
    // tab's loading spinner animates forever and settling never completes.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    expect(find.byType(PostDetailScreen), findsOneWidget);
    expect(find.text('SHARE'), findsOneWidget);

    // The stamp is the last thing in a lazily built ListView, so it is not in
    // the tree until scrolled to.
    await tester.dragUntilVisible(
      find.textContaining('OFFICIALLY'),
      find.byType(ListView).last,
      const Offset(0, -250),
    );
    expect(find.textContaining('OFFICIALLY'), findsOneWidget);

    // Scrolling that far builds the comments section, which kicks off a demo
    // fetch; drain it or the binding fails on a pending timer.
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('detail shows the comment thread, and posting appends to it', (tester) async {
    // 360x640 doubles as the layout guard: a widget test fails on overflow, and
    // the composer plus counter row is the widest thing on the screen.
    await pumpApp(tester, size: const Size(360, 640));

    // On a 640pt screen the hero title sits under the bottom nav, so it has to
    // be scrolled into reach before it can be tapped.
    await tester.dragUntilVisible(
      find.text('Microwaved a salad').first,
      find.byType(ListView).first,
      const Offset(0, -120),
    );
    await tester.pump();
    await tester.tap(find.text('Microwaved a salad').first);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    final list = find.byType(ListView).last;
    await tester.dragUntilVisible(find.text('COMMENTS'), list, const Offset(0, -250));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('No comments yet. Be the first.'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'comments section overflowed');

    await tester.enterText(find.byType(TextField).last, 'sej bo sej bo');
    await tester.pump();
    await tester.tap(find.text('POST'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('sej bo sej bo'), findsOneWidget, reason: 'new comment is appended locally');
    expect(find.text('No comments yet. Be the first.'), findsNothing);

    // The comment carries its own vote bar - same widget, same semantics as a
    // post's - so the tile now holds a second SEJ BO.
    expect(find.text('SEJ BO'), findsWidgets);
    await tester.tap(find.text('SEJ BO').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull, reason: 'voting on a comment overflowed or threw');
  });

  testWidgets('an unknown post kind renders a card instead of a broken image', (tester) async {
    // Guards the day audio/video ship: an old install must degrade, not break.
    await tester.pumpWidget(
      L10n(
        strings: Strings.en,
        onChange: (_) {},
        child: MaterialApp(
          theme: Brutal.theme(),
          home: Scaffold(
            body: SizedBox(
              height: 260,
              width: 180,
              child: PostCard(
                post: Post.fromJson({
                  'id': 1,
                  'title': 'A loud one',
                  'kind': 'video',
                  'image_url': 'https://sejbosejbo.fyi/uploads/a.mp4',
                  'created_at': '2026-08-14T19:34:03.000Z',
                }),
                index: 0,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('VIDEO'), findsOneWidget);
    expect(find.byType(Image), findsNothing, reason: 'never hand an .mp4 to Image.network');
  });

  testWidgets('the gate lets the app through when the server says nothing', (tester) async {
    AppVersion.cachedForTest = const AppVersion(version: '1.8.0', build: '10');
    addTearDown(() => AppVersion.cachedForTest = null);

    final api = Api(
      baseUrl: 'https://example.test',
      useDemoData: false,
      client: MockClient((_) async => http.Response('', 404)),
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      L10n(
        strings: Strings.en,
        onChange: (_) {},
        child: MaterialApp(
          theme: Brutal.theme(),
          home: UpdateGate(
            api: api,
            store: const NoStoreUpdates(),
            child: const Scaffold(body: Text('THE APP')),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('THE APP'), findsOneWidget, reason: 'no endpoint must not lock anyone out');
    expect(find.text('UPDATE REQUIRED'), findsNothing);
  });

  testWidgets('the gate walls the app off when the build is too old', (tester) async {
    AppVersion.cachedForTest = const AppVersion(version: '1.4.0', build: '5');
    addTearDown(() => AppVersion.cachedForTest = null);

    final api = Api(
      baseUrl: 'https://example.test',
      useDemoData: false,
      client: MockClient(
        (_) async => http.Response('{"min_version":"1.8.0","message":"Voting moved."}', 200),
      ),
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      L10n(
        strings: Strings.en,
        onChange: (_) {},
        child: MaterialApp(
          theme: Brutal.theme(),
          home: UpdateGate(
            api: api,
            store: const NoStoreUpdates(),
            child: const Scaffold(body: Text('THE APP')),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('UPDATE REQUIRED'), findsOneWidget);
    expect(find.text('UPDATE NOW'), findsOneWidget);
    expect(find.text('Voting moved.'), findsOneWidget, reason: "server's reason is shown");
    expect(find.text('THE APP'), findsNothing, reason: 'the app must be unreachable');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Play having an update ready runs the flow without being asked',
      (tester) async {
    AppVersion.cachedForTest = const AppVersion(version: '1.10.0', build: '12');
    addTearDown(() => AppVersion.cachedForTest = null);

    final store = _FakeStore(ready: true);
    final api = Api(
      baseUrl: 'https://example.test',
      useDemoData: false,
      // Server has no opinion: Play alone is enough to force the update.
      client: MockClient((_) async => http.Response('', 404)),
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      L10n(
        strings: Strings.en,
        onChange: (_) {},
        child: MaterialApp(
          theme: Brutal.theme(),
          home: UpdateGate(
            api: api,
            store: store,
            child: const Scaffold(body: Text('THE APP')),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(store.immediateStarted, 1,
        reason: "Play's own flow should open without the user tapping first");
    // accepts: true, so the update went through and the app is usable again.
    // (On a real device Play restarts the app at this point.)
    expect(find.text('THE APP'), findsOneWidget);
  });

  testWidgets('declining the Play update keeps the wall up, with a retry', (tester) async {
    AppVersion.cachedForTest = const AppVersion(version: '1.10.0', build: '12');
    addTearDown(() => AppVersion.cachedForTest = null);

    // accepts: false = the user backs out of Play's dialog.
    final store = _FakeStore(ready: true, accepts: false);
    final api = Api(
      baseUrl: 'https://example.test',
      useDemoData: false,
      client: MockClient((_) async => http.Response('', 404)),
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      L10n(
        strings: Strings.en,
        onChange: (_) {},
        child: MaterialApp(
          theme: Brutal.theme(),
          home: UpdateGate(
            api: api,
            store: store,
            child: const Scaffold(body: Text('THE APP')),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('THE APP'), findsNothing, reason: 'backing out must not get you in');

    await tester.tap(find.text('UPDATE NOW'));
    await tester.pump();
    expect(store.immediateStarted, 2, reason: 'the button re-runs the flow');
  });

  testWidgets('no store update and no server opinion means nothing changes', (tester) async {
    AppVersion.cachedForTest = const AppVersion(version: '1.10.0', build: '12');
    addTearDown(() => AppVersion.cachedForTest = null);

    final store = _FakeStore(ready: false);
    final api = Api(
      baseUrl: 'https://example.test',
      useDemoData: false,
      client: MockClient((_) async => http.Response('', 404)),
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      L10n(
        strings: Strings.en,
        onChange: (_) {},
        child: MaterialApp(
          theme: Brutal.theme(),
          home: UpdateGate(
            api: api,
            store: store,
            child: const Scaffold(body: Text('THE APP')),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('THE APP'), findsOneWidget);
    expect(store.immediateStarted, 0);
  });

  testWidgets('hall of fame is ordered by score, highest first', (tester) async {
    await pumpApp(tester);

    // The dashboard ListView builds lazily, so the section does not exist in
    // the tree until it is scrolled near.
    await tester.dragUntilVisible(
      find.text('HALL OF FAME'),
      find.byType(ListView).first,
      const Offset(0, -220),
    );
    await tester.pump();

    expect(find.text('HALL OF FAME'), findsOneWidget);
    // Demo data's runaway winner is the fridge router at +502.
    expect(find.text('Put the router in the fridge'), findsWidgets);
  });

  testWidgets('voting on the hero moves the count and sticks after the server replies',
      (tester) async {
    await pumpApp(tester);

    expect(find.text('128'), findsWidgets, reason: 'hero starts on 128 upvotes');

    await tester.tap(find.text('SEJ BO').first);
    await tester.pump();
    expect(find.text('129'), findsWidgets, reason: 'count moves optimistically');

    // Let the response land: the count must survive reconciliation rather than
    // snapping back, since the server's my_vote now replaces the local guess.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('129'), findsWidgets, reason: 'server response agreed');
  });

  testWidgets('switching to Slovenian translates the chrome', (tester) async {
    await pumpApp(tester, lang: Lang.sl);
    expect(find.text('DOMOV'), findsOneWidget);
    expect(find.text('GALERIJA'), findsOneWidget);
    expect(find.text('NALOŽI'), findsOneWidget);
    expect(find.text('PODPRI'), findsOneWidget);
  });

  group('Post model', () {
    test('parses the documented wire format', () {
      final p = Post.fromJson({
        'id': 7,
        'title': 'Microwaved a salad',
        'description': 'warm and wrong',
        'kind': 'image',
        'image_url': 'https://sejbosejbo.fyi/uploads/a.jpg',
        'featured': true,
        'pinned': false,
        'created_at': '2026-07-19T00:29:00Z',
      });

      expect(p.id, 7);
      expect(p.featured, isTrue);
      expect(p.isStory, isFalse);
      expect(p.createdAt.toUtc(), DateTime.utc(2026, 7, 19, 0, 29));
    });

    test('an image post with no URL is still not treated as a story', () {
      // Regression guard: isStory used to key off image_url, which silently hid
      // the description whenever a photo post arrived without a usable URL.
      final p = Post.fromJson({
        'id': 1,
        'title': 't',
        'description': 'this must survive',
        'kind': 'image',
        'image_url': null,
        'created_at': '2026-07-19T00:29:00Z',
      });

      expect(p.isStory, isFalse);
    });

    test('tolerates missing optional fields', () {
      final p = Post.fromJson({'id': 2, 'title': 'x', 'created_at': 'nonsense'});
      expect(p.description, '');
      expect(p.featured, isFalse);
      expect(p.imageUrl, isNull);
      expect(p.commentCount, 0, reason: 'a server that predates comments still parses');
    });

    test('reads comment_count', () {
      final p = Post.fromJson({'id': 3, 'title': 'x', 'created_at': '', 'comment_count': 12});
      expect(p.commentCount, 12);
    });

    test('kind is an open set - audio and video are not treated as images', () {
      // Audio/video exist server-side behind a flag. If an unknown kind fell
      // through to the image path, Image.network would pull a whole .mp4 over
      // mobile data before failing.
      for (final kind in ['audio', 'video', 'something-invented-later']) {
        final p = Post.fromJson({
          'id': 4,
          'title': 'x',
          'kind': kind,
          'image_url': 'https://sejbosejbo.fyi/uploads/a.mp4',
          'created_at': '',
        });
        expect(p.isUnsupported, isTrue, reason: '$kind must not render as an image');
        expect(p.isStory, isFalse);
      }

      for (final kind in ['image', 'story']) {
        expect(
          Post.fromJson({'id': 5, 'title': 'x', 'kind': kind, 'created_at': ''}).isUnsupported,
          isFalse,
        );
      }
    });
  });

  group('my_vote', () {
    // The whole point of the field is the difference between "unknown" and
    // "not voted". Collapsing them is the bug it exists to fix.
    test('a missing field is unknown, NOT unvoted', () {
      expect(Post.fromJson({'id': 1, 'title': 'x', 'created_at': ''}).myVote, isNull);
      expect(Comment.fromJson({'id': 1, 'created_at': ''}).myVote, isNull);
    });

    test('an explicit 0 means known and unvoted', () {
      expect(Post.fromJson({'id': 1, 'title': '', 'created_at': '', 'my_vote': 0}).myVote, 0);
      expect(Comment.fromJson({'id': 1, 'created_at': '', 'my_vote': 0}).myVote, 0);
    });

    test('carries 1 and -1 through', () {
      expect(Post.fromJson({'id': 1, 'title': '', 'created_at': '', 'my_vote': 1}).myVote, 1);
      expect(Post.fromJson({'id': 1, 'title': '', 'created_at': '', 'my_vote': -1}).myVote, -1);
    });

    test('the offline cache round-trip preserves unknown as unknown', () {
      // toJson omits the key when null; re-parsing must not invent a 0, or a
      // cached feed would claim the user has not voted on anything.
      final unknown = Post.fromJson({'id': 1, 'title': 'x', 'created_at': ''});
      expect(unknown.toJson().containsKey('my_vote'), isFalse);
      expect(Post.fromJson(unknown.toJson()).myVote, isNull);

      final voted = Post.fromJson({'id': 1, 'title': 'x', 'created_at': '', 'my_vote': -1});
      expect(Post.fromJson(voted.toJson()).myVote, -1);
    });

    test('reads send the device id, since my_vote is keyed off it', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await Prefs.load();
      final seen = <http.BaseRequest>[];
      final api = Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        prefs: prefs,
        client: MockClient((req) async {
          seen.add(req);
          return http.Response('{"items":[],"page":1,"total":0,"has_next":false}', 200);
        }),
      );

      await api.posts();
      await api.comments(1);
      expect(seen, hasLength(2));
      for (final req in seen) {
        expect(req.headers['X-Device-Id'], prefs.deviceId,
            reason: 'without it the server omits my_vote entirely');
      }
    });

    test('no prefs means no device id, and the field stays unknown', () async {
      late http.BaseRequest sent;
      final api = Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        client: MockClient((req) async {
          sent = req;
          return http.Response('{"items":[{"id":1,"title":"x","created_at":""}]}', 200);
        }),
      );
      final page = await api.posts();
      expect(sent.headers.keys.map((k) => k.toLowerCase()), isNot(contains('x-device-id')));
      expect(page.items.single.myVote, isNull);
    });
  });

  group('rate limiting', () {
    Api build(Map<String, String> headers, String body) => Api(
          baseUrl: 'https://example.test',
          useDemoData: false,
          client: MockClient((_) async => http.Response(body, 429, headers: headers)),
        );

    test('reads Retry-After from the header', () async {
      await expectLater(
        () => build({'retry-after': '40'}, '{"error":"too fast"}').addComment(1, 'x'),
        throwsA(isA<ApiException>()
            .having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 40))),
      );
    });

    test('falls back to retry_after_seconds when the header is stripped', () async {
      // Proxies drop headers; the body carries the same number for that case.
      await expectLater(
        () => build({}, '{"error":"too fast","retry_after_seconds":25}').addComment(1, 'x'),
        throwsA(isA<ApiException>()
            .having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 25))),
      );
    });

    test("shows the server's own wording, which names the limit that was hit", () async {
      final api = build({'retry-after': '40'},
          '{"error":"Too many comments from this address. Give it a minute."}');
      await expectLater(
        () => api.addComment(1, 'x'),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', contains('Give it a minute'))),
      );
    });

    test('a 429 with no timing at all still throws, just without a countdown', () async {
      await expectLater(
        () => build({}, 'not json').addComment(1, 'x'),
        throwsA(isA<ApiException>().having((e) => e.retryAfter, 'retryAfter', isNull)),
      );
    });

    test('applies to votes and reports too', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await Prefs.load();
      final voteApi = Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        prefs: prefs,
        client: MockClient((_) async => http.Response('{}', 429, headers: {'retry-after': '5'})),
      );
      await expectLater(
        () => voteApi.voteComment(1, 1),
        throwsA(isA<ApiException>()
            .having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 5))),
      );

      await expectLater(
        () => build({'retry-after': '900'}, '{}').reportPost(1, ReportReason.spam),
        throwsA(isA<ApiException>()
            .having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 900))),
      );
    });
  });

  group('comment sort', () {
    test('sends the requested sort and reads the echo', () async {
      late http.Request sent;
      final api = Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        client: MockClient((req) async {
          sent = req;
          return http.Response('{"items":[],"sort":"top"}', 200);
        }),
      );
      final page = await api.comments(1, sort: CommentSort.top);
      expect(sent.url.queryParameters['sort'], 'top');
      expect(page.sort, CommentSort.top);
    });

    test('trusts the echo over the request', () async {
      // The server falls back to oldest on anything it does not recognise, so
      // the UI must read what was applied rather than assume it got its way.
      final api = Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        client: MockClient((_) async => http.Response('{"items":[],"sort":"oldest"}', 200)),
      );
      expect((await api.comments(1, sort: CommentSort.top)).sort, CommentSort.oldest);
    });

    test('an unknown or missing sort reads as oldest', () {
      expect(CommentSort.fromWire('nonsense'), CommentSort.oldest);
      expect(CommentSort.fromWire(null), CommentSort.oldest);
      expect(CommentSort.fromWire('top'), CommentSort.top);
    });
  });

  group('version comparison', () {
    test('compares numerically, not as strings', () {
      // The bug this exists to prevent: '1.10.0' sorts BEFORE '1.9.0'
      // lexically, so a string-compared gate silently stops gating at 1.10.
      expect('1.10.0'.compareTo('1.9.0') < 0, isTrue, reason: 'string compare is wrong');
      expect(compareVersions('1.10.0', '1.9.0'), greaterThan(0));
      expect(compareVersions('2.0.0', '1.99.99'), greaterThan(0));
      expect(compareVersions('1.8.0', '1.8.0'), 0);
      expect(compareVersions('1.8.0', '1.8.1'), lessThan(0));
    });

    test('missing segments count as zero', () {
      expect(compareVersions('1.8', '1.8.0'), 0);
      expect(compareVersions('1', '1.0.0'), 0);
      expect(compareVersions('1.8', '1.8.1'), lessThan(0));
    });

    test('ignores build and pre-release suffixes', () {
      expect(compareVersions('1.8.0+10', '1.8.0'), 0);
      expect(compareVersions('1.8.0+10', '1.8.0+99'), 0, reason: 'build number is Play\'s concern');
      expect(compareVersions('2.0-rc1', '2.0.0'), 0);
    });
  });

  group('update gate', () {
    const mine = '1.8.0';

    test('blocks only when strictly older than min_version', () {
      expect(AppRelease.fromJson({'min_version': '1.9.0'}).blocks(mine), isTrue);
      expect(AppRelease.fromJson({'min_version': '1.8.0'}).blocks(mine), isFalse,
          reason: 'equal to the minimum is allowed');
      expect(AppRelease.fromJson({'min_version': '1.7.0'}).blocks(mine), isFalse);
      expect(AppRelease.fromJson({'min_version': '1.10.0'}).blocks(mine), isTrue,
          reason: 'double-digit minor must still gate');
    });

    test('never blocks on a missing, empty or junk min_version', () {
      // Fail open. A gate that fails closed bricks every install at once, and
      // the only fix would be a store release.
      expect(AppRelease.fromJson(const {}).blocks(mine), isFalse);
      expect(AppRelease.fromJson({'min_version': ''}).blocks(mine), isFalse);
      expect(AppRelease.fromJson({'min_version': '   '}).blocks(mine), isFalse);
      expect(AppRelease.fromJson({'min_version': 'latest'}).blocks(mine), isFalse);
      expect(AppRelease.fromJson({'min_version': 'null'}).blocks(mine), isFalse);
    });

    test('a soft update nudge is separate from the hard block', () {
      final r = AppRelease.fromJson({'min_version': '1.0.0', 'latest_version': '1.9.0'});
      expect(r.blocks(mine), isFalse, reason: 'newer existing is not a reason to lock out');
      expect(r.updateAvailable(mine), isTrue);
    });

    test('release() returns null on every kind of failure, so nothing blocks', () async {
      Future<void> expectNull(http.Response Function() respond) async {
        final api = Api(
          baseUrl: 'https://example.test',
          useDemoData: false,
          client: MockClient((_) async => respond()),
        );
        expect(await api.release(), isNull);
      }

      await expectNull(() => http.Response('', 404));       // endpoint not shipped
      await expectNull(() => http.Response('', 500));       // server on fire
      await expectNull(() => http.Response('<html>', 200)); // captive portal
      await expectNull(() => http.Response('null', 200));   // valid JSON, wrong shape

      final offline = Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        client: MockClient((_) async => throw Exception('no network')),
      );
      expect(await offline.release(), isNull);
    });

    test('parses the documented shape', () async {
      final api = Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        client: MockClient(
          (_) async => http.Response(
            '{"min_version":"1.5.0","latest_version":"1.8.0",'
            '"server_version":"1.13.0","message":"Voting changed."}',
            200,
          ),
        ),
      );
      final r = await api.release();
      expect(r!.minVersion, '1.5.0');
      expect(r.latestVersion, '1.8.0');
      expect(r.serverVersion, '1.13.0');
      expect(r.message, 'Voting changed.');
      expect(r.blocks('1.8.0'), isFalse);
      expect(r.blocks('1.4.0'), isTrue);
    });
  });

  group('donation verification', () {
    Api build(int status, [String body = '{}', Map<String, String>? headers]) => Api(
          baseUrl: 'https://example.test',
          useDemoData: false,
          client: MockClient((_) async => http.Response(body, status, headers: headers ?? const {})),
        );

    test('posts the documented shape to the right provider path', () async {
      late http.Request sent;
      final api = Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        client: MockClient((req) async {
          sent = req;
          return http.Response('', 200);
        }),
      );

      await api.verifyStorePurchase(
        platform: 'google',
        productId: 'fyi.sejbosejbo.tip.medium',
        token: 'tok_123',
      );
      expect(sent.url.path, '/api/v1/donations/google/verify');
      expect(jsonDecode(sent.body),
          {'product_id': 'fyi.sejbosejbo.tip.medium', 'token': 'tok_123'});
    });

    test('200 with an empty body is success, not a parse error', () async {
      // The server returns 200 and nothing else; treating that as malformed
      // would leave a verified tip looking like a failure.
      await build(200, '').verifyStorePurchase(
          platform: 'google', productId: 'x', token: 't');
    });

    test('400 throws so the caller does NOT finish the transaction', () async {
      await expectLater(
        () => build(400, '{"error":"Receipt did not check out."}')
            .verifyStorePurchase(platform: 'google', productId: 'x', token: 't'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 400)
            .having((e) => e.message, 'message', contains('did not check out'))),
      );
    });

    test('503 is flagged as "not configured yet", not a user-facing failure', () async {
      await expectLater(
        () => build(503).verifyStorePurchase(platform: 'apple', productId: 'x', token: 't'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 503)),
      );
    });

    test('429 carries the retry delay', () async {
      await expectLater(
        () => build(429, '{"error":"slow down"}', {'retry-after': '30'})
            .verifyStorePurchase(platform: 'google', productId: 'x', token: 't'),
        throwsA(isA<ApiException>()
            .having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 30))),
      );
    });

    test('a network failure throws rather than silently passing', () async {
      // The old code swallowed everything, so an unreachable server looked
      // identical to a verified tip - and the purchase was acknowledged anyway.
      final api = Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        client: MockClient((_) async => throw Exception('offline')),
      );
      await expectLater(
        () => api.verifyStorePurchase(platform: 'google', productId: 'x', token: 't'),
        throwsA(isA<ApiException>()),
      );
    });

    test('stripe session returns the checkout URL', () async {
      final api = build(200, '{"url":"https://checkout.stripe.com/c/pay/cs_test_1"}');
      expect(await api.createStripeCheckout(tierId: 'medium'),
          'https://checkout.stripe.com/c/pay/cs_test_1');
    });

    test('stripe 503 is distinguishable, so the UI can hide tipping', () async {
      await expectLater(
        () => build(503, '{"error":"Stripe is not configured."}')
            .createStripeCheckout(tierId: 'medium'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 503)),
      );
    });

    test('a 200 with no url is a failure, not an empty launch', () async {
      await expectLater(
        () => build(200, '{}').createStripeCheckout(tierId: 'small'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('donation tiers match the store', () {
    test('product ids are exactly what Play and App Store Connect expect', () {
      expect(kDonationTiers.map((t) => t.storeProductId), [
        'fyi.sejbosejbo.tip.small',
        'fyi.sejbosejbo.tip.medium',
        'fyi.sejbosejbo.tip.large',
      ]);
    });

    test('tier ids are what the Stripe endpoint expects', () {
      expect(kDonationTiers.map((t) => t.id), ['small', 'medium', 'large']);
    });

    test('handedOff is not success - the browser may still be abandoned', () {
      final tier = kDonationTiers.first;
      expect(DonationResult.handedOff(tier).ok, isFalse);
      expect(DonationResult.handedOff(tier).pending, isTrue);
      expect(DonationResult.success(tier).ok, isTrue);
      expect(const DonationResult.notAvailable('503').unavailable, isTrue);
      expect(const DonationResult.notAvailable('503').ok, isFalse);
    });
  });

  group('a tier the store does not offer', () {
    test('donate() fails politely instead of throwing', () async {
      // Regression guard. This used to be firstWhere(orElse: throw StateError),
      // outside the try, so tapping a tier Play had not returned crashed
      // instead of showing a message. It happened for real: Play returned one
      // of the three products and the other two were still unpriced.
      final gateway = DonationGateway(
        Api(baseUrl: 'https://example.test', useDemoData: false),
      );
      addTearDown(gateway.dispose);

      // No init(), so no products are known - the same state as a tier the
      // store declined to return.
      final result = await gateway.donate(kDonationTiers[1]);
      expect(result.ok, isFalse);
      expect(result.error, isNotNull);
    });

    test('availability follows the rail, not a hardcoded assumption', () {
      final gateway = DonationGateway(
        Api(baseUrl: 'https://example.test', useDemoData: false),
      );
      addTearDown(gateway.dispose);

      for (final t in kDonationTiers) {
        if (DonationGateway.supportsStoreBilling) {
          // A store rail with no products loaded: nothing is purchasable, and
          // that must be visible rather than papered over with our own price.
          expect(gateway.hasProduct(t), isFalse);
        } else {
          // Stripe rail: the tiers are ours, so they are always offerable and
          // must not be greyed out on desktop.
          expect(gateway.hasProduct(t), isTrue);
          expect(gateway.priceFor(t), t.display);
        }
      }
    });
  });

  group('signed device ids', () {
    test('parses the minted id', () async {
      final api = Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        client: MockClient(
          (_) async => http.Response('{"device_id":"v1_abc_def"}', 200),
        ),
      );
      expect(await api.mintDeviceId(), 'v1_abc_def');
    });

    test('hits POST /device', () async {
      late http.Request sent;
      final api = Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        client: MockClient((req) async {
          sent = req;
          return http.Response('{"device_id":"v1_x"}', 200);
        }),
      );
      await api.mintDeviceId();
      expect(sent.method, 'POST');
      expect(sent.url.path, '/api/v1/device');
    });

    test('returns null on every failure, so the local id keeps working', () async {
      // Minting is capped at 10/hour per IP. A failure must never block voting;
      // the server still accepts unsigned ids.
      for (final response in [
        () => http.Response('', 429),
        () => http.Response('', 500),
        () => http.Response('{}', 200),
        () => http.Response('{"device_id":""}', 200),
        () => http.Response('not json', 200),
      ]) {
        final api = Api(
          baseUrl: 'https://example.test',
          useDemoData: false,
          client: MockClient((_) async => response()),
        );
        expect(await api.mintDeviceId(), isNull);
      }

      final offline = Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        client: MockClient((_) async => throw Exception('offline')),
      );
      expect(await offline.mintDeviceId(), isNull);
    });

    test('a signed id is recognised, a locally generated one is not', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await Prefs.load();

      // Untouched: the getter mints a local hex id on first read.
      expect(prefs.hasSignedDeviceId, isFalse);
      final local = prefs.deviceId;
      expect(local, matches(RegExp(r'^[0-9a-f]{32}$')));

      await prefs.setDeviceId('v1_khQnVEOqdDB4SiOzVL4cA-bD_yEuq5mhQhHsXsFxYXVFHPIGbgKo6tyGB');
      expect(prefs.hasSignedDeviceId, isTrue);
      expect(prefs.deviceId, startsWith('v1_'));
    });

    test('a stored signed id is kept, so minting runs at most once', () async {
      SharedPreferences.setMockInitialValues({'device_id': 'v1_already_have_one'});
      final prefs = await Prefs.load();
      expect(prefs.hasSignedDeviceId, isTrue);
      expect(prefs.deviceId, 'v1_already_have_one');
    });

    test('both id shapes satisfy the server pattern', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await Prefs.load();
      final pattern = RegExp(r'^[A-Za-z0-9_-]{8,128}$');
      expect(prefs.deviceId, matches(pattern));
      await prefs.setDeviceId('v1_khQnVEOqdDB4SiOzVL4cA-bD_yEuq5mhQhHsXsFxYXVFHPIGbgKo6tyGB');
      expect(prefs.deviceId, matches(pattern));
    });
  });

  group('push registration', () {
    test('posts the documented shape', () async {
      late http.Request sent;
      final api = Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        client: MockClient((req) async {
          sent = req;
          return http.Response('{"ok":true,"delivery_enabled":false}', 200);
        }),
      );

      await api.registerPush(token: 'fcm-token', platform: 'android', lang: 'sl');
      expect(sent.url.path, '/api/v1/push/register');
      expect(jsonDecode(sent.body),
          {'token': 'fcm-token', 'platform': 'android', 'lang': 'sl'});
    });

    test('reports delivery_enabled without gating on it', () async {
      // Tokens registered while delivery is off are kept server-side and get
      // the first notification once Firebase credentials land, so false must
      // not read as a failure.
      Api build(String body) => Api(
            baseUrl: 'https://example.test',
            useDemoData: false,
            client: MockClient((_) async => http.Response(body, 200)),
          );

      expect(await build('{"ok":true,"delivery_enabled":false}')
          .registerPush(token: 't', platform: 'android', lang: 'en'), isFalse);
      expect(await build('{"ok":true,"delivery_enabled":true}')
          .registerPush(token: 't', platform: 'android', lang: 'en'), isTrue);
      // Missing field is not an error either.
      expect(await build('{"ok":true}')
          .registerPush(token: 't', platform: 'android', lang: 'en'), isFalse);
    });

    test('400 surfaces the server wording', () async {
      final api = Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        client: MockClient(
          (_) async => http.Response('{"error":"A valid token is required."}', 400),
        ),
      );
      await expectLater(
        () => api.registerPush(token: '', platform: 'android', lang: 'en'),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', contains('valid token'))),
      );
    });

    test('429 carries the retry delay, so nothing loops', () async {
      final api = Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        client: MockClient(
          (_) async => http.Response('{}', 429, headers: {'retry-after': '120'}),
        ),
      );
      await expectLater(
        () => api.registerPush(token: 't', platform: 'android', lang: 'en'),
        throwsA(isA<ApiException>()
            .having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 120))),
      );
    });

    test('unregister posts just the token', () async {
      late http.Request sent;
      final api = Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        client: MockClient((req) async {
          sent = req;
          return http.Response('{"ok":true}', 200);
        }),
      );
      await api.unregisterPush('fcm-token');
      expect(sent.url.path, '/api/v1/push/unregister');
      expect(jsonDecode(sent.body), {'token': 'fcm-token'});
    });

    test('notifications default to on, and the token round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await Prefs.load();
      // Defaulting to off would silently opt everyone out; the OS permission
      // prompt is the real gate.
      expect(prefs.pushEnabled, isTrue);
      expect(prefs.pushToken, isNull);

      await prefs.setPushToken('abc');
      expect(prefs.pushToken, 'abc');
      await prefs.setPushEnabled(false);
      expect(prefs.pushEnabled, isFalse);
      await prefs.setPushToken(null);
      expect(prefs.pushToken, isNull);
    });
  });

  group('donation tiers', () {
    test('prices are whole euros in minor units', () {
      expect(kDonationTiers.map((t) => t.amountMinor), [200, 500, 1500]);
      expect(kDonationTiers.map((t) => t.display), ['€2', '€5', '€15']);
    });

    test('store product ids are unique and namespaced', () {
      final ids = kDonationTiers.map((t) => t.storeProductId).toSet();
      expect(ids.length, kDonationTiers.length);
      expect(ids.every((id) => id.startsWith('fyi.sejbosejbo.tip.')), isTrue);
    });
  });
}

/// Regression guard for the upload MIME bug: package:http defaults multipart
/// files to application/octet-stream, which the server rejects outright with
/// "Only images and GIFs are allowed right now."
void _uploadContentTypeTests() {
  group('upload content type', () {
    late List<http.BaseRequest> sent;
    late Api api;

    setUp(() {
      sent = [];
      api = Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        client: MockClient.streaming((req, bytes) async {
          sent.add(req);
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({
              'id': 1,
              'title': 't',
              'kind': 'image',
              'created_at': '2026-01-01T00:00:00Z',
            }))),
            201,
          );
        }),
      );
    });

    Future<String> contentTypeFor(List<int> magic) async {
      await api.createPost(
        title: 't',
        description: '',
        imageBytes: Uint8List.fromList([...magic, ...List.filled(32, 0)]),
        imageName: 'whatever.bin',
      );
      final f = (sent.last as http.MultipartRequest).files.single;
      return f.contentType.toString();
    }

    test('JPEG magic bytes are sent as image/jpeg', () async {
      expect(await contentTypeFor([0xFF, 0xD8, 0xFF]), 'image/jpeg');
    });

    test('PNG magic bytes are sent as image/png', () async {
      expect(await contentTypeFor([0x89, 0x50, 0x4E, 0x47]), 'image/png');
    });

    test('GIF magic bytes are sent as image/gif', () async {
      expect(await contentTypeFor([0x47, 0x49, 0x46, 0x38]), 'image/gif');
    });

    test('never sends application/octet-stream', () async {
      final ct = await contentTypeFor([0xFF, 0xD8, 0xFF]);
      expect(ct, isNot(contains('octet-stream')));
    });
  });
}

/// Comments. The shapes asserted here were captured from the live API, not from
/// the spec - GET/POST responses, the per_page clamp and every documented error.
void _commentTests() {
  group('comments', () {
    late List<http.Request> sent;

    Api build(int status, String body) {
      sent = [];
      return Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        client: MockClient((req) async {
          sent.add(req);
          return http.Response(body, status, headers: {'content-type': 'application/json'});
        }),
      );
    }

    test('parses the live GET shape, oldest first', () async {
      final api = build(200, jsonEncode({
        'items': [
          {'id': 6, 'post_id': 57, 'body': 'jabuk', 'created_at': '2026-08-14T19:34:03.000Z'},
          {'id': 7, 'post_id': 57, 'body': 'second', 'created_at': '2026-08-14T19:36:07.000Z'},
        ],
        'page': 1,
        'per_page': 50,
        'total': 2,
        'has_next': false,
      }));

      final page = await api.comments(57);
      expect(sent.single.url.path, '/api/v1/posts/57/comments');
      expect(page.items.map((c) => c.body), ['jabuk', 'second']);
      expect(page.items.first.createdAt.toUtc(), DateTime.utc(2026, 8, 14, 19, 34, 3));
      expect(page.total, 2);
      expect(page.hasNext, isFalse);
    });

    test('per_page is clamped to the 100 the server enforces', () async {
      final api = build(200, '{"items":[],"page":1,"per_page":100,"total":0,"has_next":false}');
      await api.comments(57, perPage: 999);
      expect(sent.single.url.queryParameters['per_page'], '100');
    });

    test('posts the documented body and trims whitespace', () async {
      final api = build(201, jsonEncode({
        'id': 8,
        'post_id': 57,
        'body': 'hello',
        'created_at': '2026-08-14T19:40:00.000Z',
      }));

      final c = await api.addComment(57, '  hello  ');
      expect(sent.single.url.path, '/api/v1/posts/57/comments');
      expect(jsonDecode(sent.single.body), {'body': 'hello'});
      expect(c.id, 8);
      expect(c.body, 'hello');
    });

    test('sends the device id so this install can badge its own comments', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await Prefs.load();
      final api = Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        prefs: prefs,
        client: MockClient((req) async {
          sent = [req];
          return http.Response('{"id":1,"post_id":1,"body":"x","created_at":""}', 201);
        }),
      );

      await api.addComment(1, 'x');
      expect(sent.single.headers['X-Device-Id'], prefs.deviceId);
    });

    test('an empty comment never leaves the device', () async {
      final api = build(201, '{}');
      await expectLater(() => api.addComment(1, '   \n '), throwsA(isA<ApiException>()));
      expect(sent, isEmpty, reason: 'the server 400s on this, so do not ask it');
    });

    test('an over-long comment never leaves the device', () async {
      final api = build(201, '{}');
      await expectLater(() => api.addComment(1, 'x' * 1001), throwsA(isA<ApiException>()));
      expect(sent, isEmpty);
    });

    test('1000 characters is accepted - the limit is inclusive', () async {
      final api = build(201, '{"id":1,"post_id":1,"body":"x","created_at":""}');
      await api.addComment(1, 'x' * 1000);
      expect(sent, hasLength(1));
    });

    test('surfaces the server wording on 400 rather than a status code', () async {
      final api = build(400, '{"error":"Comment is too long (max 1000 characters)."}');
      await expectLater(
        () => api.addComment(1, 'x'),
        throwsA(
          isA<ApiException>().having((e) => e.message, 'message', contains('max 1000 characters')),
        ),
      );
    });

    test('429 surfaces a rate-limit message', () async {
      final api = build(429, '{"error":"rate limited"}');
      await expectLater(
        () => api.addComment(1, 'x'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 429)),
      );
    });

    test('404 surfaces a missing-post message', () async {
      final api = build(404, '{"error":"Post not found."}');
      await expectLater(
        () => api.addComment(1, 'x'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
      );
    });

    test('Comment.maxLength matches the server contract', () {
      expect(Comment.maxLength, 1000);
      expect(CommentPage.maxPerPage, 100);
    });

    test('parses upvotes and downvotes, defaulting to zero on older servers', () {
      final c = Comment.fromJson({
        'id': 6,
        'post_id': 57,
        'body': 'jabuk',
        'created_at': '2026-08-14T19:34:03.000Z',
        'upvotes': 3,
        'downvotes': 1,
      });
      expect(c.score, 2);
      expect(Comment.fromJson({'id': 1, 'created_at': ''}).score, 0);
    });
  });

  group('comment voting', () {
    test('sends the device id, which is required here unlike posting', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await Prefs.load();
      late http.Request sent;
      final api = Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        prefs: prefs,
        client: MockClient((req) async {
          sent = req;
          return http.Response(
            '{"id":6,"post_id":57,"body":"jabuk","created_at":"","upvotes":1,"downvotes":0}',
            200,
          );
        }),
      );

      final c = await api.voteComment(6, 1);
      expect(sent.url.path, '/api/v1/comments/6/vote');
      expect(jsonDecode(sent.body), {'value': 1});
      expect(sent.headers['X-Device-Id'], prefs.deviceId);
      expect(c.upvotes, 1);
    });

    test('the generated device id satisfies the server pattern', () async {
      // The server 400s on anything outside [A-Za-z0-9_-]{8,128}, and a vote
      // that always fails would be invisible behind the optimistic UI.
      SharedPreferences.setMockInitialValues({});
      final prefs = await Prefs.load();
      expect(prefs.deviceId, matches(RegExp(r'^[A-Za-z0-9_-]{8,128}$')));
    });

    test('refuses to vote with no device id rather than earning a 400', () async {
      var called = false;
      final api = Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        client: MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );
      await expectLater(() => api.voteComment(6, 1), throwsA(isA<ApiException>()));
      expect(called, isFalse);
    });

    test('404 and 429 surface with their status attached', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await Prefs.load();
      Api build(int status) => Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        prefs: prefs,
        client: MockClient((_) async => http.Response('{"error":"x"}', status)),
      );

      await expectLater(
        () => build(404).voteComment(6, 1),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
      );
      await expectLater(
        () => build(429).voteComment(6, 1),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 429)),
      );
    });

    test('withdrawing sends 0, matching post voting', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await Prefs.load();
      late http.Request sent;
      final api = Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        prefs: prefs,
        client: MockClient((req) async {
          sent = req;
          return http.Response('{"id":6,"created_at":"","upvotes":0,"downvotes":0}', 200);
        }),
      );
      await api.voteComment(6, 0);
      expect(jsonDecode(sent.body), {'value': 0});
    });

    test('applyVoteDelta covers every transition and never goes negative', () {
      expect(applyVoteDelta(5, 2, 0, 1), (up: 6, down: 2));
      expect(applyVoteDelta(5, 2, 0, -1), (up: 5, down: 3));
      expect(applyVoteDelta(5, 2, 1, 0), (up: 4, down: 2));
      expect(applyVoteDelta(5, 2, 1, -1), (up: 4, down: 3), reason: 'flip moves both counts');
      expect(applyVoteDelta(5, 2, -1, 1), (up: 6, down: 1));
      // Local state can drift from the server's; a stale "previous" must not
      // render a negative count.
      expect(applyVoteDelta(0, 0, 1, 0), (up: 0, down: 0));
    });

    test('the vote response carries my_vote, which the UI reconciles against', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await Prefs.load();
      final api = Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        prefs: prefs,
        client: MockClient(
          (_) async => http.Response(
            '{"id":6,"post_id":57,"body":"x","created_at":"","upvotes":1,'
            '"downvotes":0,"my_vote":1}',
            200,
          ),
        ),
      );
      expect((await api.voteComment(6, 1)).myVote, 1);
    });
  });

  group('comment reporting', () {
    test('hits the comments path, with no device id', () async {
      late http.Request sent;
      final api = Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        client: MockClient((req) async {
          sent = req;
          return http.Response('{"ok":true}', 201);
        }),
      );

      await api.reportComment(6, ReportReason.spam, details: 'nope');
      expect(sent.url.path, '/api/v1/comments/6/report');
      expect(jsonDecode(sent.body), {'reason': 'spam', 'details': 'nope'});
      expect(sent.headers.keys.map((k) => k.toLowerCase()), isNot(contains('x-device-id')));
    });

    test('posts still hit the posts path', () async {
      late http.Request sent;
      final api = Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        client: MockClient((req) async {
          sent = req;
          return http.Response('{"ok":true}', 201);
        }),
      );
      await api.reportPost(6, ReportReason.spam);
      expect(sent.url.path, '/api/v1/posts/6/report');
    });

    test('a 404 on a comment says comment, not post', () async {
      final api = Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        client: MockClient((_) async => http.Response('{"error":"Comment not found."}', 404)),
      );
      await expectLater(
        () => api.reportComment(6, ReportReason.spam),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('comment'))),
      );
    });
  });
}

/// The report endpoint is a store requirement (Play UGC policy, Apple 1.2), so
/// its wire format and failure handling are worth pinning down.
void _reportTests() {
  group('report', () {
    late List<http.Request> sent;
    late Api api;

    Api build(int status, String body) {
      sent = [];
      return Api(
        baseUrl: 'https://example.test',
        useDemoData: false,
        client: MockClient((req) async {
          sent.add(req);
          return http.Response(body, status);
        }),
      );
    }

    test('posts the documented shape and trims details to 500 chars', () async {
      api = build(201, '{"ok":true}');
      await api.reportPost(7, ReportReason.harassment, details: 'x' * 900);

      expect(sent.single.url.path, '/api/v1/posts/7/report');
      final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
      expect(body['reason'], 'harassment');
      expect((body['details'] as String).length, 500);
    });

    test('omits details when blank rather than sending an empty string', () async {
      api = build(201, '{"ok":true}');
      await api.reportPost(7, ReportReason.spam, details: '   ');
      expect(jsonDecode(sent.single.body), isNot(contains('details')));
    });

    test('sends no device id — repeat reports are signal, not abuse', () async {
      api = build(201, '{"ok":true}');
      await api.reportPost(7, ReportReason.other);
      expect(sent.single.headers.keys.map((k) => k.toLowerCase()), isNot(contains('x-device-id')));
    });

    test('429 surfaces a rate-limit message', () async {
      api = build(429, '{"error":"rate limited"}');
      expect(
        () => api.reportPost(7, ReportReason.spam),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 429)),
      );
    });

    test('404 surfaces a missing-post message', () async {
      api = build(404, '{"error":"Post not found."}');
      expect(
        () => api.reportPost(7, ReportReason.spam),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
      );
    });

    test('reason wire values match what the server accepts', () {
      expect(
        ReportReason.values.map((r) => r.wire),
        ['spam', 'inappropriate', 'harassment', 'copyright', 'other'],
      );
    });
  });
}


/// Stands in for Google Play, which cannot run in a widget test.
class _FakeStore implements StoreUpdates {
  _FakeStore({required this.ready, this.accepts = true});

  final bool ready;

  /// Whether the user goes through with Play's dialog.
  final bool accepts;

  int immediateStarted = 0;

  @override
  Future<bool> isUpdateReady() async => ready;

  @override
  Future<bool> startImmediateUpdate() async {
    immediateStarted++;
    return accepts;
  }
}
