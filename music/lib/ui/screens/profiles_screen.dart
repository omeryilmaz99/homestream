import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models.dart';
import '../../state/app_state.dart';
import '../neu.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'home_screen.dart' show ProfileAvatar, parseHex;

const profileColors = [
  '#1DB954',
  '#E50914',
  '#3B82F6',
  '#F59E0B',
  '#8B5CF6',
  '#EC4899',
  '#14B8A6',
  '#EF4444',
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
  '🎧',
  '🎸',
  '🎹',
  '🎤',
];

/// "Kim dinliyor?": no passwords, "Beni hatırla" skips this next time.
class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});
  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  bool _remember = true;
  String? _opening;

  Future<void> _open(Profile p) async {
    if (_opening != null) return;
    setState(() => _opening = p.id);
    await context.read<AppState>().selectProfile(p, remember: _remember);
    if (mounted) setState(() => _opening = null);
  }

  Future<void> _create() async {
    final p = await showDialog<Profile>(
      context: context,
      builder: (_) => const _NewProfileDialog(),
    );
    if (p != null && mounted) {
      await context.read<AppState>().refreshProfiles();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final profiles = app.profiles;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: app.refreshProfiles,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 30),
            children: [
              const Text(
                'Kim dinliyor?',
                style: T.h1,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                app.server?.name ?? '',
                style: T.dim,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 26,
                runSpacing: 26,
                children: [
                  for (var i = 0; i < profiles.length; i++)
                    FadeSlideIn(
                      index: i,
                      child: _ProfileItem(
                        profile: profiles[i],
                        busy: _opening == profiles[i].id,
                        onTap: () => _open(profiles[i]),
                      ),
                    ),
                  FadeSlideIn(
                    index: profiles.length,
                    child: SizedBox(
                      width: 104,
                      child: Column(
                        children: [
                          NeuButton(
                            circle: true,
                            width: 92,
                            height: 92,
                            onTap: app.online ? _create : null,
                            child: const Icon(
                              Icons.add_rounded,
                              size: 40,
                              color: C.textDim,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text('Yeni profil', style: T.dim),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 36),
              Center(
                child: NeuBox(
                  radius: 18,
                  depth: 0.6,
                  padding: const EdgeInsets.fromLTRB(18, 6, 8, 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.bookmark_added_outlined,
                        color: C.textDim,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Beni hatırla', style: T.h3),
                          Text('Her açılışta sorulmaz', style: T.faint),
                        ],
                      ),
                      const SizedBox(width: 14),
                      Switch(
                        value: _remember,
                        onChanged: (v) => setState(() => _remember = v),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),
              Center(
                child: TextButton.icon(
                  onPressed: app.openSetup,
                  icon: const Icon(Icons.dns_outlined, size: 18),
                  label: const Text('Sunucuyu değiştir'),
                  style: TextButton.styleFrom(foregroundColor: C.textDim),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileItem extends StatelessWidget {
  final Profile profile;
  final bool busy;
  final VoidCallback onTap;
  const _ProfileItem({
    required this.profile,
    required this.busy,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      child: Column(
        children: [
          NeuButton(
            circle: true,
            width: 92,
            height: 92,
            padding: const EdgeInsets.all(7),
            onTap: onTap,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ProfileAvatar(profile: profile, size: 78),
                if (busy)
                  const SizedBox(
                    width: 78,
                    height: 78,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            profile.name,
            style: T.h3,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _NewProfileDialog extends StatefulWidget {
  const _NewProfileDialog();
  @override
  State<_NewProfileDialog> createState() => _NewProfileDialogState();
}

class _NewProfileDialogState extends State<_NewProfileDialog> {
  final _name = TextEditingController();
  String _color =
      profileColors[DateTime.now().millisecond % profileColors.length];
  String _avatar =
      profileAvatars[DateTime.now().second % profileAvatars.length];
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Bir ad yaz');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final app = context.read<AppState>();
    final p = await app.call(
      (a) => a.createProfile(name, _color, _avatar),
      quiet: true,
    );
    if (!mounted) return;
    if (p == null) {
      setState(() {
        _saving = false;
        _error = 'Profil oluşturulamadı';
      });
      return;
    }
    Navigator.pop(context, p);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Yeni profil'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ProfileAvatar(
              profile: Profile(
                id: '',
                name: _name.text,
                color: _color,
                avatar: _avatar,
              ),
              size: 80,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 30,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: 'Ad',
                counterText: '',
                errorText: _error,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in profileColors)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: parseHex(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color == c
                              ? Colors.white
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final a in profileAvatars)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _avatar = a),
                    child: Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _avatar == a ? C.bgDeep : null,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(a, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Oluştur'),
        ),
      ],
    );
  }
}
