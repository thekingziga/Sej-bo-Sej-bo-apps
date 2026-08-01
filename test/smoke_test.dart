import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sejbosejbo/api.dart';
import 'package:sejbosejbo/donations.dart';
import 'package:sejbosejbo/main.dart';
import 'package:sejbosejbo/models.dart';
import 'package:sejbosejbo/screens/detail.dart';
import 'package:sejbosejbo/theme.dart';

/// A widget test fails on a RenderFlex overflow, so simply pumping every screen
/// at several phone sizes is what guards the layout - that is how the gallery's
/// featured-card overflow was caught.
void main() {
  Future<void> pumpApp(WidgetTester tester, {Size size = const Size(414, 896)}) async {
    tester.view.physicalSize = size * tester.view.devicePixelRatio;
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    final api = Api(useDemoData: true);
    addTearDown(api.close);
    final donations = DonationGateway(api);
    addTearDown(donations.dispose);

    await tester.pumpWidget(
      MaterialApp(theme: Brutal.theme(), home: Shell(api: api, donations: donations)),
    );
    // Demo endpoints are deliberately delayed; settle past them.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
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
    expect(find.textContaining('OFFICIALLY'), findsOneWidget);
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
