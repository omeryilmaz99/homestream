import 'package:flutter/material.dart';

/// Navigation inside the tabs: every tab keeps its own page stack, and pages
/// opened from the player or a sheet land in the current tab.
class ShellNav {
  static final rootKey = GlobalKey<NavigatorState>();
  static final tabKeys = List.generate(4, (_) => GlobalKey<NavigatorState>());
  static final tab = ValueNotifier<int>(0);

  static NavigatorState? get current => tabKeys[tab.value].currentState;

  /// Opens a page in the current tab (closing the player / sheets first).
  static void push(Widget page) {
    rootKey.currentState?.popUntil((r) => r.isFirst);
    current?.push(route(page));
  }

  static Route<T> route<T>(Widget page) => PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (context, a, _, child) {
      final c = CurvedAnimation(
        parent: a,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: c,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(c),
          child: child,
        ),
      );
    },
  );

  /// Switches tab; tapping the open tab again goes back to its first page.
  static void select(int i) {
    if (tab.value == i) {
      tabKeys[i].currentState?.popUntil((r) => r.isFirst);
    } else {
      tab.value = i;
    }
  }
}
