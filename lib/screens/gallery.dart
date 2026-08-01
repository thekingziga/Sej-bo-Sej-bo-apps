import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'detail.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key, required this.api});

  final Api api;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final _scroll = ScrollController();
  final List<Post> _posts = [];

  int _page = 1;
  bool _loading = false;
  bool _hasNext = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
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
      final result = await widget.api.posts(page: page);
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

  @override
  Widget build(BuildContext context) {
    final showFullError = _error != null && _posts.isEmpty;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const BrandHeader(
            title: 'Gallery',
            subtitle: 'Newest first. Most questionable first, spiritually.',
          ),
          Expanded(
            child: showFullError
                ? ErrorState(message: _error!, onRetry: _refresh)
                : RefreshIndicator(
                    onRefresh: _refresh,
                    color: Brutal.ink,
                    backgroundColor: Brutal.cyan,
                    child: _posts.isEmpty && _loading
                        ? const Loading(label: 'LOADING THE ARCHIVE...')
                        : _posts.isEmpty
                        ? _empty()
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
                              mainAxisExtent: 288,
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
                                  MaterialPageRoute(builder: (_) => PostDetailScreen(post: p)),
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

  Widget _empty() => ListView(
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
              Text('THE ARCHIVE IS EMPTY.', style: Brutal.label.copyWith(fontSize: 16)),
              const SizedBox(height: 4),
              Text('Suspicious.', style: Brutal.body.copyWith(fontSize: 15)),
            ],
          ),
        ),
      ),
    ],
  );
}
