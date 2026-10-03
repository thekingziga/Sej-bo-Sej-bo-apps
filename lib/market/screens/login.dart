import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../models.dart';
import '../session.dart';
import '../widgets.dart';

/// Gets someone to the point where they can sell and message: signed in, and
/// with a display name. Returns true when they are there, false if they backed
/// out. Already there: returns true at once, without showing anything.
Future<bool> ensureMarketReady(BuildContext context, MarketSession session) async {
  if (session.ready) return true;
  final t = L10n.of(context);
  if (session.signedIn && session.me == null) {
    // Signed in from a previous run, but the account was not reachable at
    // start. Read it now; if that fails too, say so rather than asking for a
    // login the person does not need.
    try {
      await session.ensureMe(lang: t.code);
      if (session.ready) return true;
    } catch (e) {
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(marketError(t, e))));
      if (session.signedIn) return false;
    }
  }
  if (!context.mounted) return false;
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => MarketLoginScreen(session: session)),
  );
  return ok == true && session.ready;
}

enum _Step { email, code, name }

/// Email, then the emailed code, then - first time only - a display name.
///
/// A code rather than the website's link: the link opens in a browser and
/// signs that browser in, and the app cannot claim login links without
/// breaking login on the website. See docs/API_REQUEST_marketplace.md.
class MarketLoginScreen extends StatefulWidget {
  const MarketLoginScreen({super.key, required this.session, this.nameOnly = false});

  final MarketSession session;

  /// Straight to the name step - for changing a name that already exists.
  final bool nameOnly;

  @override
  State<MarketLoginScreen> createState() => _MarketLoginScreenState();
}

class _MarketLoginScreenState extends State<MarketLoginScreen> {
  late _Step _step = widget.nameOnly ? _Step.name : _Step.email;
  final _email = TextEditingController();
  final _code = TextEditingController();
  late final _name = TextEditingController(text: widget.session.me?.name ?? '');
  bool _busy = false;
  String? _error;
  String? _fieldError;

  static final _emailShape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = marketError(L10n.of(context), e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() async {
    final t = L10n.of(context);
    if (!_emailShape.hasMatch(_email.text.trim())) {
      setState(() => _fieldError = t['loginEmailInvalid']);
      return;
    }
    setState(() => _fieldError = null);
    await _run(() async {
      await widget.session.requestCode(_email.text, lang: t.code);
      if (mounted) setState(() => _step = _Step.code);
    });
  }

  Future<void> _verify() async {
    final t = L10n.of(context);
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) {
      setState(() => _fieldError = t['loginCodeInvalid']);
      return;
    }
    setState(() => _fieldError = null);
    await _run(() async {
      await widget.session.verifyCode(_email.text, _code.text, lang: t.code);
      if (!mounted) return;
      if (widget.session.ready) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _step = _Step.name);
      }
    });
  }

  Future<void> _saveName() async {
    final t = L10n.of(context);
    if (!Me.nameRule.hasMatch(_name.text.trim())) {
      setState(() => _fieldError = t['nameInvalid']);
      return;
    }
    setState(() => _fieldError = null);
    await _run(() async {
      await widget.session.setName(_name.text, lang: t.code);
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final (title, body, field, button, onGo) = switch (_step) {
      _Step.email => (
        t['loginTitle'],
        t['loginWhy'],
        BrutalField(
          label: t['loginEmail'],
          hint: t['loginEmailHint'],
          controller: _email,
          maxLength: 254,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.send,
          autofillHints: const [AutofillHints.email],
          autofocus: true,
          errorText: _fieldError,
          onSubmitted: (_) => _sendCode(),
        ),
        t['loginSend'],
        _sendCode,
      ),
      _Step.code => (
        t['loginTitle'],
        t['loginSent'].replaceAll('{email}', _email.text.trim()),
        BrutalField(
          label: t['loginCode'],
          hint: '000000',
          controller: _code,
          maxLength: 6,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofillHints: const [AutofillHints.oneTimeCode],
          autofocus: true,
          errorText: _fieldError,
          onSubmitted: (_) => _verify(),
        ),
        t['loginVerify'],
        _verify,
      ),
      _Step.name => (
        t['nameTitle'],
        t['nameWhy'],
        BrutalField(
          label: t['nameField'],
          hint: 'sejbomojster',
          controller: _name,
          maxLength: 24,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.nickname],
          autofocus: true,
          errorText: _fieldError,
          onSubmitted: (_) => _saveName(),
        ),
        t['nameSave'],
        _saveName,
      ),
    };

    return Scaffold(
      backgroundColor: Brutal.paper,
      body: SafeArea(
        child: Column(
          children: [
            MarketTopBar(title: title),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Text(title, style: Brutal.display.copyWith(fontSize: 38)),
                  const SizedBox(height: 10),
                  Text(body, style: Brutal.body.copyWith(fontSize: 16)),
                  const SizedBox(height: 22),
                  field,
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    BrutalBox(
                      color: Brutal.danger,
                      padding: const EdgeInsets.all(12),
                      child: Text(_error!, style: Brutal.body.copyWith(fontSize: 15)),
                    ),
                  ],
                  const SizedBox(height: 20),
                  BrutalButton(
                    color: Brutal.yellow,
                    onPressed: _busy ? null : onGo,
                    child: Center(
                      child: _busy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3))
                          : Text(button, style: Brutal.label.copyWith(fontSize: 15)),
                    ),
                  ),
                  if (_step == _Step.code) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 18,
                      runSpacing: 8,
                      children: [
                        _Link(text: t['loginResend'], onTap: _busy ? null : _sendCode),
                        _Link(
                          text: t['loginOtherEmail'],
                          onTap: _busy
                              ? null
                              : () => setState(() {
                                  _step = _Step.email;
                                  _code.clear();
                                  _error = null;
                                  _fieldError = null;
                                }),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.text, required this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Text(
      text,
      style: Brutal.body.copyWith(fontSize: 15, decoration: TextDecoration.underline),
    ),
  );
}
