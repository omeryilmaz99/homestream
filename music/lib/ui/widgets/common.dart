import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../state/app_state.dart';
import '../neu.dart';
import '../theme.dart';
import 'profile_button.dart';

void showToast(BuildContext context, String message) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
  );
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const SectionHeader(this.title, {super.key, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: T.h2,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (action != null)
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onAction,
              child: Text(action!, style: T.link),
            )
          else
            const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// Shrinks its child a little while pressed (cards, tiles).
class PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
  });
  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;
  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: const Duration(milliseconds: 120),
        child: AnimatedOpacity(
          opacity: _down ? 0.85 : 1,
          duration: const Duration(milliseconds: 120),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Fades and slides a child in once (lists appear with a little motion).
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int index;
  final double offset;
  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = 16,
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  @override
  void initState() {
    super.initState();
    final delay = Duration(milliseconds: math.min(widget.index, 10) * 35);
    Future.delayed(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: a,
      builder: (context, child) => Opacity(
        opacity: a.value,
        child: Transform.translate(
          offset: Offset(0, (1 - a.value) * widget.offset),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Animated equalizer bars for the song that is playing.
class PlayingBars extends StatefulWidget {
  final bool animate;
  final double size;
  final Color color;
  const PlayingBars({
    super.key,
    this.animate = true,
    this.size = 16,
    this.color = C.accent,
  });

  @override
  State<PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<PlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void didUpdateWidget(PlayingBars old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_c.isAnimating) _c.repeat();
    if (!widget.animate && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value * 2 * math.pi;
          final hs = [
            0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * 2)),
            0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * 3 + 1.3)),
            0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * 2 + 2.6)),
          ];
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final h in hs)
                Container(
                  width: widget.size / 4.5,
                  height: widget.size * (widget.animate ? h : 0.35),
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NeuBox(
              circle: true,
              width: 96,
              height: 96,
              child: Icon(icon, size: 42, color: C.textDim),
            ),
            const SizedBox(height: 22),
            Text(title, style: T.h3, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!, style: T.dim, textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 34,
        height: 34,
        child: CircularProgressIndicator(strokeWidth: 3),
      ),
    );
  }
}

/// Loads data with loading / error / offline states and pull-to-refresh.
/// Reloads when the library changes or the connection comes back.
class DataView<D> extends StatefulWidget {
  final Future<D> Function(ApiClient api) load;
  final Widget Function(
    BuildContext context,
    D data,
    Future<void> Function() reload,
  )
  builder;
  final Widget? offline;
  final Object? reloadKey;
  const DataView({
    super.key,
    required this.load,
    required this.builder,
    this.offline,
    this.reloadKey,
  });

  @override
  State<DataView<D>> createState() => _DataViewState<D>();
}

class _DataViewState<D> extends State<DataView<D>> {
  D? _data;
  String? _error;
  bool _loading = true;
  late AppState _app;
  int _version = 0;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _version = _app.libraryVersion.value;
    _app.libraryVersion.addListener(_onVersion);
    _load();
  }

  @override
  void didUpdateWidget(DataView<D> old) {
    super.didUpdateWidget(old);
    if (old.reloadKey != widget.reloadKey) _load();
  }

  void _onVersion() {
    if (_app.libraryVersion.value != _version) {
      _version = _app.libraryVersion.value;
      _load(quiet: true);
    }
  }

  @override
  void dispose() {
    _app.libraryVersion.removeListener(_onVersion);
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    final api = _app.api;
    if (api == null) return;
    if (!quiet) {
      setState(() {
        _loading = _data == null;
        _error = null;
      });
    }
    try {
      final d = await widget.load(api);
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
        _error = null;
      });
      if (!_app.online) _app.ping();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.offline) _app.ping();
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = context.select<AppState, bool>((s) => s.online);
    if (_data != null) {
      return RefreshIndicator(
        color: C.accent,
        backgroundColor: C.bg,
        onRefresh: () => _load(quiet: true),
        child: widget.builder(context, _data as D, () => _load(quiet: true)),
      );
    }
    if (_loading) return const LoadingView();
    if (!online && widget.offline != null) return widget.offline!;
    return EmptyState(
      icon: online ? Icons.error_outline_rounded : Icons.cloud_off_rounded,
      title: online ? 'Yüklenemedi' : 'Sunucuya bağlanılamıyor',
      message: online
          ? _error
          : 'İndirdiğin şarkıları Kitaplık > İndirilenler bölümünden dinleyebilirsin.',
      action: AccentPill('Tekrar dene', onTap: _load),
    );
  }
}

/// Slim banner shown while the server can't be reached.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final online = context.select<AppState, bool>((s) => s.online);
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      child: online
          ? const SizedBox(width: double.infinity)
          : Material(
              color: const Color(0xFF3A2F1E),
              child: InkWell(
                onTap: () async {
                  final ok = await context.read<AppState>().ping();
                  if (context.mounted) {
                    showToast(
                      context,
                      ok ? 'Bağlantı kuruldu' : 'Sunucuya hâlâ ulaşılamıyor',
                    );
                  }
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  child: Row(
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 16,
                        color: Color(0xFFFFC66D),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Çevrimdışı — indirilen şarkılar çalınabilir',
                          style: TextStyle(
                            color: Color(0xFFFFD99A),
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      Text(
                        'Yenile',
                        style: TextStyle(
                          color: Color(0xFFFFC66D),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
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

/// Page scaffold with a large title for the tab screens.
class PageTitle extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  final bool profile; // profile picture at the right end
  const PageTitle(
    this.title, {
    super.key,
    this.actions = const [],
    this.profile = true,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.paddingOf(context).top + 14,
        14,
        6,
      ),
      child: Row(
        children: [
          Expanded(child: Text(title, style: T.h1)),
          ...actions,
          if (profile) ...[const SizedBox(width: 2), const ProfileButton()],
        ],
      ),
    );
  }
}
