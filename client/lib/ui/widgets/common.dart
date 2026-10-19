import 'package:flutter/material.dart';

import '../theme.dart';

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
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppColors.accent.withValues(alpha: 0.25),
                      AppColors.accent2.withValues(alpha: 0.18),
                    ],
                  ),
                ),
                child: Icon(icon, size: 40, color: Colors.white),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textDim,
                    height: 1.45,
                  ),
                ),
              ],
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorState({super.key, required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.cloud_off_rounded,
    title: 'Bir sorun oluştu',
    message: message,
    action: PillButton(
      icon: Icons.refresh_rounded,
      label: 'Tekrar dene',
      onPressed: onRetry,
    ),
  );
}

/// Small rounded tag like "4K", "HDR", "2010".
class Tag extends StatelessWidget {
  final String text;
  final bool outlined;
  final Color? color;
  const Tag(this.text, {super.key, this.outlined = true, this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: outlined ? null : (color ?? const Color(0x33FFFFFF)),
      border: outlined ? Border.all(color: const Color(0x66FFFFFF)) : null,
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.textDim,
      ),
    ),
  );
}

void showToast(BuildContext context, String msg, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(
            error
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            color: error ? AppColors.danger : AppColors.success,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(msg)),
        ],
      ),
      duration: Duration(seconds: error ? 5 : 2),
    ),
  );
}

/// Thin progress bar shown on cards.
class ProgressLine extends StatelessWidget {
  final double value;
  final double height;
  const ProgressLine(this.value, {super.key, this.height = 4});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height),
    child: SizedBox(
      height: height,
      child: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Color(0x55FFFFFF))),
          FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(
              decoration: const BoxDecoration(
                gradient: AppColors.brandGradient,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
