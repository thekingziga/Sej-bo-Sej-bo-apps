/// The marketplace's data, as docs/API_REQUEST_marketplace.md describes it.
///
/// Money is integer cents end to end. A price is one of three things, and the
/// difference matters to the person reading it: an amount, free (`0`), or open
/// to offers (`null`). They are never collapsed into each other.
library;

/// Formats and parses money exactly the way the website does, so the app can
/// never show a different price from the one on the site.
abstract final class Money {
  /// Highest price the server accepts: seven figures of euros.
  static const maxCents = 999999999;

  /// "25,00 €" in Slovenian, "€25.00" in English - the same output as the
  /// site's `Intl.NumberFormat("sl-SI" | "en-IE")`. The space before the euro
  /// sign is non-breaking so a narrow tile never strands it on its own line.
  static String format(int cents, String lang) {
    final whole = (cents ~/ 100).toString();
    final fraction = (cents % 100).toString().padLeft(2, '0');
    final sl = lang == 'sl';
    final grouped = _group(whole, sl ? '.' : ',');
    return sl ? '$grouped,$fraction €' : '€$grouped.$fraction';
  }

  static String _group(String digits, String sep) {
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(sep);
      out.write(digits[i]);
    }
    return out.toString();
  }

  /// Reads what a person typed: "12", "12.5", "12,50" (Slovenians write a
  /// comma), with or without spaces and a euro sign. Mirrors the server's
  /// `parsePrice` - anything it would reject is rejected here first, so the
  /// error appears under the field instead of after an upload.
  ///
  /// `ok: false` means unparseable. `ok: true, cents: null` means blank.
  static ({bool ok, int? cents}) parse(String raw) {
    final text = raw.trim().replaceAll(RegExp(r'\s'), '').replaceAll('€', '');
    if (text.isEmpty) return (ok: true, cents: null);
    final m = RegExp(r'^(\d{1,7})(?:[.,](\d{1,2}))?$').firstMatch(text);
    if (m == null) return (ok: false, cents: null);
    final cents = int.parse(m.group(1)!) * 100 + int.parse((m.group(2) ?? '0').padRight(2, '0'));
    if (cents > maxCents) return (ok: false, cents: null);
    return (ok: true, cents: cents);
  }

  /// What goes on the wire: the server runs it through the same `parsePrice`
  /// as its own form, so it gets plain text with a dot. Blank means "make an
  /// offer".
  static String toWire(int? cents) {
    if (cents == null) return '';
    return '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
  }
}

enum ListingStatus {
  active,
  sold;

  static ListingStatus fromWire(Object? v) => v == 'sold' ? sold : active;
}

enum ListingSort {
  newest('new'),
  priceAsc('price_asc'),
  priceDesc('price_desc');

  const ListingSort(this.wire);
  final String wire;

  /// Unknown values read as [newest], matching the server's own fallback.
  static ListingSort fromWire(Object? v) =>
      values.firstWhere((s) => s.wire == v, orElse: () => newest);
}

class Listing {
  const Listing({
    required this.id,
    required this.title,
    required this.description,
    required this.priceCents,
    required this.imageUrl,
    required this.status,
    required this.sellerName,
    required this.createdAt,
    this.expiresAt,
    this.isMine = false,
    this.myConversationId,
    this.hidden = false,
    this.held = false,
  });

  final int id;
  final String title;
  final String description;

  /// `null` is "make an offer", `0` is free. See [Money].
  final int? priceCents;
  final String? imageUrl;
  final ListingStatus status;
  final String sellerName;
  final DateTime createdAt;
  final DateTime? expiresAt;

  /// Only meaningful with a token; false otherwise.
  final bool isMine;

  /// The caller's own buyer thread on this listing, so "message seller" can
  /// reopen it rather than start a second one the server would refuse.
  final int? myConversationId;

  /// Not public (only ever true in the seller's own list). Its public page
  /// 404s, so it must not be opened. [held] narrows it: waiting for review.
  final bool hidden;
  final bool held;

