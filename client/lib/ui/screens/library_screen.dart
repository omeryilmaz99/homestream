import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/media_card.dart';
import '../widgets/shimmer.dart';

/// Grid of all movies or all series with sort / genre / watched filters.
class LibraryScreen extends StatefulWidget {
  final bool series;
  const LibraryScreen({super.key, required this.series});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final AppState _state = context.read<AppState>();
  List<MediaItem>? _items;
  List<String> _genres = [];
  String? _error;
  String _sort = 'added';
  String? _genre;
  String? _filter;
  int _reqId = 0;

  static const _sorts = {
    'added': 'Son eklenen',
    'title': 'İsim (A-Z)',
    'year': 'Yıl',
    'rating': 'Puan',
    'lastPlayed': 'Son izlenen',
  };
  static const _filters = {
    null: 'Tümü',
    'unwatched': 'İzlenmeyenler',
    'watched': 'İzlenenler',
    'liked': 'Beğendiklerim',
  };

  @override
  void initState() {
    super.initState();
    _state.dataVersion.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _state.dataVersion.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final api = _state.api;
    if (api == null) return;
    final id = ++_reqId;
    try {
      final items = widget.series
          ? await api.series(sort: _sort, genre: _genre, filter: _filter)
          : await api.movies(sort: _sort, genre: _genre, filter: _filter);
      final genres = await api.genres().catchError((_) => <String>[]);
      if (!mounted || id != _reqId) return;
      setState(() {
        _items = items;
        _genres = genres;
        _error = null;
      });
    } catch (e) {
      if (mounted && id == _reqId) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.series ? 'Diziler' : 'Filmler';
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(48, 100, 48, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(width: 14),
                if (_items != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${_items!.length}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 18,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(48, 8, 48, 18),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Dropdown<String>(
                  icon: Icons.sort_rounded,
                  value: _sort,
                  items: _sorts,
                  onChanged: (v) {
                    setState(() => _sort = v ?? 'added');
                    _load();
                  },
                ),
                _Dropdown<String?>(
                  icon: Icons.filter_list_rounded,
                  value: _filter,
                  items: _filters,
                  onChanged: (v) {
                    setState(() => _filter = v);
                    _load();
                  },
                ),
                if (_genres.isNotEmpty)
                  _Dropdown<String?>(
                    icon: Icons.local_offer_outlined,
                    value: _genre,
                    items: {null: 'Tüm türler', for (final g in _genres) g: g},
                    onChanged: (v) {
                      setState(() => _genre = v);
                      _load();
                    },
                  ),
              ],
            ),
          ),
        ),
        if (_error != null && _items == null)
          SliverFillRemaining(
            child: ErrorState(message: _error!, onRetry: _load),
          )
        else if (_items == null)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            sliver: SliverGrid(
              gridDelegate: _grid,
              delegate: SliverChildBuilderDelegate(
                (_, _) => const Shimmer(child: SkeletonBox()),
                childCount: 18,
              ),
            ),
          )
        else if (_items!.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: widget.series ? Icons.live_tv_rounded : Icons.movie_rounded,
              title: _filter != null || _genre != null
                  ? 'Bu filtreye uyan bir şey yok'
                  : (widget.series ? 'Henüz dizi yok' : 'Henüz film yok'),
              message: _filter != null || _genre != null
                  ? null
                  : 'Sunucudaki HomeStream klasörüne eklediğin ${widget.series ? 'diziler' : 'filmler'} burada görünecek.',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(48, 0, 48, 48),
            sliver: SliverGrid(
              gridDelegate: _grid,
              delegate: SliverChildBuilderDelegate(
                (context, i) => LayoutBuilder(
                  builder: (context, c) =>
                      PosterCard(item: _items![i], width: c.maxWidth),
                ),
                childCount: _items!.length,
              ),
            ),
          ),
      ],
    );
  }

  static const _grid = SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 190,
    childAspectRatio: 2 / 3,
    mainAxisSpacing: 22,
    crossAxisSpacing: 16,
  );
}

class _Dropdown<T> extends StatelessWidget {
  final IconData icon;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T?> onChanged;
  const _Dropdown({
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.textDim),
          const SizedBox(width: 6),
          DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: items.containsKey(value) ? value : null,
              dropdownColor: AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
              style: const TextStyle(fontSize: 14, color: AppColors.text),
              items: items.entries
                  .map(
                    (e) =>
                        DropdownMenuItem<T>(value: e.key, child: Text(e.value)),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
