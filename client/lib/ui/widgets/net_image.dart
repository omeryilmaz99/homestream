import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/image_cache.dart';
import '../../state/app_state.dart';
import '../theme.dart';

/// Loads a server image path ("/api/images/...") with disk caching, a soft
/// fade-in and a neutral placeholder.
class NetImage extends StatelessWidget {
  final String path;
  final int? width;
  final BoxFit fit;
  final Alignment alignment;
  final Widget? placeholder;
  const NetImage(
    this.path, {
    super.key,
    this.width,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    final api = context.select<AppState, ApiClient?>((s) => s.api);
    final ph = placeholder ?? const ColoredBox(color: AppColors.surface2);
    if (api == null || path.isEmpty) return ph;
    final url = api.imageUrl(path, width: width);
    return Image(
      image: CachedNetImage(url),
      fit: fit,
      alignment: alignment,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      frameBuilder: (context, child, frame, sync) {
        if (sync) return child;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          layoutBuilder: (current, previous) =>
              Stack(fit: StackFit.expand, children: [...previous, ?current]),
          child: frame == null ? ph : child,
        );
      },
      errorBuilder: (context, error, stack) => ph,
    );
  }
}