  bool get isSold => status == ListingStatus.sold;

  factory Listing.fromJson(Map<String, dynamic> j) => Listing(
    id: (j['id'] as num).toInt(),
    title: j['title'] as String? ?? '',
    description: j['description'] as String? ?? '',
    priceCents: (j['price_cents'] as num?)?.toInt(),
    imageUrl: j['image_url'] as String?,
    status: ListingStatus.fromWire(j['status']),
    sellerName: (j['seller'] as Map?)?['name'] as String? ?? '',
    createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
    expiresAt: DateTime.tryParse(j['expires_at'] as String? ?? ''),
    isMine: j['is_mine'] == true,
    myConversationId: (j['my_conversation_id'] as num?)?.toInt(),
    hidden: j['hidden'] == true,
    held: j['held'] == true,
  );

  Listing copyWith({ListingStatus? status, int? myConversationId}) => Listing(
    id: id,
    title: title,
    description: description,
    priceCents: priceCents,
    imageUrl: imageUrl,
    status: status ?? this.status,
    sellerName: sellerName,
    createdAt: createdAt,
    expiresAt: expiresAt,
    isMine: isMine,
    myConversationId: myConversationId ?? this.myConversationId,
    hidden: hidden,
    held: held,
  );
}

class ListingPage {
  const ListingPage({
    required this.items,
    required this.page,
    required this.hasNext,
    required this.sort,
    required this.q,
  });

  final List<Listing> items;
  final int page;
  final bool hasNext;

  /// What the server says it **applied**, which can differ from what was
  /// asked for - the website had no search or sort at first. The screen shows
  /// the echo, so it never claims a filter that was not applied.
  final ListingSort sort;
  final String q;

  /// Listings cap at 50 per page on the server; asking for more just gets 50
  /// back and makes paging disagree.
  static const maxPerPage = 50;

  factory ListingPage.fromJson(Map<String, dynamic> j) => ListingPage(
    items: [
      for (final e in (j['items'] as List? ?? const []))
        Listing.fromJson((e as Map).cast<String, dynamic>()),
    ],
    page: (j['page'] as num?)?.toInt() ?? 1,
    hasNext: j['has_next'] == true,
    sort: ListingSort.fromWire(j['sort']),
    q: j['q'] as String? ?? '',
  );
}

/// The signed-in account. The only object that ever carries an email, and it
/// is the user's own.
class Me {
  const Me({
    required this.email,
    required this.name,
    required this.lang,
    required this.notify,
    required this.unreadCount,
  });

  final String email;

  /// Null until picked. Selling and messaging need one.
  final String? name;
  final String lang;

  /// Whether the site emails "you have a new message".
  final bool notify;
  final int unreadCount;

  bool get hasName => (name ?? '').isNotEmpty;

  factory Me.fromJson(Map<String, dynamic> j) => Me(
    email: j['email'] as String? ?? '',
    name: j['name'] as String?,
    lang: j['lang'] as String? ?? 'sl',
    notify: j['notify'] != false,
    unreadCount: (j['unread_count'] as num?)?.toInt() ?? 0,
  );

  Me copyWith({String? name, bool? notify, int? unreadCount}) => Me(
    email: email,
    name: name ?? this.name,
    lang: lang,
    notify: notify ?? this.notify,
    unreadCount: unreadCount ?? this.unreadCount,
  );

  /// Display names: 3-24 letters, digits and `._-`, starting and ending on a
  /// letter or digit - the website's `NAME_RE`. Checked here so the common
  /// mistake is caught before a round trip; the server stays the authority,
  /// and the only one that knows whether a name is taken.
  static final nameRule = RegExp(r'^[\p{L}\p{N}](?:[\p{L}\p{N}._-]{1,22})[\p{L}\p{N}]$', unicode: true);
}

enum OfferStatus {
  pending,
  accepted,
  declined,
  superseded;

  static OfferStatus? fromWire(Object? v) {
    for (final s in values) {
      if (s.name == v) return s;
    }
    return null;
  }
}

