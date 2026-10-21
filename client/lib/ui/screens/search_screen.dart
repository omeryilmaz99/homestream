import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../state/app_state.dart';
import '../layout.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/media_card.dart';
import '../widgets/media_row.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  SearchResults? _results;
  bool _loading = false;
  String? _error;
  int _req = 0;

  void focus() => _focus.requestFocus();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () => _search(q));
  }

  Future<void> _search(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      setState(() {
        _results = null;
        _loading = false;
      });
      return;
    }
    final id = ++_req;
    setState(() => _loading = true);
    try {
      final r = await context.read<AppState>().api!.search(query);
      if (!mounted || id != _req) return;
      setState(() {
        _results = r;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted && id == _req) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _results;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              pagePad(context),
              pageTop(context),
              pagePad(context),
              24,
            ),
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              onChanged: _onChanged,
              onSubmitted: _search,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'Film, dizi veya bölüm ara…',
                prefixIcon: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Icon(Icons.search_rounded, size: 28),
                ),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : (_ctrl.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _ctrl.clear();
                                _search('');
                              },
                            )),
                contentPadding: const EdgeInsets.symmetric(vertical: 22),
              ),
            ),
          ),
        ),
        if (_error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: pagePad(context)),
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.danger),
              ),
            ),
          ),
        if (r == null)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.manage_search_rounded,
              title: 'Ne izlemek istersin?',
              message:
                  'Türkçe karakter yazmana gerek yok: "gorev" yazınca "Görev" de bulunur.',
            ),
          )
        else if (r.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Sonuç bulunamadı',
              message: '"${_ctrl.text}" için bir şey bulamadık.',
            ),
          )
        else ...[
          if (r.movies.isNotEmpty || r.series.isNotEmpty)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                pagePad(context),
                0,
                pagePad(context),
                24,
              ),
              sliver: SliverGrid(
                gridDelegate: posterGrid(context),
                delegate: SliverChildBuilderDelegate((context, i) {
                  final all = [...r.series, ...r.movies];
                  return LayoutBuilder(
                    builder: (context, c) =>
                        PosterCard(item: all[i], width: c.maxWidth),
                  );
                }, childCount: r.movies.length + r.series.length),
              ),
            ),
          if (r.episodes.isNotEmpty)
            SliverToBoxAdapter(
              child: MediaRow(title: 'Bölümler', items: r.episodes, wide: true),
            ),
          SliverToBoxAdapter(child: SizedBox(height: pageBottom(context))),
        ],
      ],
    );
  }
}
