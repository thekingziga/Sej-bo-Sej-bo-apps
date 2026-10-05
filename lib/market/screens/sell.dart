import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../api.dart';
import '../../l10n.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../models.dart';
import '../session.dart';
import '../widgets.dart';

enum _PriceMode { amount, offer, free }

/// Publishes a listing. Pops with the new [Listing], or null.
///
/// The website's form spells the price out in its label - "leave empty for
/// make an offer, 0 for free". That works on a page and is invisible on a
/// phone, so here the three are three buttons; what is sent is identical.
class SellScreen extends StatefulWidget {
  const SellScreen({super.key, required this.api, required this.session});

  final Api api;
  final MarketSession session;

  @override
  State<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends State<SellScreen> {
  final _picker = ImagePicker();
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController();

  XFile? _photo;
  Uint8List? _preview;
  _PriceMode _mode = _PriceMode.amount;
  bool _sending = false;
  double? _progress;
  String? _error;
  String? _priceError;
  bool _tried = false;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _price.dispose();
    super.dispose();
  }

  bool get _canCamera => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _pick(ImageSource source) async {
    try {
      // Phone photos are 12 megapixels and up; a listing tile never needs that.
      final f = await _picker.pickImage(source: source, maxWidth: 2048, imageQuality: 85);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      if (mounted) {
        setState(() {
          _photo = f;
          _preview = bytes;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = L10n.of(context)['sellPhotoRequired']);
    }
  }

  int? _priceCents() {
    switch (_mode) {
      case _PriceMode.offer:
        return null;
      case _PriceMode.free:
        return 0;
      case _PriceMode.amount:
        final p = Money.parse(_price.text);
        return p.ok ? p.cents : null;
    }
  }

  Future<void> _publish() async {
    final t = L10n.of(context);
    setState(() {
      _tried = true;
      _error = null;
      _priceError = null;
    });
    if (_photo == null || _title.text.trim().isEmpty) return;
    if (_mode == _PriceMode.amount) {
      final p = Money.parse(_price.text);
      if (!p.ok || p.cents == null) {
        setState(() => _priceError = t['sellPriceInvalid']);
        return;
      }
    }

    setState(() {
      _sending = true;
      _progress = 0;
    });
    try {
      final photo = _photo!;
      final result = await widget.session.authed((tk) => widget.api.createListing(
            token: tk,
            title: _title.text,
            description: _desc.text,
            priceCents: _priceCents(),
            photoPath: kIsWeb ? null : photo.path,
            photoBytes: kIsWeb ? _preview : null,
            photoName: photo.name,
            lang: t.code,
            onProgress: (sent, total) {
              if (mounted && total > 0) setState(() => _progress = sent / total);
            },
          ));
      if (!mounted) return;
      switch (result) {
        case Published(value: final listing):
          Navigator.of(context).pop(listing);
        case Held(:final message):
          // Saved, but hidden until reviewed - its public page would 404, so
          // there is nothing to open. It shows in the account's own listings.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), duration: const Duration(seconds: 8)),
          );
          Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) setState(() => _error = marketError(t, e));
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final missingPhoto = _tried && _photo == null;
    final missingTitle = _tried && _title.text.trim().isEmpty;

    return Scaffold(
      backgroundColor: Brutal.paper,
      body: SafeArea(
        child: Column(
          children: [
            MarketTopBar(title: t['sellTitle']),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                children: [
                  Text(t['sellTitle'], style: Brutal.display.copyWith(fontSize: 36)),
                  const SizedBox(height: 8),
                  Text(t['sellSub'], style: Brutal.body.copyWith(fontSize: 15)),
                  const SizedBox(height: 20),
                  _photoBox(t, missingPhoto),
                  const SizedBox(height: 20),
                  BrutalField(
                    label: t['sellField'],
                    hint: 'Kolo, ki skoraj dela',
                    controller: _title,
                    maxLength: 120,
                    textInputAction: TextInputAction.next,
                    errorText: missingTitle ? t['sellTitleRequired'] : null,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 18),
                  BrutalField(
                    label: t['sellDesc'],
                    hint: '...',
                    controller: _desc,
                    maxLength: 2000,
                    maxLines: 5,
                  ),
                  const SizedBox(height: 18),
                  _priceBox(t),
                  const SizedBox(height: 20),
                  Text(
                    t['sellAs'].replaceAll('{name}', widget.session.me?.name ?? ''),
                    style: Brutal.body.copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(t['sellRules'], style: Brutal.body.copyWith(fontSize: 13, color: Brutal.ink.withValues(alpha: 0.7))),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    BrutalBox(
                      color: Brutal.danger,
                      padding: const EdgeInsets.all(12),
                      child: Text(_error!, style: Brutal.body.copyWith(fontSize: 15)),
                    ),
                  ],
                  const SizedBox(height: 20),
                  BrutalButton(
                    color: Brutal.pink,
                    onPressed: _sending ? null : _publish,
                    child: Center(
                      child: Text(
                        _sending ? '${((_progress ?? 0) * 100).round()} %' : t['sellSubmit'],
                        style: Brutal.label.copyWith(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoBox(Strings t, bool missing) {
    final preview = _preview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 240,
          decoration: BoxDecoration(
            color: Brutal.paperDeep,
            border: Border.all(color: missing ? Brutal.danger : Brutal.ink, width: Brutal.border),
            boxShadow: Brutal.shadow(dx: 5, dy: 5),
          ),
          child: preview == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_a_photo_outlined, size: 40),
                      const SizedBox(height: 8),
                      Text(t['sellPhoto'], style: Brutal.label.copyWith(fontSize: 13)),
                      if (missing) ...[
                        const SizedBox(height: 4),
                        Text(t['sellPhotoRequired'], style: Brutal.body.copyWith(color: Brutal.danger)),
                      ],
                    ],
                  ),
                )
              : Image.memory(preview, fit: BoxFit.contain),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (_canCamera) ...[
              Expanded(
                child: BrutalButton(
                  color: Brutal.yellow,
                  onPressed: _sending ? null : () => _pick(ImageSource.camera),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: Text(t['camera'], style: Brutal.label.copyWith(fontSize: 13))),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: BrutalButton(
                color: Brutal.cyan,
                onPressed: _sending ? null : () => _pick(ImageSource.gallery),
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Text(
                    preview == null ? t['library'] : t['sellPhotoChange'],
                    style: Brutal.label.copyWith(fontSize: 13),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _priceBox(Strings t) {
    Widget seg(_PriceMode m, String label) => Expanded(
      child: GestureDetector(
        onTap: _sending ? null : () => setState(() {
          _mode = m;
          _priceError = null;
        }),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          color: _mode == m ? kHot : Brutal.paper,
          child: Text(label, textAlign: TextAlign.center, style: Brutal.label.copyWith(fontSize: 12)),
        ),
      ),
    );
    const divider = SizedBox(width: Brutal.border, height: 40, child: ColoredBox(color: Brutal.ink));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(border: Brutal.outline, boxShadow: Brutal.shadow(dx: 4, dy: 4)),
          child: IntrinsicHeight(
            child: Row(
              children: [
                seg(_PriceMode.amount, t['sellPriceAmount']),
                divider,
                seg(_PriceMode.offer, t['sellPriceOffer']),
                divider,
                seg(_PriceMode.free, t['sellPriceFree']),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        switch (_mode) {
          _PriceMode.amount => BrutalField(
            label: t['sellPriceField'],
            hint: '12,50',
            controller: _price,
            maxLength: 12,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            errorText: _priceError,
          ),
          _PriceMode.offer => Text(t['sellPriceOfferNote'], style: Brutal.body.copyWith(fontSize: 14)),
          _PriceMode.free => Text(t['sellPriceFreeNote'], style: Brutal.body.copyWith(fontSize: 14)),
        },
      ],
    );
  }
}
