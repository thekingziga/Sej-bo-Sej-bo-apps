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
import 'package:shared_preferences/shared_preferences.dart';

/// A widget test fails on a RenderFlex overflow, so simply pumping every screen
/// at several phone sizes is what guards the layout - that is how the gallery's
/// featured-card overflow was caught.
void main() {
  _uploadContentTypeTests();
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

  testWidgets('voting on the hero updates the count and persists', (tester) async {
    final prefs = await pumpApp(tester);

    expect(find.text('128'), findsWidgets, reason: 'hero starts on 128 upvotes');

    await tester.tap(find.text('SEJ BO').first);
    await tester.pump();

    expect(find.text('129'), findsWidgets, reason: 'count moves optimistically');
    expect(prefs.voteFor(9), 1, reason: 'vote is remembered across launches');

    // Drain the demo vote() delay, or the binding fails on a pending timer.
    await tester.pump(const Duration(milliseconds: 400));
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
