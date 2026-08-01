import 'package:flutter/material.dart';

import 'api.dart';
import 'donations.dart';
import 'screens/donate.dart';
import 'screens/gallery.dart';
import 'screens/home.dart';
import 'screens/upload.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SejbosejboApp());
}

class SejbosejboApp extends StatefulWidget {
  const SejbosejboApp({super.key});

  @override
  State<SejbosejboApp> createState() => _SejbosejboAppState();
}

class _SejbosejboAppState extends State<SejbosejboApp> {
  // Pass --dart-define=API_BASE_URL=https://sejbosejbo.fyi to leave demo mode.
  final Api _api = Api();
  late final DonationGateway _donations = DonationGateway(_api);

  @override
  void initState() {
    super.initState();
    _donations.init();
  }

  @override
  void dispose() {
    _donations.dispose();
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sejbosejbo',
      debugShowCheckedModeBanner: false,
      theme: Brutal.theme(),
      home: Shell(api: _api, donations: _donations),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key, required this.api, required this.donations});

  final Api api;
  final DonationGateway donations;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  // Lets a screenshot/dev run open straight onto a given tab:
  //   flutter run --dart-define=START_TAB=2
  // Defaults to 0, so release builds are unaffected.
  int _index = const int.fromEnvironment('START_TAB').clamp(0, 3);
  final _navKeys = List.generate(4, (_) => GlobalKey<NavigatorState>());

  static const _tabs = [
    _TabSpec('HOME', Icons.bolt, Brutal.yellow),
    _TabSpec('GALLERY', Icons.grid_view_rounded, Brutal.cyan),
    _TabSpec('UPLOAD', Icons.add_a_photo_outlined, Brutal.pink),
    _TabSpec('SUPPORT', Icons.favorite, Brutal.orange),
  ];

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
        return HomeScreen(api: widget.api, onSeeAll: () => _go(1), onUpload: () => _go(2));
      case 1:
        return GalleryScreen(api: widget.api);
      case 2:
        return UploadScreen(api: widget.api);
      default:
        return DonateScreen(api: widget.api, donations: widget.donations);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brutal.paper,
      body: IndexedStack(
        index: _index,
        children: List.generate(
          _tabs.length,
          (i) => Navigator(
            key: _navKeys[i],
            onGenerateRoute: (s) => MaterialPageRoute(builder: (_) => _screenFor(i)),
          ),
        ),
      ),
      bottomNavigationBar: _BrutalNavBar(tabs: _tabs, index: _index, onTap: _go),
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
              style: Brutal.label.copyWith(fontSize: 10, color: Brutal.ink, letterSpacing: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}
