import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../core/platform.dart';
import '../../state/app_state.dart';
import '../layout.dart';
import '../settings_lock.dart';
import '../theme.dart';
import '../tv_focus.dart';
import '../widgets/common.dart';
import '../widgets/profile_avatar.dart';
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
    final compact = isCompact(context);
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: AnimatedBackdrop()),
          // header and content in one column so they can never overlap
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 16 : 32,
                    compact ? 8 : 18,
                    compact ? 8 : 24,
                    0,
                  ),
                  child: Row(
                    children: [
                      BrandLogo(size: compact ? 20 : 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () async {
                              if (await SettingsLock.ensureUnlocked(
                                context,
                                state.prefs,
                              )) {
                                state.showServerSetup();
                              }
                            },
                            icon: const Icon(Icons.dns_rounded, size: 18),
                            label: Text(
                              state.server?.name.isNotEmpty == true
                                  ? state.server!.name
                                  : 'Sunucu',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(compact ? 16 : 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _manage
                                ? 'Profilleri Yönet'
                                : (profiles.isEmpty
                                      ? 'Hoş geldin!'
                                      : 'Kim izliyor?'),
                            style: TextStyle(
                              fontSize: compact ? 32 : 44,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1,
                            ),
                          ),
                          if (profiles.isEmpty) ...[
                            const SizedBox(height: 10),
                            const Text(
                              'Başlamak için bir profil oluştur. Herkesin izleme geçmişi ve önerileri ayrı tutulur.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.textDim,
                                fontSize: 16,
                              ),
                            ),
                          ],
                          SizedBox(height: compact ? 28 : 40),
                          Wrap(
                            spacing: compact ? 16 : 28,
                            runSpacing: compact ? 18 : 28,
                            alignment: WrapAlignment.center,
                            children: [
                              for (var i = 0; i < profiles.length; i++)
                                _ProfileTile(
                                  autofocus: i == 0,
                                  name: profiles[i].name,
                                  color: parseHexColor(profiles[i].color),
                                  profile: profiles[i],
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
                                onTap: () async {
                                  if (await SettingsLock.ensureUnlocked(
                                    context,
                                    state.prefs,
                                  )) {
                                    _edit(null);
                                  }
                                },
                              ),
                            ],
                          ),
                          SizedBox(height: compact ? 32 : 48),
                          if (profiles.isNotEmpty)
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              alignment: WrapAlignment.center,
                              children: [
                                if (_manage && profiles.length > 1)
                                  PillButton(
                                    key: const ValueKey('order'),
                                    label: 'Sırayı Değiştir',
                                    icon: Icons.swap_vert_rounded,
                                    onPressed: () => showDialog(
                                      context: context,
                                      barrierColor: Colors.black87,
                                      builder: (_) =>
                                          const ProfileOrderDialog(),
                                    ),
                                  ),
                                PillButton(
                                  key: const ValueKey('manage'),
                                  label: _manage ? 'Bitti' : 'Profilleri Yönet',
                                  icon: _manage
                                      ? Icons.check_rounded
                                      : Icons.edit_rounded,
                                  onPressed: () async {
                                    if (_manage ||
                                        await SettingsLock.ensureUnlocked(
                                          context,
                                          state.prefs,
                                        )) {
                                      setState(() => _manage = !_manage);
                                    }
                                  },
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(Profile? p) async {
    // the lock may have been closed again ("Kilitle") while managing
    if (!await SettingsLock.ensureUnlocked(
      context,
      context.read<AppState>().prefs,
    )) {
      return;
    }
    if (!mounted) return;
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
  final Profile? profile;
  final IconData? icon;
  final bool editing;
  final bool autofocus;
  final VoidCallback onTap;
  const _ProfileTile({
    required this.name,
    required this.color,
    required this.onTap,
    this.profile,
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
    final c = isCompact(context);
    final box = c ? 100.0 : 150.0;
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
                width: box,
                height: box,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(c ? 20 : 28),
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
                  fit: StackFit.expand,
                  children: [
                    if (widget.icon != null)
                      Icon(
                        widget.icon,
                        size: c ? 44 : 64,
                        color: AppColors.textDim,
                      )
                    else
                      ProfileAvatar.of(
                        widget.profile,
                        size: box,
                        radius: c ? 17 : 25,
                      ),
                    if (widget.editing)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(c ? 18 : 26),
                        ),
                        child: const Center(
                          child: Icon(Icons.edit_rounded, size: 44),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: c ? 8 : 14),
              SizedBox(
                width: c ? 110 : 160,
                child: Text(
                  widget.name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: c ? 15 : 18,
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
  // photo: picked bytes wait for "Kaydet"; _removePhoto drops the current one
  Uint8List? _newPhoto;
  bool _removePhoto = false;
  bool _busy = false;
  String? _error;

  bool get _hasPhoto =>
      _newPhoto != null ||
      (!_removePhoto && (widget.profile?.photo.isNotEmpty ?? false));

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final res = await FilePicker.pickFile(
        dialogTitle: 'Profil fotoğrafı seç',
        type: FileType.image,
      );
      if (res == null) return;
      final bytes = await res.xFile.readAsBytes();
      if (bytes.length > 20 * 1024 * 1024) {
        setState(() => _error = 'Fotoğraf çok büyük (en fazla 20 MB).');
        return;
      }
      setState(() {
        _newPhoto = bytes;
        _removePhoto = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Bu cihazda dosya seçilemedi. Fotoğrafı telefondan veya bilgisayardan yükleyebilirsin, tüm cihazlarda görünür.',
        );
      }
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Bir isim yaz.');
      return;
    }
    setState(() => _busy = true);
    final state = context.read<AppState>();
    final api = state.api!;
    try {
      final String id;
      if (widget.profile == null) {
        id = (await api.createProfile(name, _color, _avatar)).id;
      } else {
        id = widget.profile!.id;
        await api.updateProfile(id, name, _color, _avatar);
      }
      if (_newPhoto != null) {
        await api.uploadProfilePhoto(id, _newPhoto!);
      } else if (_removePhoto && widget.profile?.photo.isNotEmpty == true) {
        await api.deleteProfilePhoto(id);
      }
      await state.refreshProfiles();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      // a new profile may exist already even if the photo failed
      await state.refreshProfiles();
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
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
            autofocus: true,
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
    final compact = isCompact(context);
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 40,
        vertical: 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(compact ? 18 : 26),
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
                  ProfileAvatar(
                    name: _name.text,
                    color: _color,
                    avatar: _avatar,
                    photo: _removePhoto ? '' : (widget.profile?.photo ?? ''),
                    localPhoto: _newPhoto,
                    size: compact ? 80 : 96,
                    radius: 20,
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: TextField(
                      controller: _name,
                      autofocus: AppPlatform.isDesktop && !AppPlatform.isPhone,
                      maxLength: 24,
                      decoration: const InputDecoration(
                        hintText: 'İsim',
                        counterText: '',
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _save(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pickPhoto,
                    icon: const Icon(Icons.add_a_photo_rounded, size: 18),
                    label: Text(
                      _hasPhoto ? 'Fotoğrafı değiştir' : 'Fotoğraf yükle',
                    ),
                  ),
                  if (_hasPhoto)
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _newPhoto = null;
                              _removePhoto = true;
                            }),
                      icon: const Icon(Icons.hide_image_outlined, size: 18),
                      label: const Text('Fotoğrafı kaldır'),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              const Text('Renk', style: TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in profileColors)
                    Focusable(
                      onTap: () => setState(() => _color = c),
                      builder: (context, focused) => AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 38,
                        height: 38,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: focused
                                ? AppColors.accent
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: DecoratedBox(
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
              Text(
                _hasPhoto ? 'Simge (fotoğraf yokken görünür)' : 'Simge',
                style: const TextStyle(color: AppColors.textMuted),
              ),
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
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 8,
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
                    )
                  else
                    const SizedBox.shrink(),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
            ],
          ),
        ),
      ),
    );
  }
}

/// Changes the order of the profiles on this device.
class ProfileOrderDialog extends StatefulWidget {
  const ProfileOrderDialog({super.key});
  @override
  State<ProfileOrderDialog> createState() => _ProfileOrderDialogState();
}

class _ProfileOrderDialogState extends State<ProfileOrderDialog> {
  late final List<Profile> _list = [...context.read<AppState>().profiles];
  void _move(int i, int d) {
    final j = i + d;
    if (j < 0 || j >= _list.length) return;
    setState(() {
      final p = _list.removeAt(i);
      _list.insert(j, p);
    });
  }

  void _save() {
    // the order is kept on this device only
    context.read<AppState>().setProfileOrder(_list);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final touch = !AppPlatform.isTv;
    return AlertDialog(
      title: const Text('Profil sırası'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              touch
                  ? 'Okları kullan ya da satırı basılı tutup sürükle. Sıra yalnızca bu cihazda geçerli.'
                  : 'Okları kullanarak profilleri yukarı veya aşağı taşı. Sıra yalnızca bu cihazda geçerli.',
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: _list.length,
                onReorder: (from, to) => setState(() {
                  if (to > from) to--;
                  final p = _list.removeAt(from);
                  _list.insert(to, p);
                }),
                itemBuilder: (context, i) {
                  final p = _list[i];
                  final row = Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 26,
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        ProfileAvatar.of(p, size: 40, radius: 10),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            p.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Yukarı taşı',
                          autofocus: AppPlatform.isTv && i == 0,
                          // never disabled: a disabled button would drop
                          // the remote's focus when the row reaches the end
                          onPressed: () => _move(i, -1),
                          icon: Icon(
                            Icons.arrow_upward_rounded,
                            color: i == 0 ? AppColors.textMuted : null,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Aşağı taşı',
                          onPressed: () => _move(i, 1),
                          icon: Icon(
                            Icons.arrow_downward_rounded,
                            color: i == _list.length - 1
                                ? AppColors.textMuted
                                : null,
                          ),
                        ),
                      ],
                    ),
                  );
                  return touch
                      ? ReorderableDelayedDragStartListener(
                          key: ValueKey(p.id),
                          index: i,
                          child: row,
                        )
                      : KeyedSubtree(key: ValueKey(p.id), child: row);
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(onPressed: _save, child: const Text('Kaydet')),
      ],
    );
  }
}
