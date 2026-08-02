import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n.dart';
import '../models.dart';
import '../prefs.dart';
import '../theme.dart';
import '../widgets.dart';
import 'detail.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key, required this.api, required this.prefs});

  final Api api;
  final Prefs prefs;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final _scroll = ScrollController();
  final List<Post> _posts = [];

  PostSort _sort = PostSort.newest;
  int _page = 1;
  bool _loading = false;
  bool _hasNext = true;
  String? _error;

  String? _lang;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // No _load() here: it needs the language, and reading an InheritedWidget
    // from initState throws. didChangeDependencies runs before the first paint
    // and again whenever the language changes, which is exactly what we want.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lang = L10n.of(context).code;
    if (lang == _lang) return;
    _lang = lang;
    _hasNext = true;
    _load(reset: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final nearBottom = _scroll.position.pixels >= _scroll.position.maxScrollExtent - 500;
    if (nearBottom && !_loading && _hasNext) _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      if (reset) _error = null;
    });

    try {
      final page = reset ? 1 : _page;
      final result = await widget.api.posts(page: page, lang: _lang ?? 'en', sort: _sort);
      if (!mounted) return;
      setState(() {
        if (reset) _posts.clear();
        _posts.addAll(result.items);
        _hasNext = result.hasNext;
        _page = page + 1;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    _hasNext = true;
    await _load(reset: true);
  }

  Future<void> _setSort(PostSort s) async {
    if (s == _sort) return;
    setState(() {
      _sort = s;
      _hasNext = true;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    final showFullError = _error != null && _posts.isEmpty;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          BrandHeader(title: t['galleryTitle'], subtitle: t['gallerySub']),
          _SortBar(sort: _sort, onChange: _setSort),
          const SizedBox(height: 12),
          Expanded(
            child: showFullError
                ? ErrorState(message: _error!, onRetry: _refresh)
                : RefreshIndicator(
                    onRefresh: _refresh,
                    color: Brutal.ink,
                    backgroundColor: Brutal.cyan,
                    child: _posts.isEmpty && _loading
                        ? Loading(label: t['loadingArchive'])
                        : _posts.isEmpty
                        ? _empty(t)
                        : GridView.builder(
                            controller: _scroll,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 230,
                              mainAxisSpacing: 18,
                              crossAxisSpacing: 14,
                              // A fixed pixel height, not a ratio. The caption
                              // is the same height on every phone, so tying the
                              // tile to width made narrow screens overflow.
                              // PostCard's media absorbs the remainder.
                              mainAxisExtent: 296,
                            ),
                            itemCount: _posts.length + (_hasNext ? 1 : 0),
                            itemBuilder: (context, i) {
                              if (i >= _posts.length) {
                                return const Center(
                                  child: SizedBox(
                                    width: 26,
                                    height: 26,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: Brutal.ink,
                                    ),
                                  ),
                                );
                              }
                              final p = _posts[i];
                              return PostCard(
                                post: p,
                                index: i,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => PostDetailScreen(
                                      post: p,
                                      api: widget.api,
                                      prefs: widget.prefs,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _empty(Strings t) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      const SizedBox(height: 90),
      Center(
        child: BrutalBox(
          color: Brutal.yellow,
          rotation: -0.02,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🫥', style: TextStyle(fontSize: 44)),
              const SizedBox(height: 10),
              Text(t['emptyArchive'], style: Brutal.label.copyWith(fontSize: 16)),
              const SizedBox(height: 4),
              Text(t['emptySuspicious'], style: Brutal.body.copyWith(fontSize: 15)),
            ],
          ),
        ),
      ),
    ],
  );
}

class _SortBar extends StatelessWidget {
  const _SortBar({required this.sort, required this.onChange});

  final PostSort sort;
  final ValueChanged<PostSort> onChange;

  @override
  Widget build(BuildContext context) {
    final t = L10n.of(context);
    const colors = {
      PostSort.newest: Brutal.cyan,
      PostSort.top: Brutal.lime,
      PostSort.featured: Brutal.yellow,
    };
    final labels = {
      PostSort.newest: t['sortNewest'],
      PostSort.top: t['sortTop'],
      PostSort.featured: t['sortFeatured'],
    };

    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final s in PostSort.values)
            Padding(
              padding: const EdgeInsets.only(right: 9),
              child: GestureDetector(
                onTap: () => onChange(s),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 130),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  decoration: BoxDecoration(
                    color: s == sort ? colors[s] : Brutal.paper,
                    border: Brutal.outline,
                    boxShadow: s == sort ? Brutal.shadow(dx: 3, dy: 3) : null,
                  ),
                  child: Text(labels[s]!, style: Brutal.label.copyWith(fontSize: 13)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