class MarketMessage {
  const MarketMessage({
    required this.id,
    required this.mine,
    required this.body,
    required this.offerCents,
    required this.offerStatus,
    required this.createdAt,
  });

  final int id;

  /// Computed by the server. Sender ids are never sent.
  final bool mine;
  final String body;
  final int? offerCents;
  final OfferStatus? offerStatus;
  final DateTime createdAt;

  bool get isOffer => offerCents != null;

  /// Only the side that did not make an offer may answer it, only while it is
  /// still the live one, and only while the listing is for sale - the same
  /// three conditions `respondToOffer` checks. The buttons appear exactly when
  /// the server would accept the click.
  bool canAnswer({required bool listingActive}) =>
      !mine && offerStatus == OfferStatus.pending && listingActive;

  factory MarketMessage.fromJson(Map<String, dynamic> j) => MarketMessage(
    id: (j['id'] as num).toInt(),
    mine: j['mine'] == true,
    body: j['body'] as String? ?? '',
    offerCents: (j['offer_cents'] as num?)?.toInt(),
    offerStatus: OfferStatus.fromWire(j['offer_status']),
    createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
  );
}

/// The slice of a listing a conversation carries.
class ListingSummary {
  const ListingSummary({
    required this.id,
    required this.title,
    required this.priceCents,
    required this.imageUrl,
    required this.status,
  });

  final int id;
  final String title;
  final int? priceCents;
  final String? imageUrl;
  final ListingStatus status;

  bool get isActive => status == ListingStatus.active;

  factory ListingSummary.fromJson(Map<String, dynamic> j) => ListingSummary(
    id: (j['id'] as num).toInt(),
    title: j['title'] as String? ?? '',
    priceCents: (j['price_cents'] as num?)?.toInt(),
    imageUrl: j['image_url'] as String?,
    status: ListingStatus.fromWire(j['status']),
  );

  factory ListingSummary.of(Listing l) => ListingSummary(
    id: l.id,
    title: l.title,
    priceCents: l.priceCents,
    imageUrl: l.imageUrl,
    status: l.status,
  );
}

enum ConversationRole { buyer, seller }

class Conversation {
  const Conversation({
    required this.id,
    required this.role,
    required this.otherName,
    required this.listing,
    required this.lastBody,
    required this.lastOfferCents,
    required this.lastMine,
    required this.unread,
    required this.lastMessageAt,
  });

  final int id;
  final ConversationRole role;
  final String otherName;
  final ListingSummary listing;
  final String lastBody;
  final int? lastOfferCents;
  final bool lastMine;
  final bool unread;
  final DateTime lastMessageAt;

  factory Conversation.fromJson(Map<String, dynamic> j) {
    final last = (j['last_message'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Conversation(
      id: (j['id'] as num).toInt(),
      role: j['role'] == 'seller' ? ConversationRole.seller : ConversationRole.buyer,
      otherName: (j['other'] as Map?)?['name'] as String? ?? '',
      listing: ListingSummary.fromJson((j['listing'] as Map).cast<String, dynamic>()),
      lastBody: last['body'] as String? ?? '',
      lastOfferCents: (last['offer_cents'] as num?)?.toInt(),
      lastMine: last['mine'] == true,
      unread: j['unread'] == true,
      lastMessageAt: DateTime.tryParse(j['last_message_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class BlockedUser {
  const BlockedUser({required this.userId, required this.name, required this.blockedAt});

  final int userId;
  final String name;
  final DateTime blockedAt;

  factory BlockedUser.fromJson(Map<String, dynamic> j) => BlockedUser(
    userId: (j['user_id'] as num).toInt(),
    name: j['name'] as String? ?? '',
    blockedAt: DateTime.tryParse(j['blocked_at'] as String? ?? '') ?? DateTime.now(),
  );
}

/// The five reasons the website takes for a listing or a conversation.
enum MarketReportReason { scam, prohibited, spam, harassment, other }
