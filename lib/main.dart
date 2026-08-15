import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'donations.dart';
import 'l10n.dart';
import 'prefs.dart';
import 'screens/detail.dart';
import 'screens/donate.dart';
import 'screens/gallery.dart';
import 'screens/home.dart';
import 'screens/upload.dart';
import 'theme.dart';
import 'update_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await Prefs.load();
  runApp(SejbosejboApp(prefs: prefs));
}

class SejbosejboApp extends StatefulWidget {
  const SejbosejboApp({super.key, required this.prefs});

  final Prefs prefs;

  @override
  State<SejbosejboApp> createState() => _SejbosejboAppState();
}

class _SejbosejboAppState extends State<SejbosejboApp> {
  // Pass --dart-define=API_BASE_URL=https://sejbosejbo.fyi to leave demo mode.
  late final Api _api = Api(prefs: widget.prefs);
  late final DonationGateway _donations = DonationGateway(_api);
  late Lang _lang = widget.prefs.lang;

  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _donations.init();
    _initDeepLinks();
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

    _navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => PostDetailScreen.byId(api: _api, prefs: widget.prefs, id: id)),
    );
  }

  Future<void> _setLang(Lang l) async {
    if (l == _lang) return;
    setState(() => _lang = l);
    await widget.prefs.setLang(l);
  }

  @override
  void dispose() {
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
          child: Shell(api: _api, donations: _donations, prefs: widget.prefs),
        ),
      ),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key, required this.api, required this.donations, required this.prefs});

  final Api api;
  final DonationGateway donations;
  final Prefs prefs;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  // Lets a screenshot/dev run open straight onto a given tab:
  //   flutter run --dart-define=START_TAB=2
  // Defaults to 0, so release builds are unaffected.
  int _index = const int.fromEnvironment('START_TAB').clamp(0, 3);
  final _navKeys = List.generate(4, (_) => GlobalKey<NavigatorState>());

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
        );
      case 1:
        return GalleryScreen(api: widget.api, prefs: widget.prefs);
      case 2:
        return UploadScreen(api: widget.api);
      default:
        return DonateScreen(api: widget.api, donations: widget.donations);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final tabs = [
      _TabSpec(t['tabHome'], Icons.bolt, Brutal.yellow),
      _TabSpec(t['tabGallery'], Icons.grid_view_rounded, Brutal.cyan),
      _TabSpec(t['tabUpload'], Icons.add_a_photo_outlined, Brutal.pink),
      _TabSpec(t['tabSupport'], Icons.favorite, Brutal.orange),
    ];

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
            index: _index,
            children: List.generate(
              tabs.length,
              (i) => Navigator(
                key: _navKeys[i],
                onGenerateRoute: (s) => MaterialPageRoute(builder: (_) => _screenFor(i)),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: _BrutalNavBar(tabs: tabs, index: _index, onTap: _go),
    );
  }
}

class _TabSpec {
  const _TabSpec(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
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
            Icon(spec.icon, size: 21, color: Brutal.ink),
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
