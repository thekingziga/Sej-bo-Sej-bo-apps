import 'package:flutter/widgets.dart';

/// Deliberately a plain map rather than generated ARB localisations: the website
/// keeps its copy in a hand-written `i18n` object in server.js, and keeping the
/// two in the same shape makes it obvious when one gains a string the other lacks.
enum Lang { en, sl }

class Strings {
  const Strings._(this.lang, this._m);

  final Lang lang;
  final Map<String, String> _m;

  String get(String key) => _m[key] ?? key;

  /// Shorthand so screens read as `t.homeTitle` rather than `t.get('homeTitle')`.
  String operator [](String key) => get(key);

  static const _en = <String, String>{
    'brandSub': 'Officially certifying stupidity',
    'tabHome': 'HOME',
    'tabGallery': 'GALLERY',
    'tabUpload': 'UPLOAD',
    'tabSupport': 'SUPPORT',
    'demoBanner': 'DEMO DATA — the website API is not live yet',
    'offlineBanner': 'OFFLINE — showing the last loaded feed',
    'visitors': 'Visitors',
    'archived': 'Archived',
    'daysSince': 'Days since',
    'latest': 'LATEST SEJBOSEJBO',
    'moreChaos': 'More chaos',
    'seeAll': 'see all',
    'hallOfFame': 'Hall of fame',
    'randomQuote': 'RANDOM QUOTE',
    'todaysAward': "TODAY'S AWARD",
    'pressIt': 'Press it. You know you want to.',
    'measuring': 'Measuring Sejbosejbo...',
    'measureFailed': 'Calibrating stupidity detector failed.',
    'submitCta': 'SUBMIT A SEJBOSEJBO',
    'galleryTitle': 'Gallery',
    'gallerySub': 'Newest first. Most questionable first, spiritually.',
    'sortNewest': 'NEWEST',
    'sortTop': 'TOP',
    'sortFeatured': 'FEATURED',
    'emptyArchive': 'THE ARCHIVE IS EMPTY.',
    'emptySuspicious': 'Suspicious.',
    'loadingArchive': 'LOADING THE ARCHIVE...',
    'uploadTitle': 'Submit',
    'uploadSub': 'Image, GIF, or just a cursed story. Anonymous by design.',
    'addPhoto': 'ADD A PHOTO OR GIF',
    'addPhotoSub': 'optional — a story alone also counts',
    'camera': 'CAMERA',
    'library': 'LIBRARY',
    'paste': 'PASTE',
    'edit': 'EDIT',
    'editPhoto': 'Crop / rotate',
    'editFailed': 'Could not open the editor.',
    'change': 'CHANGE',
    'remove': 'REMOVE',
    'labelTitle': 'Title',
    'hintTitle': 'Microwaved a salad',
    'labelStory': 'Description or story',
    'hintStory': 'What happened? Why was it like this?',
    'needsMore': 'Needs a title, plus either a photo or a story.',
    'submitButton': 'SUBMIT THIS SEJBOSEJBO',
    'clipboardEmpty': 'No image on the clipboard.',
    'supportTitle': 'Support',
    'supportSub': 'Keep the nonsense online',
    'pitchTitle': 'THIS RUNS ON A\nRASPBERRY PI',
    'pitchBody':
        'No ads. No tracking. No accounts. Just a very small computer in a '
            'cupboard, archiving humanity’s worst decisions.',
    'thanksTitle': 'CERTIFIED LEGEND',
    'thanksBody': 'The Pi thanks you. It will keep going.',
    'railStore': 'Handled by the App Store / Google Play. They take their cut '
        'before it reaches the Pi — that is their rule, not ours.',
    'railStripe': 'Handled by Stripe in your browser. Card details never touch this app.',
    'officially': 'THIS IS OFFICIALLY\nSEJBOSEJBO.',
    'featured': 'featured',
    'pinned': 'pinned',
    'share': 'SHARE',
    'shareText': 'This is officially Sejbosejbo.',
    'voteUp': 'SEJ BO',
    'voteDown': 'SEJ NE BO',
    'errorTitle': 'SEJBOSEJBO DETECTED',
    'tryAgain': 'TRY AGAIN',
    'justNow': 'just now',
    'report': 'REPORT',
    'reportTitle': 'Report this Sejbosejbo',
    'reportSub': 'Tell us what is wrong and it goes to a human for review.',
    'reasonSpam': 'Spam',
    'reasonInappropriate': 'Inappropriate content',
    'reasonHarassment': 'Harassment or bullying',
    'reasonCopyright': 'Copyright / it is my content',
    'reasonOther': 'Something else',
    'reportDetails': 'Anything else? (optional)',
    'reportDetailsHint': 'Add context if it helps.',
    'reportSend': 'SEND REPORT',
    'reportCancel': 'CANCEL',
    'reportThanks': 'Report sent. A human will look at it.',
    'legalPrivacy': 'Privacy policy',
    'legalTerms': 'Terms',
    'legalWebsite': 'Open the website',
    'comments': 'Comments',
    'commentsEmpty': 'No comments yet. Be the first.',
    'commentHint': 'Say something...',
    'commentSend': 'POST',
    'commentsMore': 'SHOW MORE',
    'commentsFailed': 'Could not load the comments.',
    'commentSent': 'Comment posted.',
    'commentYou': 'YOU',
    'commentAnon': 'Anonymous',
    'sortOldest': 'OLDEST',
    'sortBest': 'TOP',
    'retryIn': 'Too fast. Try again in {s}s.',
    'reportCommentTitle': 'Report this comment',
    'reportComment': 'Report comment',
    'unsupportedTitle': 'NEEDS A NEWER APP',
    'unsupportedBody': 'This one is a kind of post this version cannot show yet.',
    'openOnWeb': 'OPEN ON THE WEBSITE',
  };

