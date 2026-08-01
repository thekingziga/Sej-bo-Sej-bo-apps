// Wire models. These mirror docs/API_PROMPT.md exactly - if you change a field
// here, change it there too, or the app and the website will drift apart.

class Post {
  const Post({
    required this.id,
    required this.title,
    required this.description,
    required this.kind,
    required this.imageUrl,
    required this.featured,
    required this.pinned,
    required this.createdAt,
  });

  final int id;
  final String title;
  final String description;

  /// 'image' or 'story'.
  final String kind;

  /// Absolute URL, or null for text-only posts.
  final String? imageUrl;
  final bool featured;
  final bool pinned;
  final DateTime createdAt;

  /// Keyed off [kind], not [imageUrl]. If a photo post ever arrives without a
  /// usable URL - API hiccup, broken file - we still want its description shown
  /// rather than silently swallowed as if it were a text-only post.
  bool get isStory => kind == 'story';

  factory Post.fromJson(Map<String, dynamic> j) => Post(
    id: (j['id'] as num).toInt(),
    title: (j['title'] ?? '') as String,
    description: (j['description'] ?? '') as String,
    kind: (j['kind'] ?? 'story') as String,
    imageUrl: j['image_url'] as String?,
    featured: j['featured'] == true,
    pinned: j['pinned'] == true,
    createdAt: DateTime.tryParse((j['created_at'] ?? '') as String)?.toLocal() ?? DateTime.now(),
  );
}

class Stats {
  const Stats({required this.visits, required this.uploads, required this.daysSinceLast});

  final int visits;
  final int uploads;

  /// Null when nothing has ever been posted.
  final int? daysSinceLast;

  factory Stats.fromJson(Map<String, dynamic> j) => Stats(
    visits: (j['visits'] as num?)?.toInt() ?? 0,
    uploads: (j['uploads'] as num?)?.toInt() ?? 0,
    daysSinceLast: (j['days_since_last'] as num?)?.toInt(),
  );
}

/// Everything the dashboard needs, in one round trip.
class Feed {
  const Feed({required this.stats, required this.quote, required this.daily, required this.posts});

  final Stats stats;
  final String quote;
  final Post? daily;

  /// Newest first. The dashboard shows [0] as the hero and the next 3 in a grid.
  final List<Post> posts;

  factory Feed.fromJson(Map<String, dynamic> j) => Feed(
    stats: Stats.fromJson((j['stats'] ?? const {}) as Map<String, dynamic>),
    quote: (j['quote'] ?? '') as String,
    daily: j['daily'] == null ? null : Post.fromJson(j['daily'] as Map<String, dynamic>),
    posts: ((j['posts'] ?? const []) as List)
        .map((e) => Post.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class PostPage {
  const PostPage({required this.items, required this.page, required this.hasNext});

  final List<Post> items;
  final int page;
  final bool hasNext;

  factory PostPage.fromJson(Map<String, dynamic> j) => PostPage(
    items: ((j['items'] ?? const []) as List)
        .map((e) => Post.fromJson(e as Map<String, dynamic>))
        .toList(),
    page: (j['page'] as num?)?.toInt() ?? 1,
    hasNext: j['has_next'] == true,
  );
}

/// A support tier. Amounts are minor units (cents) so there is no float money.
class DonationTier {
  const DonationTier({
    required this.id,
    required this.storeProductId,
    required this.label,
    required this.blurb,
    required this.amountMinor,
    required this.emoji,
  });

  final String id;

  /// Product identifier registered in App Store Connect / Play Console.
  final String storeProductId;
  final String label;
  final String blurb;
  final int amountMinor;
  final String emoji;

  String get display => '€${(amountMinor / 100).toStringAsFixed(amountMinor % 100 == 0 ? 0 : 2)}';
}

const kDonationTiers = <DonationTier>[
  DonationTier(
    id: 'small',
    storeProductId: 'fyi.sejbosejbo.tip.small',
    label: 'Small Sejbo',
    blurb: 'Buys one (1) server thought.',
    amountMinor: 200,
    emoji: '🐈',
  ),
  DonationTier(
    id: 'medium',
    storeProductId: 'fyi.sejbosejbo.tip.medium',
    label: 'Certified Sejbo',
    blurb: 'Keeps the Pi awake another month.',
    amountMinor: 500,
    emoji: '🔥',
  ),
  DonationTier(
    id: 'large',
    storeProductId: 'fyi.sejbosejbo.tip.large',
    label: 'Maximum Sejbo',
    blurb: 'Peak human generosity. Unhinged.',
    amountMinor: 1500,
    emoji: '👑',
  ),
];
