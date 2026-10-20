import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'server_setup_screen.dart';

const profileColors = [
  '#8B5CF6',
  '#EC4899',
  '#EF4444',
  '#F59E0B',
  '#10B981',
  '#06B6D4',
  '#3B82F6',
  '#6366F1',
  '#84CC16',
  '#F97316',
];
const profileAvatars = [
  '😀',
  '😎',
  '🤩',
  '🥳',
  '😺',
  '🐶',
  '🦊',
  '🐼',
  '🐯',
  '🦁',
  '🐸',
  '🐵',
  '🦄',
  '🐙',
  '👾',
  '🤖',
  '👻',
  '🎃',
  '⚽',
  '🎮',
  '🎬',
  '🍿',
  '🚀',
  '⭐',
  '🌈',
  '🔥',
  '💎',
  '🎧',
  '👑',
  '🧸',
];

/// "Kim izliyor?" profile picker.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _manage = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final profiles = state.profiles;
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: AnimatedBackdrop()),
          Positioned(top: 24, left: 32, child: const BrandLogo(size: 24)),
          Positioned(
            top: 18,
            right: 24,
            child: TextButton.icon(
              onPressed: state.showServerSetup,
              icon: const Icon(Icons.dns_rounded, size: 18),
              label: Text(
                state.server?.name.isNotEmpty == true
                    ? state.server!.name
                    : 'Sunucu',
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _manage
                        ? 'Profilleri Yönet'
                        : (profiles.isEmpty ? 'Hoş geldin!' : 'Kim izliyor?'),
                    style: const TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),
                  if (profiles.isEmpty) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'Başlamak için bir profil oluştur. Herkesin izleme geçmişi ve önerileri ayrı tutulur.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textDim, fontSize: 16),
                    ),
                  ],
                  const SizedBox(height: 40),
                  Wrap(
                    spacing: 28,
                    runSpacing: 28,
                    alignment: WrapAlignment.center,
                    children: [
                      for (var i = 0; i < profiles.length; i++)
                        _ProfileTile(
                          autofocus: i == 0,
                          name: profiles[i].name,
                          color: parseHexColor(profiles[i].color),
                          avatar: profiles[i].avatar,
                          editing: _manage,
                          onTap: () => _manage
                              ? _edit(profiles[i])
                              : state.selectProfile(profiles[i]),
                        ),
                      _ProfileTile(
                        autofocus: profiles.isEmpty,
                        name: 'Profil Ekle',
                        color: AppColors.surface3,
                        icon: Icons.add_rounded,
                        onTap: () => _edit(null),
                      ),
                    ],
                  ),
                  const SizedBox(height: 48),
                  if (profiles.isNotEmpty)
                    PillButton(
                      label: _manage ? 'Bitti' : 'Profilleri Yönet',
                      icon: _manage ? Icons.check_rounded : Icons.edit_rounded,
                      onPressed: () => setState(() => _manage = !_manage),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(Profile? p) async {
    await showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => ProfileEditDialog(profile: p),
    );
  }
}

class _ProfileTile extends StatefulWidget {
  final String name;
  final Color color;
  final String? avatar;
  final IconData? icon;
  final bool editing;
  final bool autofocus;
  final VoidCallback onTap;
  const _ProfileTile({
    required this.name,
    required this.color,
    required this.onTap,
    this.avatar,
    this.icon,
    this.editing = false,
    this.autofocus = false,
  });
  @override
  State<_ProfileTile> createState() => _ProfileTileState();
}

