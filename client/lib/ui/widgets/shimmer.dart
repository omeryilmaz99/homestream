import 'package:flutter/material.dart';

import '../theme.dart';

/// Lightweight shimmer used for loading skeletons.
class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});
  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value * 3 - 1;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (r) => LinearGradient(
            begin: Alignment(t - 1, -0.3),
            end: Alignment(t + 1, 0.3),
            colors: const [
              AppColors.surface2,
              AppColors.surface3,
              AppColors.surface2,
            ],
            stops: const [0.35, 0.5, 0.65],
          ).createShader(r),
          child: child,
        );
      },
    );
  }
}

class SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double radius;
  const SkeletonBox({super.key, this.width, this.height, this.radius = 10});
  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

class RowSkeleton extends StatelessWidget {
  final double itemWidth;
  final double itemHeight;
  const RowSkeleton({super.key, this.itemWidth = 170, this.itemHeight = 255});
  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(48, 12, 0, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonBox(width: 200, height: 22, radius: 6),
            const SizedBox(height: 14),
            SizedBox(
              height: itemHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 10,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (_, _) =>
                    SkeletonBox(width: itemWidth, height: itemHeight),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
