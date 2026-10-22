import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../core/prefs.dart';
import 'theme.dart';

/// Optional password lock for the app settings on a device (e.g. a guest room
/// TV). Only the SHA-256 of the password is kept in the code, since the
/// source is public.
class SettingsLock {
  static const _hash =
      '2e5bac908bd740b5ddded3371ed1975f89e06d550f0db2c8e0fd9b10ac9218e8';

  /// Unlocked with the password during this run of the app.
  static bool get unlockedThisRun => changes.value;
  static set unlockedThisRun(bool v) => changes.value = v;

  /// Notifies screens when the lock state changes.
  static final ValueNotifier<bool> changes = ValueNotifier(false);

  static bool check(String password) =>
      sha256.convert(utf8.encode(password.trim())).toString() == _hash;

  static bool isLocked(Prefs prefs) => prefs.settingsLocked && !unlockedThisRun;

  /// Returns true if changes are allowed, asking for the password if needed.
  static Future<bool> ensureUnlocked(BuildContext context, Prefs prefs) async {
    if (!isLocked(prefs)) return true;
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => const _PasswordDialog(),
    );
    return ok ?? false;
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();
  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  void _submit() {
    if (SettingsLock.check(_ctrl.text)) {
      SettingsLock.unlockedThisRun = true;
      Navigator.pop(context, true);
    } else {
      setState(() => _error = 'Şifre yanlış');
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Row(
        children: [
          Icon(Icons.lock_rounded),
          SizedBox(width: 10),
          Text('Ayarlar kilitli'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Değişiklik yapmak için şifreyi gir.',
            style: TextStyle(color: AppColors.textDim),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            autofocus: true,
            obscureText: true,
            decoration: InputDecoration(
              hintText: 'Şifre',
              errorText: _error,
              prefixIcon: const Icon(Icons.key_rounded),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Kilidi aç')),
      ],
    );
  }
}
