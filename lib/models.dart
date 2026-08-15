// Wire models. These mirror docs/API_PROMPT.md exactly - if you change a field
// here, change it there too, or the app and the website will drift apart.

import 'version.dart';

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
    this.commentCount = 0,
    this.myVote,
  });

  final int id;
  final String title;
  final String description;

  /// Today: 'image' or 'story'. Tomorrow: 'audio' or 'video' - both are already
  /// built server-side and only waiting on a flag.
  ///
  /// Treat this as an **open set**. The server can start sending a new kind at
  /// any time without an app release, so the app must never assume an
  /// unrecognised kind is an image: [imageUrl] would then point at an .mp4 or
  /// .m4a, and handing that to Image.network downloads the whole file over
  /// mobile data before failing. See [isUnsupported].
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

  /// How many comments the thread holds. Server-maintained; the app only ever
  /// nudges it locally so a freshly posted comment shows up without a refetch.
  final int commentCount;

  /// This device's vote, straight from the server: 1, -1, or 0 for "known, and
  /// has not voted".
  ///
  /// **Null means unknown, not unvoted.** The server omits the field entirely
  /// when the request carried no usable `X-Device-Id`, and collapsing that into
  /// 0 would reintroduce the bug this field exists to fix - a button rendered
  /// unvoted for something already voted, which is also the cheapest way to
  /// vote twice. Never write `myVote ?? 0` at the parse layer; only the widget
  /// that has to paint *something* may fall back, and only for display.
  final int? myVote;

  int get score => upvotes - downvotes;

  String shareUrl(String base) =>
      '${base.isEmpty ? 'https://sejbosejbo.fyi' : base}/post/$id';

  /// Passing null for [myVote] keeps the current value rather than erasing it
  /// to "unknown" - nothing needs to erase it, and a copyWith that could would
  /// be an easy way to lose the distinction by accident.
  Post copyWith({int? upvotes, int? downvotes, int? commentCount, int? myVote}) => Post(
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
    commentCount: commentCount ?? this.commentCount,
    myVote: myVote ?? this.myVote,
  );

  /// The kinds this build knows how to render.
  static const knownKinds = {'image', 'story'};

  /// Keyed off [kind], not [imageUrl]. If a photo post ever arrives without a
  /// usable URL - API hiccup, broken file - we still want its description shown
  /// rather than silently swallowed as if it were a text-only post.
  bool get isStory => kind == 'story';

  /// A kind this build predates - audio and video are coming. The UI shows a
  /// "open it on the website" card instead of guessing, which keeps old installs
  /// working the day the server flips the flag rather than showing them a
  /// permanent spinner or a broken image.
  bool get isUnsupported => !knownKinds.contains(kind);

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
    commentCount: (j['comment_count'] as num?)?.toInt() ?? 0,
    // No `?? 0` here, on purpose. See [myVote].
    myVote: (j['my_vote'] as num?)?.toInt(),
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
    'comment_count': commentCount,
    // Omitted when unknown, so a round trip through the offline cache preserves
    // "unknown" rather than turning it into "not voted".
    if (myVote != null) 'my_vote': myVote,
  };
}

/// One anonymous comment. The server never returns an author - there are no
/// accounts, and the device id sent on create is not exposed to anyone.
class Comment {
  const Comment({
    required this.id,
    required this.postId,
    required this.body,
    required this.createdAt,
    this.upvotes = 0,
    this.downvotes = 0,
    this.myVote,
  });

  final int id;
  final int postId;
  final String body;
  final DateTime createdAt;

  /// Same "sej bo" / "sej ne bo" counts as a post, same semantics.
  final int upvotes;
  final int downvotes;

  /// Null means unknown, not unvoted - see [Post.myVote].
  final int? myVote;

  int get score => upvotes - downvotes;

  /// The server trims and rejects past this; the composer enforces it too so a
  /// long comment fails in the text field rather than after a round trip.
  static const maxLength = 1000;

  Comment copyWith({int? upvotes, int? downvotes, int? myVote}) => Comment(
    id: id,
    postId: postId,
    body: body,
    createdAt: createdAt,
    upvotes: upvotes ?? this.upvotes,
    downvotes: downvotes ?? this.downvotes,
    myVote: myVote ?? this.myVote,
  );

  factory Comment.fromJson(Map<String, dynamic> j) => Comment(
    id: (j['id'] as num).toInt(),
    postId: (j['post_id'] as num?)?.toInt() ?? 0,
    body: (j['body'] ?? '') as String,
    createdAt: DateTime.tryParse((j['created_at'] ?? '') as String)?.toLocal() ?? DateTime.now(),
    upvotes: (j['upvotes'] as num?)?.toInt() ?? 0,
    downvotes: (j['downvotes'] as num?)?.toInt() ?? 0,
    myVote: (j['my_vote'] as num?)?.toInt(),
  );
}

/// How a comment thread is ordered. `oldest` is the default and stays the
/// default - a thread is a conversation, and reordering it by score by default
/// would break the replies that answer each other.
enum CommentSort {
  oldest('oldest'),
  top('top');

