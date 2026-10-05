import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'donations.dart';
import 'l10n.dart';
import 'market/screens/market.dart';
import 'market/session.dart';
import 'market/widgets.dart' show UnreadBadge;
import 'music.dart';
import 'prefs.dart';
import 'push.dart';
import 'screens/detail.dart';
import 'screens/donate.dart';
import 'screens/gallery.dart';
import 'screens/home.dart';
import 'screens/upload.dart';
import 'theme.dart';
import 'update_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Android 15 and up draw behind the system bars whether an app asks or not;
  // Android 14 and down only do it if asked, and Play's "may not display
  // edge-to-edge for all users" advice is about the gap. Asking closes it for
  // the status bar - paper behind it instead of a grey scrim - and nothing
  // moves on 15+, where every screen already insets with SafeArea.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(Brutal.overlayStyle);
  final prefs = await Prefs.load();
  runApp(SejbosejboApp(prefs: prefs));
}

class SejbosejboApp extends StatefulWidget {
  const SejbosejboApp({super.key, required this.prefs});

  final Prefs prefs;

  @override
  State<SejbosejboApp> createState() => _SejbosejboAppState();
}

class _SejbosejboAppState extends State<SejbosejboApp> with WidgetsBindingObserver {
  // Pass --dart-define=API_BASE_URL=https://sejbosejbo.fyi to leave demo mode.
  late final Api _api = Api(prefs: widget.prefs);
  late final DonationGateway _donations = DonationGateway(_api);
  late Lang _lang = widget.prefs.lang;

  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<Uri>? _linkSub;

  late final Push _push = Push(
    api: _api,
    prefs: widget.prefs,
    // A tapped notification lands on the same screen a deep link does.
    onOpenPost: _openPost,
  );

  Push get push => _push;

  late final Music _music = Music(widget.prefs);
  Music get music => _music;

  /// Who is signed in to the marketplace. Lives as long as the app, like the
  /// rest of these, so the unread badge on the tab survives switching tabs.
  late final MarketSession _market = MarketSession(api: _api);

  @override
  void initState() {
    super.initState();
    _donations.init();
    _initDeepLinks();
    _ensureSignedDeviceId();
    _push.start();
    // Only actually plays if the user turned it on in a previous session.
    WidgetsBinding.instance.addObserver(this);
    _music.start();
    _market.restore(lang: Strings.of(_lang).code);
  }

  /// Swaps the locally generated device id for one the server signs, exactly
  /// once per install.
  ///
  /// Minting is limited to 10 per IP per hour and a fresh id reads as a fresh
  /// person, so this must never run on every launch - hence the check for an
  /// id we already hold. Any failure is silent: the server still accepts
  /// unsigned ids, and a device id is not worth blocking a launch over.
  Future<void> _ensureSignedDeviceId() async {
    if (widget.prefs.hasSignedDeviceId) return;
    final id = await _api.mintDeviceId();
    if (id != null) await widget.prefs.setDeviceId(id);
  }

  /// Handles `sejbosejbo.fyi/post/<id>` both on cold start and while running.
  Future<void> _initDeepLinks() async {
    try {
      final links = AppLinks();
      _linkSub = links.uriLinkStream.listen(_openLink, onError: (_) {});
      final initial = await links.getInitialLink();
      if (initial != null) _openLink(initial);
    } catch (_) {
      // Deep links are a nicety; never let them stop the app from starting.
    }
  }

  void _openLink(Uri uri) {
    final segments = uri.pathSegments;
    final i = segments.indexOf('post');
    if (i == -1 || i + 1 >= segments.length) return;
    final id = int.tryParse(segments[i + 1]);
    if (id == null) return;
    _openPost(id);
  }

