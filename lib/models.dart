// Wire models. These mirror docs/API_PROMPT.md exactly - if you change a field
// here, change it there too, or the app and the website will drift apart.

/// How the gallery is ordered. The value is sent to the API as `?sort=`.
enum PostSort {
  newest('newest'),
  top('top'),
  featured('featured');

  const PostSort(this.wire);
  final String wire;
}

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
    this.upvotes = 0,
    this.downvotes = 0,
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

  /// "sej bo" - yes, this really is Sejbosejbo.
  final int upvotes;

  /// "sej ne bo" - no, this does not qualify.
  final int downvotes;

  int get score => upvotes - downvotes;

  String shareUrl(String base) =>
      '${base.isEmpty ? 'https://sejbosejbo.fyi' : base}/post/$id';

  Post copyWith({int? upvotes, int? downvotes}) => Post(
    id: id,
    title: title,
    description: description,
    kind: kind,
    imageUrl: imageUrl,
    featured: featured,
    pinned: pinned,
    createdAt: createdAt,
    upvotes: upvotes ?? this.upvotes,
    downvotes: downvotes ?? this.downvotes,
  );

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
    upvotes: (j['upvotes'] as num?)?.toInt() ?? 0,
    downvotes: (j['downvotes'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'kind': kind,
    'image_url': imageUrl,
    'featured': featured,
    'pinned': pinned,
    'created_at': createdAt.toUtc().toIso8601String(),
    'upvotes': upvotes,
    'downvotes': downvotes,
  };
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

  Map<String, dynamic> toJson() => {
    'visits': visits,
    'uploads': uploads,
    'days_since_last': daysSinceLast,
  };
}

/// Everything the dashboard needs, in one round trip.
class Feed {
  const Feed({
    required this.stats,
    required this.quote,
    required this.daily,
    required this.posts,
    this.top = const [],
  });

  final Stats stats;
  final String quote;
  final Post? daily;

  /// Newest first. The dashboard shows [0] as the hero and the next 3 in a grid.
  final List<Post> posts;

  /// Highest scoring of all time - the Hall of Fame block.
  final List<Post> top;

  factory Feed.fromJson(Map<String, dynamic> j) => Feed(
    stats: Stats.fromJson((j['stats'] ?? const {}) as Map<String, dynamic>),
    quote: (j['quote'] ?? '') as String,
    daily: j['daily'] == null ? null : Post.fromJson(j['daily'] as Map<String, dynamic>),
    posts: ((j['posts'] ?? const []) as List)
        .map((e) => Post.fromJson(e as Map<String, dynamic>))
        .toList(),
    top: ((j['top'] ?? const []) as List)
        .map((e) => Post.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  /// Round-trips through Prefs so the dashboard can render offline.
  Map<String, dynamic> toJson() => {
    'stats': stats.toJson(),
    'quote': quote,
    'daily': daily?.toJson(),
    'posts': posts.map((p) => p.toJson()).toList(),
    'top': top.map((p) => p.toJson()).toList(),
  };
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