class _ProfileTileState extends State<_ProfileTile> {
  bool _active = false;
  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(child: _buildTile(context));
  }

  Widget _buildTile(BuildContext context) {
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: (v) => setState(() => _active = v),
      onShowFocusHighlight: (v) => setState(() => _active = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => widget.onTap(),
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _active ? 1.08 : 1,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: widget.icon != null
                      ? null
                      : LinearGradient(
                          colors: [
                            widget.color,
                            Color.lerp(widget.color, Colors.black, 0.45)!,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  color: widget.icon != null ? widget.color : null,
                  border: Border.all(
                    color: _active ? Colors.white : Colors.transparent,
                    width: 3,
                  ),
                  boxShadow: _active
                      ? [
                          BoxShadow(
                            color: widget.color.withValues(alpha: 0.5),
                            blurRadius: 30,
                          ),
                        ]
                      : const [],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (widget.icon != null)
                      Icon(widget.icon, size: 64, color: AppColors.textDim)
                    else
                      Text(
                        widget.avatar?.isNotEmpty == true
                            ? widget.avatar!
                            : (widget.name.isNotEmpty
                                  ? widget.name.characters.first.toUpperCase()
                                  : '?'),
                        style: const TextStyle(
                          fontSize: 68,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    if (widget.editing)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: const Center(
                          child: Icon(Icons.edit_rounded, size: 44),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: 160,
                child: Text(
                  widget.name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    color: _active ? Colors.white : AppColors.textDim,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfileEditDialog extends StatefulWidget {
  final Profile? profile;
  const ProfileEditDialog({super.key, this.profile});
  @override
  State<ProfileEditDialog> createState() => _ProfileEditDialogState();
}

class _ProfileEditDialogState extends State<ProfileEditDialog> {
  late final _name = TextEditingController(text: widget.profile?.name ?? '');
  late String _color = widget.profile?.color.isNotEmpty == true
      ? widget.profile!.color
      : profileColors[DateTime.now().millisecond % profileColors.length];
  late String _avatar =
      widget.profile?.avatar ?? profileAvatars[DateTime.now().second % 10];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Bir isim yaz.');
      return;
    }
    setState(() => _busy = true);
    final state = context.read<AppState>();
    try {
      if (widget.profile == null) {
        await state.api!.createProfile(name, _color, _avatar);
      } else {
        await state.api!.updateProfile(
          widget.profile!.id,
          name,
          _color,
          _avatar,
        );
      }
      await state.refreshProfiles();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Profil silinsin mi?'),
        content: Text(
          '"${widget.profile!.name}" profili ve izleme geçmişi silinecek. Filmler silinmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final state = context.read<AppState>();
    try {
      await state.api!.deleteProfile(widget.profile!.id);
      await state.refreshProfiles();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = parseHexColor(_color);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.profile == null ? 'Yeni Profil' : 'Profili Düzenle',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        colors: [color, Color.lerp(color, Colors.black, 0.45)!],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(_avatar, style: const TextStyle(fontSize: 50)),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: TextField(
                      controller: _name,
                      autofocus: true,
                      maxLength: 24,
                      decoration: const InputDecoration(
                        hintText: 'İsim',
                        counterText: '',
                      ),
                      onSubmitted: (_) => _save(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Renk', style: TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in profileColors)
                    GestureDetector(
                      onTap: () => setState(() => _color = c),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: parseHexColor(c),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _color == c
                                  ? Colors.white
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              const Text('Simge', style: TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final a in profileAvatars)
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() => _avatar = a),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _avatar == a
                              ? AppColors.surface3
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _avatar == a
                                ? AppColors.accent
                                : Colors.transparent,
                          ),
                        ),
                        child: Text(a, style: const TextStyle(fontSize: 24)),
                      ),
                    ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.danger)),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  if (widget.profile != null)
                    TextButton.icon(
                      onPressed: _busy ? null : _delete,
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.danger,
                      ),
                      label: const Text(
                        'Sil',
                        style: TextStyle(color: AppColors.danger),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Vazgeç'),
                  ),
                  const SizedBox(width: 8),
                  PillButton(
                    primary: true,
                    label: _busy ? 'Kaydediliyor…' : 'Kaydet',
                    height: 42,
                    onPressed: _busy ? null : _save,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