  static const _sl = <String, String>{
    'brandSub': 'Uradno certificiramo neumnost',
    'tabHome': 'DOMOV',
    'tabGallery': 'GALERIJA',
    'tabUpload': 'NALOŽI',
    'tabSupport': 'PODPRI',
    'demoBanner': 'DEMO PODATKI — API spletne strani še ni živ',
    'offlineBanner': 'BREZ POVEZAVE — prikazan zadnji naložen seznam',
    'visitors': 'Obiskovalci',
    'archived': 'Arhivirani',
    'daysSince': 'Dni od zadnjega',
    'latest': 'NAJNOVEJŠI SEJBOSEJBO',
    'moreChaos': 'Več kaosa',
    'seeAll': 'poglej vse',
    'hallOfFame': 'Hram slavnih',
    'randomQuote': 'NAKLJUČNI CITAT',
    'todaysAward': 'DANAŠNJA NAGRADA',
    'pressIt': 'Pritisni. Saj veš, da hočeš.',
    'measuring': 'Merim Sejbosejbo...',
    'measureFailed': 'Kalibracija detektorja neumnosti ni uspela.',
    'submitCta': 'ODDAJ SEJBOSEJBO',
    'galleryTitle': 'Galerija',
    'gallerySub': 'Najnovejše najprej. Duhovno najbolj vprašljive tudi.',
    'sortNewest': 'NAJNOVEJŠE',
    'sortTop': 'NAJBOLJŠE',
    'sortFeatured': 'IZPOSTAVLJENO',
    'emptyArchive': 'ARHIV JE PRAZEN.',
    'emptySuspicious': 'Sumljivo.',
    'loadingArchive': 'NALAGAM ARHIV...',
    'uploadTitle': 'Oddaj',
    'uploadSub': 'Slika, GIF ali samo prekleta zgodba. Anonimno po dizajnu.',
    'addPhoto': 'DODAJ SLIKO ALI GIF',
    'addPhotoSub': 'neobvezno — tudi sama zgodba šteje',
    'camera': 'KAMERA',
    'library': 'GALERIJA',
    'paste': 'PRILEPI',
    'edit': 'UREDI',
    'editPhoto': 'Obreži / zavrti',
    'editFailed': 'Urejevalnika ni bilo mogoce odpreti.',
    'change': 'ZAMENJAJ',
    'remove': 'ODSTRANI',
    'labelTitle': 'Naslov',
    'hintTitle': 'Pogrel solato v mikrovalovki',
    'labelStory': 'Opis ali zgodba',
    'hintStory': 'Kaj se je zgodilo? Zakaj je bilo tako?',
    'needsMore': 'Potrebuje naslov in sliko ali zgodbo.',
    'submitButton': 'ODDAJ TA SEJBOSEJBO',
    'clipboardEmpty': 'Na odložišču ni slike.',
    'supportTitle': 'Podpri',
    'supportSub': 'Naj neumnost ostane na spletu',
    'pitchTitle': 'TO TEČE NA\nRASPBERRY PI-JU',
    'pitchBody':
        'Brez oglasov. Brez sledenja. Brez računov. Samo zelo majhen računalnik '
            'v omari, ki arhivira najslabše odločitve človeštva.',
    'thanksTitle': 'CERTIFICIRANA LEGENDA',
    'thanksBody': 'Pi se ti zahvaljuje. Šel bo naprej.',
    'railStore': 'Ureja App Store / Google Play. Svoj delež vzameta, preden '
        'pride do Pi-ja — to je njuno pravilo, ne naše.',
    'railStripe': 'Ureja Stripe v tvojem brskalniku. Podatki kartice nikoli ne '
        'pridejo v to aplikacijo.',
    'officially': 'TO JE URADNO\nSEJBOSEJBO.',
    'featured': 'izpostavljeno',
    'pinned': 'pripeto',
    'share': 'DELI',
    'shareText': 'To je uradno Sejbosejbo.',
    'voteUp': 'SEJ BO',
    'voteDown': 'SEJ NE BO',
    'errorTitle': 'ZAZNAN SEJBOSEJBO',
    'tryAgain': 'POSKUSI ZNOVA',
    'justNow': 'pravkar',
    'report': 'PRIJAVI',
    'reportTitle': 'Prijavi ta Sejbosejbo',
    'reportSub': 'Povej, kaj je narobe. Objavo bo pregledal clovek.',
    'reasonSpam': 'Neželena vsebina',
    'reasonInappropriate': 'Neprimerna vsebina',
    'reasonHarassment': 'Nadlegovanje ali ustrahovanje',
    'reasonCopyright': 'Avtorske pravice / to je moja vsebina',
    'reasonOther': 'Nekaj drugega',
    'reportDetails': 'Še kaj? (neobvezno)',
    'reportDetailsHint': 'Dodaj kontekst, ce pomaga.',
    'reportSend': 'POŠLJI PRIJAVO',
    'reportCancel': 'PREKLICI',
    'reportThanks': 'Prijava poslana. Pregledal jo bo clovek.',
    'legalPrivacy': 'Politika zasebnosti',
    'legalTerms': 'Pogoji uporabe',
    'legalWebsite': 'Odpri spletno stran',
    'comments': 'Komentarji',
    'commentsEmpty': 'Še ni komentarjev. Bodi prvi.',
    'commentHint': 'Povej kaj...',
    'commentSend': 'OBJAVI',
    'commentsMore': 'POKAŽI ŠE',
    'commentsFailed': 'Komentarjev ni bilo mogoce naložiti.',
    'commentSent': 'Komentar objavljen.',
    'commentYou': 'TI',
    'commentAnon': 'Anonimno',
    'sortOldest': 'NAJSTAREJŠE',
    'sortBest': 'NAJBOLJŠE',
    'retryIn': 'Prehitro. Poskusi znova cez {s} s.',
    'reportCommentTitle': 'Prijavi ta komentar',
    'reportComment': 'Prijavi komentar',
    'unsupportedTitle': 'POTREBUJE NOVEJŠO APLIKACIJO',
    'unsupportedBody': 'Te vrste objave ta razlicica še ne zna prikazati.',
    'openOnWeb': 'ODPRI NA SPLETNI STRANI',
  };

  static const en = Strings._(Lang.en, _en);
  static const sl = Strings._(Lang.sl, _sl);

  static Strings of(Lang l) => l == Lang.sl ? sl : en;

  String get code => lang == Lang.sl ? 'sl' : 'en';
}

/// Makes the active language available to the whole tree without a state
/// package. Rebuilds everything when [lang] changes.
class L10n extends InheritedWidget {
  const L10n({super.key, required this.strings, required this.onChange, required super.child});

  final Strings strings;
  final ValueChanged<Lang> onChange;

  static Strings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<L10n>()?.strings ?? Strings.en;

  static ValueChanged<Lang> changerOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<L10n>()?.onChange ?? (_) {};

  @override
  bool updateShouldNotify(L10n oldWidget) => oldWidget.strings.lang != strings.lang;
}