  const CommentSort(this.wire);
  final String wire;

  /// The server echoes the sort it actually applied and falls back to `oldest`
  /// on anything it does not recognise, so the UI reads the echo rather than
  /// assuming its request was honoured.
  static CommentSort fromWire(String? wire) =>
      values.where((s) => s.wire == wire).firstOrNull ?? CommentSort.oldest;
}

/// A page of comments. Oldest first, which is reading order for a thread -
/// unlike posts, which are newest first.
class CommentPage {
  const CommentPage({
    required this.items,
    required this.page,
    required this.total,
    required this.hasNext,
    this.sort = CommentSort.oldest,
  });

  final List<Comment> items;
  final int page;
  final int total;
  final bool hasNext;

  /// What the server actually sorted by, not what was asked for.
  final CommentSort sort;

  /// The server clamps `per_page` here, so asking for more just wastes a header.
  static const maxPerPage = 100;

  factory CommentPage.fromJson(Map<String, dynamic> j) => CommentPage(
    items: ((j['items'] ?? const []) as List)
        .map((e) => Comment.fromJson(e as Map<String, dynamic>))
        .toList(),
    page: (j['page'] as num?)?.toInt() ?? 1,
    total: (j['total'] as num?)?.toInt() ?? 0,
    hasNext: j['has_next'] == true,
    sort: CommentSort.fromWire(j['sort'] as String?),
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

/// Moves vote counts as if the user changed their vote from [from] to [to],
/// without waiting on the server. Shared by posts and comments, which vote
/// identically - including that re-tapping the active direction passes 0.
///
/// Clamped at zero: an optimistic decrement must never render "-1 sej bo" if
/// the local idea of the previous vote has drifted from the server's.
({int up, int down}) applyVoteDelta(int up, int down, int from, int to) {
  var u = up, d = down;
  if (from == 1) u--;
  if (from == -1) d--;
  if (to == 1) u++;
  if (to == -1) d++;
  return (up: u.clamp(0, 1 << 30), down: d.clamp(0, 1 << 30));
}

/// Why a post is being flagged. The wire values are fixed by the server, which
/// 400s on anything else - so this enum is the single source of truth and the
/// UI must never send a free-text reason.
enum ReportReason {
  spam('spam'),
  inappropriate('inappropriate'),
  harassment('harassment'),
  copyright('copyright'),
  other('other');

  const ReportReason(this.wire);
  final String wire;
}

/// What a report is about. Both endpoints take the same reasons and neither
/// wants a device id, so only the path differs.
enum ReportTarget {
  post('posts'),
  comment('comments');

  const ReportTarget(this.path);
  final String path;
}

/// What the server says about app versions, plus its own version so the two
/// numbers can be shown side by side.
///
/// Every field is optional. A server that has not shipped this endpoint, or a
/// response that is missing pieces, must leave the app fully usable - see
/// [blocks].
class AppRelease {
  const AppRelease({this.minVersion, this.latestVersion, this.serverVersion, this.message});

  /// The oldest version still allowed to run. Below this the app blocks.
  final String? minVersion;

  /// The newest version available, for a non-blocking "update available" nudge.
  final String? latestVersion;

  /// The website/API's own version, shown next to the app's.
  final String? serverVersion;

  /// Optional line explaining *why* an update is required, shown on the gate.
  final String? message;

  /// Whether [current] is old enough to be locked out.
  ///
  /// Deliberately conservative: an absent or unparseable [minVersion] never
  /// blocks. A version gate that fails closed is far worse than one that fails
  /// open - a typo in an env var, or the Pi being down, would otherwise brick
  /// every install at once with no way to push a fix except through the store.
  bool blocks(String current) {
    final min = minVersion?.trim();
    if (min == null || min.isEmpty) return false;
    if (!RegExp(r'^\d').hasMatch(min)) return false;
    return compareVersions(current, min) < 0;
  }

  /// Whether a newer version exists, without it being mandatory.
  bool updateAvailable(String current) {
    final latest = latestVersion?.trim();
    if (latest == null || latest.isEmpty) return false;
    if (!RegExp(r'^\d').hasMatch(latest)) return false;
    return compareVersions(current, latest) < 0;
  }

  factory AppRelease.fromJson(Map<String, dynamic> j) => AppRelease(
    minVersion: j['min_version'] as String?,
    latestVersion: j['latest_version'] as String?,
    serverVersion: j['server_version'] as String?,
    message: j['message'] as String?,
  );
}

/// Public URLs the app links to but never calls as an API.
class Links {
  const Links._();

  static const privacy = 'https://sejbosejbo.fyi/privacy';
  static const terms = 'https://sejbosejbo.fyi/terms';
  static const website = 'https://sejbosejbo.fyi';

  /// Where the update button goes. The `market:` scheme opens the Play app
  /// directly; the https form is the fallback for anything without it,
  /// including a desktop browser.
  static const playStore = 'market://details?id=com.thekingziga.sejbosejbo';
  static const playStoreWeb =
      'https://play.google.com/store/apps/details?id=com.thekingziga.sejbosejbo';
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
