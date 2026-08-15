import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'l10n.dart';
import 'models.dart';
import 'theme.dart';
import 'version.dart';

/// Blocks the app when the server says this build is too old to run.
///
/// The gate is **server-driven**, not driven by "is there a newer build in the
/// store". That distinction matters: Play rolls updates out gradually, so for
/// hours after an upload there are users who cannot get the new version yet.
/// Blocking on "newer exists" would lock those people out of an app they have
/// no way to fix. Blocking on an explicit `min_version` that you raise when you
/// mean it does what you actually want, and only when you want it.
///
/// It also fails open on every error - see [Api.release].
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.api, required this.child});

  final Api api;
  final Widget child;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  AppRelease? _release;
  AppVersion? _mine;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final mine = await AppVersion.load();
    final release = await widget.api.release();
    if (!mounted) return;
    setState(() {
      _mine = mine;
      _release = release;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mine = _mine;
    final release = _release;

    // Until both are known, and whenever the server says nothing, the app runs
    // exactly as before. No spinner, no gate, no delay on launch.
    if (mine == null || release == null || !release.blocks(mine.version)) {
      return widget.child;
    }
    return UpdateRequiredScreen(release: release, current: mine);
  }
}

/// The wall. Deliberately a dead end - no back, no dismiss - because a gate the
/// user can tap past is not a gate.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key, required this.release, required this.current});

  final AppRelease release;
  final AppVersion current;

  static Future<void> openStore() async {
    // market: opens the Play app directly. It fails on a device without Play
    // (and on desktop), so fall back to the browser rather than doing nothing.
    final direct = Uri.parse(Links.playStore);
    try {
      if (await launchUrl(direct, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    await launchUrl(Uri.parse(Links.playStoreWeb), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);

    return Scaffold(
      backgroundColor: Brutal.paper,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset(
                  'assets/img/logo.png',
                  height: 92,
                  errorBuilder: (_, _, _) => const SizedBox(height: 92),
                ),
                const SizedBox(height: 22),
                Transform.rotate(
                  angle: -0.02,
                  child: BrutalBox(
                    color: Brutal.yellow,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          t['updateTitle'],
                          textAlign: TextAlign.center,
                          style: Brutal.display.copyWith(fontSize: 30),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          // The server can explain why; otherwise a generic line.
                          release.message?.trim().isNotEmpty == true
                              ? release.message!.trim()
                              : t['updateBody'],
                          textAlign: TextAlign.center,
                          style: Brutal.body.copyWith(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                BrutalButton(
                  color: Brutal.lime,
                  onPressed: openStore,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(t['updateButton']),
                ),
                const SizedBox(height: 18),
                Text(
                  '${current.display}  ->  v${release.minVersion}+',
                  textAlign: TextAlign.center,
                  style: Brutal.body.copyWith(
                    fontSize: 13,
                    color: Brutal.ink.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small "v1.8.0 (10)" line for the bottom of a screen. Shows the website's
/// version too once the server reports one, so a bug report can name both
/// halves without the user hunting for either.
class VersionFooter extends StatefulWidget {
  const VersionFooter({super.key, this.api});

  final Api? api;

  @override
  State<VersionFooter> createState() => _VersionFooterState();
}

class _VersionFooterState extends State<VersionFooter> {
  AppVersion? _mine;
  String? _server;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final mine = await AppVersion.load();
    if (mounted) setState(() => _mine = mine);
    final release = await widget.api?.release();
    if (mounted && release?.serverVersion != null) {
      setState(() => _server = release!.serverVersion);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = _mine;
    if (mine == null) return const SizedBox(height: 18);

    final t = L10n.of(context);
    final style = Brutal.body.copyWith(fontSize: 12, color: Brutal.ink.withValues(alpha: 0.55));

    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 4),
      child: Column(
        children: [
          Text('${t['versionApp']} ${mine.display}', textAlign: TextAlign.center, style: style),
          if (_server != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${t['versionSite']} v$_server',
                textAlign: TextAlign.center,
                style: style,
              ),
            ),
        ],
      ),
    );
  }
}
