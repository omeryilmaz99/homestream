import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Phone-sized screens (portrait phones, small windows) get a compact layout:
/// narrower margins, smaller cards and a bottom navigation bar.
/// Uses the short side, so a phone held sideways stays compact.
bool isCompact(BuildContext context) =>
    MediaQuery.sizeOf(context).shortestSide < 560;

/// Compact and taller than wide (phone held upright).
bool isPortraitPhone(BuildContext context) {
  final s = MediaQuery.sizeOf(context);
  return s.shortestSide < 560 && s.height > s.width;
}

/// Side margin of pages.
double pagePad(BuildContext context) => isCompact(context) ? 16 : 48;

/// Space above page content, below the top bar.
double pageTop(BuildContext context) =>
    isCompact(context) ? MediaQuery.paddingOf(context).top + 68 : 100;

/// Space below page content (above the bottom navigation on phones).
double pageBottom(BuildContext context) =>
    isCompact(context) ? MediaQuery.paddingOf(context).bottom + 90 : 48;

/// Poster grid: three columns on a phone, more on wider screens.
SliverGridDelegate posterGrid(BuildContext context) {
  final compact = isCompact(context);
  return SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: compact ? 135 : 190,
    childAspectRatio: 2 / 3,
    mainAxisSpacing: compact ? 12 : 22,
    crossAxisSpacing: compact ? 10 : 16,
  );
}