  /// Shared by deep links and notification taps: both must land on the post
  /// itself, not the home screen.
  void _openPost(int id) {
    _navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) =>
          PostDetailScreen.byId(api: _api, prefs: widget.prefs, id: id, music: _music)),
    );
  }

  Future<void> _setLang(Lang l) async {
    if (l == _lang) return;
    setState(() => _lang = l);
    await widget.prefs.setLang(l);
  }

  /// Music stops when the app goes to the background and picks up on return.
  /// Anything else amounts to holding the phone's audio hostage after the user
  /// has walked away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _music.handleLifecycle(foreground: state == AppLifecycleState.resumed);
    // Messages arrive by email while the app is closed; coming back is when
    // the badge should catch up with them.
    if (state == AppLifecycleState.resumed) {
      final lang = Strings.of(_lang).code;
      _market.refresh(lang: lang);
      if (_market.available != true) _market.probe(lang: lang);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _music.dispose();
    _market.dispose();
    _linkSub?.cancel();
    _donations.dispose();
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return L10n(
      strings: Strings.of(_lang),
      onChange: _setLang,
      child: MaterialApp(
        title: 'Sejbosejbo',
        debugShowCheckedModeBanner: false,
        theme: Brutal.theme(),
        navigatorKey: _navigatorKey,
        // Wrapped, not routed to: the gate must be impossible to navigate
        // around, and this way it also covers a deep link that opens straight
        // onto a post.
        home: UpdateGate(
          api: _api,
          child: Shell(
            api: _api,
            donations: _donations,
            prefs: widget.prefs,
            push: _push,
            music: _music,
            market: _market,
          ),
        ),
      ),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({
    super.key,
    required this.api,
    required this.donations,
    required this.prefs,
    this.push,
    this.music,
    this.market,
  });

  final Api api;
  final DonationGateway donations;
  final Prefs prefs;

  /// Absent in tests and in demo mode, where there is no Firebase to talk to.
  final Push? push;

  /// Absent in tests, where there is no audio device.
  final Music? music;

  /// Absent in tests, which get a signed-out session with no keystore behind
  /// it rather than no marketplace tab.
  final MarketSession? market;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  // Lets a screenshot/dev run open straight onto a given tab:
  //   flutter run --dart-define=START_TAB=2
  // Defaults to 0, so release builds are unaffected.
  int _index = const int.fromEnvironment('START_TAB').clamp(0, 4);
  final _navKeys = List.generate(5, (_) => GlobalKey<NavigatorState>());

  late final MarketSession _market =
      widget.market ?? MarketSession(api: widget.api, store: MemoryTokenStore());

  /// The marketplace's tab position. Its navigator always exists, so indices
  /// never shift; only the bar hides it until the server says it is there.
  static const _marketTab = 3;
  bool? _marketKnown;

  bool get _marketShown => _market.available == true;

  @override
  void initState() {
    super.initState();
    _market.addListener(_onMarket);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _market.available == null) _market.probe(lang: L10n.of(context).code);
    });
  }

  @override
  void dispose() {
    _market.removeListener(_onMarket);
    if (widget.market == null) _market.dispose();
    super.dispose();
  }

  /// Rebuilds when the marketplace appears or disappears - not on every
  /// unread-count change, which only the nav bar needs to hear about.
  void _onMarket() {
    if (_market.available == _marketKnown) return;
    _marketKnown = _market.available;
    setState(() {
      if (!_marketShown && _index == _marketTab) _index = 0;
    });
  }

  void _go(int i) {
    if (i == _index) {
      // Tapping the active tab pops it back to root, like every native app.
      _navKeys[i].currentState?.popUntil((r) => r.isFirst);
      return;
    }
    setState(() => _index = i);
  }

  Widget _screenFor(int i) {
    switch (i) {
      case 0:
        return HomeScreen(
          api: widget.api,
          prefs: widget.prefs,
          onSeeAll: () => _go(1),
          onUpload: () => _go(2),
          music: widget.music,
        );
      case 1:
        return GalleryScreen(api: widget.api, prefs: widget.prefs, music: widget.music);
      case 2:
        return UploadScreen(api: widget.api, onHeld: () => _go(1));
      case 3:
        return MarketScreen(api: widget.api, session: _market);
      default:
        return DonateScreen(
          api: widget.api,
          donations: widget.donations,
          prefs: widget.prefs,
          push: widget.push,
          music: widget.music,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    List<_TabSpec> tabsWith({int unread = 0}) => [
      _TabSpec(t['tabHome'], Icons.bolt, Brutal.yellow),
      _TabSpec(t['tabGallery'], Icons.grid_view_rounded, Brutal.cyan),
      _TabSpec(t['tabUpload'], Icons.add_a_photo_outlined, Brutal.pink),
      _TabSpec(t['tabMarket'], Icons.storefront_outlined, Brutal.lime, badge: unread),
      _TabSpec(t['tabSupport'], Icons.favorite, Brutal.orange),
    ];
    final tabs = tabsWith();
    // A dev run started on the marketplace tab before the server has answered.
    final shown = !_marketShown && _index == _marketTab ? 0 : _index;

    return Scaffold(
      backgroundColor: Brutal.paper,
      // Cap the content width on desktop. The layout is designed around a phone;
      // stretched across a maximised Windows or macOS window the hero image grows
      // to fill the screen and the forms become unreadably wide lines. The nav
      // bar stays full width so the window still feels like a desktop app.
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: IndexedStack(
            index: shown,
            children: List.generate(
              tabs.length,
              // Android's back button goes to the root navigator, which only
              // holds this shell - so without this, back from a post or a
              // listing closed the whole app instead of going back one screen.
              // Each tab handles its own: the handler calls back even when
              // disabled, so the check on _index is what keeps one press from
              // popping every tab's stack at once.
              (i) => NavigatorPopHandler<Object?>(
                enabled: i == _index,
                onPopWithResult: (_) {
                  if (i == _index) _navKeys[i].currentState?.maybePop();
                },
                child: Navigator(
                  key: _navKeys[i],
                  onGenerateRoute: (s) => MaterialPageRoute(builder: (_) => _screenFor(i)),
                ),
              ),
            ),
          ),
        ),
      ),
      // Only the bar listens to the session: a new unread count repaints the
      // badge, not every tab's navigator above it.
      bottomNavigationBar: ListenableBuilder(
        listenable: _market,
        builder: (context, _) {
          final all = tabsWith(unread: _market.unreadCount);
          final visible = [
            for (var i = 0; i < all.length; i++)
              if (i != _marketTab || _marketShown) i,
          ];
          return _BrutalNavBar(
            tabs: [for (final i in visible) all[i]],
            index: visible.indexOf(shown),
            onTap: (pos) => _go(visible[pos]),
          );
        },
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec(this.label, this.icon, this.color, {this.badge = 0});
  final String label;
  final IconData icon;
  final Color color;

  /// Unread marketplace messages - the only tab that has anything to count.
  final int badge;
}

/// Custom nav bar - Material's BottomNavigationBar cannot do the hard-shadow,
/// thick-border look without fighting it the whole way.
class _BrutalNavBar extends StatelessWidget {
  const _BrutalNavBar({required this.tabs, required this.index, required this.onTap});

  final List<_TabSpec> tabs;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Brutal.paper,
        border: Border(top: BorderSide(color: Brutal.ink, width: 4)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: _NavItem(spec: tabs[i], active: i == index, onTap: () => onTap(i)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.spec, required this.active, required this.onTap});

  final _TabSpec spec;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 7),
        transform: Matrix4.translationValues(0, active ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: active ? spec.color : Brutal.paper,
          border: Border.all(color: active ? Brutal.ink : Colors.transparent, width: 3),
          boxShadow: active ? Brutal.shadow(dx: 3, dy: 3) : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(spec.icon, size: 21, color: Brutal.ink),
                if (spec.badge > 0)
                  Positioned(right: -14, top: -8, child: UnreadBadge(count: spec.badge)),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              spec.label,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: Brutal.label.copyWith(fontSize: 10, color: Brutal.ink, letterSpacing: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}
