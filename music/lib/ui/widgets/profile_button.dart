import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../nav.dart';
import '../screens/home_screen.dart' show ProfileAvatar;
import '../screens/profile_screen.dart';

/// Round picture of the profile at the top right of the tab pages: opens
/// the profile page.
class ProfileButton extends StatelessWidget {
  final double size;
  const ProfileButton({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final profile = context.select<AppState, Object?>((s) => s.profile);
    final app = context.read<AppState>();
    return Tooltip(
      message: 'Profil',
      child: Semantics(
        button: true,
        label: 'Profil',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ShellNav.push(const ProfileScreen()),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: ProfileAvatar(
              key: ValueKey(profile),
              profile: app.profile,
              size: size,
            ),
          ),
        ),
      ),
    );
  }
}
