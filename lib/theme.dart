import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Neo-brutalist design system, lifted from sejbosejbo.fyi and turned up.
///
/// The website's signature is thick black borders plus hard un-blurred offset
/// shadows on a warm paper background. Everything here keeps that DNA; the app
/// just gets a bigger accent palette (pulled from the cat logo) and motion.
class Brutal {
  const Brutal._();

  // Palette
  static const ink = Color(0xFF0D0D0D);
  static const paper = Color(0xFFFFFCF2);
  static const paperDeep = Color(0xFFF3EEDF);
  static const yellow = Color(0xFFFFE03D);
  static const pink = Color(0xFFFF63B8);
  static const cyan = Color(0xFF5FE3F0);
  static const orange = Color(0xFFFF7A2F); // straight off the logo
  static const lime = Color(0xFFC4F24A);
  static const danger = Color(0xFFFF5B5B);

  /// Accents in the order they cycle through lists.
  static const accents = <Color>[yellow, cyan, pink, lime, orange];

  static Color accentFor(int i) => accents[i % accents.length];

  static const border = 3.0;
  static const radius = Radius.zero;

  /// The un-blurred offset shadow that defines the whole look.
  static List<BoxShadow> shadow({double dx = 5, double dy = 5, Color? color}) => [
    BoxShadow(color: color ?? ink, offset: Offset(dx, dy), blurRadius: 0),
  ];

  static Border get outline => Border.all(color: ink, width: border);

  static ThemeData theme() {
    const family = 'ComicNeue';
    final base = ThemeData.light(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: paper,
      colorScheme: base.colorScheme.copyWith(primary: ink, secondary: pink, surface: paper),
      textTheme: base.textTheme.apply(fontFamily: family, bodyColor: ink, displayColor: ink),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: family),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
    );
  }

  // Type scale. Everything is ComicNeue via the theme's fontFamily.
  static const display = TextStyle(fontWeight: FontWeight.w700, height: 0.95, letterSpacing: -1);
  static const heading = TextStyle(fontWeight: FontWeight.w700, height: 1.05);
  static const label = TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1.2, height: 1.1);
  static const body = TextStyle(fontWeight: FontWeight.w400, height: 1.45);
}

/// A bordered, hard-shadowed panel. The building block for nearly every surface.
class BrutalBox extends StatelessWidget {
  const BrutalBox({
    super.key,
    required this.child,
    this.color = Brutal.paper,
    this.padding = const EdgeInsets.all(14),
    this.dx = 5,
    this.dy = 5,
    this.rotation = 0,
    this.dashed = false,
  });

  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;
  final double dx;
  final double dy;

  /// Radians. Small values (±0.02) give the deliberately messy scrapbook feel.
  final double rotation;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        border: Brutal.outline,
        boxShadow: Brutal.shadow(dx: dx, dy: dy),
      ),
      child: child,
    );
    final wrapped = dashed
        ? CustomPaint(
            painter: _DashedBorderPainter(),
            child: Container(padding: padding, child: child),
          )
        : box;
    return rotation == 0 ? wrapped : Transform.rotate(angle: rotation, child: wrapped);
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Brutal.ink
      ..strokeWidth = Brutal.border
      ..style = PaintingStyle.stroke;
    const dash = 10.0, gap = 7.0;
    final path = Path()..addRect(Offset.zero & size);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, (d + dash).clamp(0, metric.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Press-to-squash button. The shadow collapses under the finger, exactly like
/// the website's `button:hover { transform: translate(1px,1px) }` but tactile.
class BrutalButton extends StatefulWidget {
  const BrutalButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.color = Brutal.cyan,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    this.expand = false,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final Color color;
  final EdgeInsetsGeometry padding;
  final bool expand;

  @override
  State<BrutalButton> createState() => _BrutalButtonState();
}

class _BrutalButtonState extends State<BrutalButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final offset = _down ? 2.0 : 5.0;

    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: enabled
            ? () {
                HapticFeedback.lightImpact();
                widget.onPressed!();
              }
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 70),
          transform: Matrix4.translationValues(5 - offset, 5 - offset, 0),
          width: widget.expand ? double.infinity : null,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: enabled ? widget.color : Brutal.paperDeep,
            border: Brutal.outline,
            boxShadow: Brutal.shadow(dx: offset, dy: offset),
          ),
          child: DefaultTextStyle.merge(
            style: Brutal.label.copyWith(fontSize: 16, color: Brutal.ink),
            textAlign: TextAlign.center,
            child: Center(widthFactor: widget.expand ? null : 1, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// Uppercase section header with the chunky underline rule.
class SectionHead extends StatelessWidget {
  const SectionHead({super.key, required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: Text(title.toUpperCase(), style: Brutal.label.copyWith(fontSize: 20))),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Brutal.yellow, border: Brutal.outline),
                child: Text(action!.toUpperCase(), style: Brutal.label.copyWith(fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small filled tag, e.g. FEATURED / PINNED / STORY.
class BrutalTag extends StatelessWidget {
  const BrutalTag(this.text, {super.key, this.color = Brutal.yellow});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: Brutal.ink, width: 2),
      ),
      child: Text(text.toUpperCase(), style: Brutal.label.copyWith(fontSize: 11)),
    );
  }
}

/// Fades + slides a child in, staggered by [index].
///
/// Only use this for content that is on screen at first paint. A ListView builds
/// its children lazily even when they are passed as an explicit list, so an
/// Entrance placed below the fold would replay its fade every time the user
/// scrolls back to it - and would sit at opacity 0 if the ticker were ever
/// stalled. Pass `enabled: false` for anything further down; it then renders
/// fully opaque with no animation and no controller work.
class Entrance extends StatefulWidget {
  const Entrance({super.key, required this.child, this.index = 0, this.enabled = true});

  final Widget child;
  final int index;
  final bool enabled;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 400 + 70 * widget.index),
  );

  late final Animation<double> _a = CurvedAnimation(
    parent: _c,
    // The stagger lives in the curve rather than a pending Future, so there is
    // never a timer that can outlive the widget or fire before the first frame.
    curve: Interval((0.07 * widget.index).clamp(0.0, 0.55), 1, curve: Curves.easeOutCubic),
  );

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _c.forward();
    } else {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return FadeTransition(
      opacity: _a,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(_a),
        child: widget.child,
      ),
    );
  }
}
