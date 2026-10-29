import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// With a remote control there is no mouse: if nothing is focused when a
/// direction or OK key is pressed, focus the first control of the screen
/// instead of ignoring the key.
void installTvFocusFallback() {
  HardwareKeyboard.instance.addHandler((event) {
    if (event is! KeyDownEvent) return false;
    final keys = {
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.select,
      LogicalKeyboardKey.enter,
    };
    if (!keys.contains(event.logicalKey)) return false;
    final primary = FocusManager.instance.primaryFocus;
    // a text box swallows up/down for its cursor; on a remote that would trap
    // the user, so up/down always leaves the box
    final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if ((up || event.logicalKey == LogicalKeyboardKey.arrowDown) &&
        primary?.context?.findAncestorStateOfType<EditableTextState>() !=
            null) {
      primary!.focusInDirection(
        up ? TraversalDirection.up : TraversalDirection.down,
      );
      return true;
    }
    final hasLeaf =
        primary != null &&
        primary is! FocusScopeNode &&
        primary.context != null;
    if (hasLeaf) return false;
    final scope = primary is FocusScopeNode
        ? primary
        : FocusManager.instance.rootScope;
    // the deepest focused scope (current route / dialog)
    var s = scope;
    while (s.focusedChild is FocusScopeNode) {
      s = s.focusedChild! as FocusScopeNode;
    }
    return s.nextFocus();
  });
}

/// A plain tap target that can also be reached and pressed with a remote:
/// it takes focus, reacts to OK/Enter and rebuilds with [focused] set.
class Focusable extends StatefulWidget {
  final VoidCallback onTap;
  final bool autofocus;
  final FocusNode? focusNode;
  final Widget Function(BuildContext context, bool focused) builder;
  const Focusable({
    super.key,
    required this.onTap,
    required this.builder,
    this.autofocus = false,
    this.focusNode,
  });
  @override
  State<Focusable> createState() => _FocusableState();
}

class _FocusableState extends State<Focusable> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (f) => setState(() => _focused = f),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: widget.builder(context, _focused),
      ),
    );
  }
}

/// Sliders take up/down on a keyboard too, which traps a remote control on
/// them. In directional mode they only use left/right, so up/down move on.
class RemoteSlider extends StatelessWidget {
  final Widget child;
  const RemoteSlider({super.key, required this.child});
  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(navigationMode: NavigationMode.directional),
    child: child,
  );
}
