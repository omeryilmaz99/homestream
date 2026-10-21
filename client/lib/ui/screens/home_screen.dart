import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../core/platform.dart';
import '../../state/app_state.dart';
import '../layout.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/hero_banner.dart';
import '../widgets/media_row.dart';
import '../widgets/shimmer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeData? _data;
  String? _error;
  bool _scanning = false;
  late final AppState _state = context.read<AppState>();

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
    try {
      final d = await api.home();
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    try {
      await _state.api!.scan();
      // poll until done
      for (var i = 0; i < 600; i++) {
        await Future.delayed(const Duration(seconds: 2));
        final st = await _state.api!.scanStatus();
        if (!st.running) break;
      }
    } catch (_) {}
    if (mounted) setState(() => _scanning = false);
    _state.bumpData();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _data == null) {
      return ErrorState(message: _error!, onRetry: _load);
    }
    final d = _data;
    if (d == null) {
      return ListView(
        padding: EdgeInsets.only(top: pageTop(context)),
        children: const [
          Shimmer(child: SkeletonBox(height: 420, radius: 0)),
          SizedBox(height: 24),
          RowSkeleton(itemWidth: 300, itemHeight: 170),
          RowSkeleton(),
        ],
      );
    }
    if (d.rows.isEmpty && d.hero.isEmpty) {
      final host = Uri.tryParse(_state.server?.url ?? '')?.host ?? 'sunucu';
      return EmptyState(
        icon: Icons.video_library_rounded,
        title: 'Kütüphane henüz boş',
        message:
            'Filmlerini ve dizilerini sunucudaki HomeStream klasörüne kopyala.\n'
            'Windows\'ta Dosya Gezgini\'nin adres çubuğuna  \\\\$host\\HomeStream  yazarak klasörü açabilirsin.\n'
            'Kopyalama bitince ${AppPlatform.canManageServer ? 'aşağıdaki düğmeye bas.' : 'bilgisayardaki Home Stream uygulamasından kütüphaneyi tarat.'}',
        action: !AppPlatform.canManageServer
            ? null
            : PillButton(
                primary: true,
                icon: _scanning ? null : Icons.sync_rounded,
                label: _scanning ? 'Taranıyor…' : 'Kütüphaneyi tara',
                onPressed: _scanning ? null : _scan,
              ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: HeroBanner(items: d.hero)),
          SliverToBoxAdapter(child: SizedBox(height: d.hero.isEmpty ? 90 : 0)),
          SliverList.builder(
            itemCount: d.rows.length,
            itemBuilder: (context, i) {
              final r = d.rows[i];
              return MediaRow(
                key: ValueKey('row-${r.id}'),
                title: r.title,
                items: r.items,
                wide: r.id == 'continue' || r.id == 'nextup',
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
          SliverToBoxAdapter(
            child: Center(
              child: Text(
                '${_state.serverInfo?.name ?? ''} · Home Stream',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
