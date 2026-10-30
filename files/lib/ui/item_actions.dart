import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/local_fs.dart';
import '../core/models.dart';
import '../core/transfers.dart';
import '../state/app_state.dart';
import '../state/pane.dart';
import 'theme.dart';
import 'widgets/common.dart';

String _err(Object e) => e is ApiException
    ? e.message
    : (e is FileSystemException ? LocalFs.errorText(e) : '$e');

Future<void> doMkdir(BuildContext context, PaneController c) async {
  if (c.path == null) return;
  final name = await prompt(
    context,
    title: 'Yeni klasör',
    initial: 'Yeni klasör',
    ok: 'Oluştur',
    validate: nameError,
  );
  if (name == null || !context.mounted) return;
  try {
    await c.mkdir(name);
  } catch (e) {
    if (context.mounted) toast(context, _err(e), error: true);
  }
}

Future<void> doRename(
  BuildContext context,
  PaneController c,
  FileItem e,
) async {
  final name = await prompt(
    context,
    title: 'Yeniden adlandır',
    initial: e.name,
    validate: nameError,
    selectStem: !e.isDir,
  );
  if (name == null || name == e.name || !context.mounted) return;
  try {
    await c.rename(e, name);
  } catch (err) {
    if (context.mounted) toast(context, _err(err), error: true);
  }
}

Future<void> doDelete(
  BuildContext context,
  PaneController c,
  List<FileItem> items, {
  bool permanent = false,
}) async {
  if (items.isEmpty) return;
  final what = items.length == 1 ? '"${items.first.name}"' : '${items.length} öğe';
  final local = !c.remote;
  final perm = permanent || local;
  final ok = await confirm(
    context,
    title: perm ? '$what kalıcı olarak silinsin mi?' : '$what çöp kutusuna taşınsın mı?',
    text: perm
        ? (local
              ? 'Bu cihazdan silinir${Platform.isAndroid ? '' : ' (Geri Dönüşüm Kutusu\'na gitmez)'}. Bu işlem geri alınamaz.'
              : 'Bu işlem geri alınamaz.')
        : 'Sunucudaki çöp kutusundan geri alabilirsin (Sunucu > Çöp kutusu).',
    ok: perm ? 'Kalıcı sil' : 'Çöpe taşı',
    danger: perm,
  );
  if (!ok || !context.mounted) return;
  final errors = <String>[];
  if (local) {
    for (final e in items) {
      try {
        await LocalFs.delete(e.path);
      } catch (err) {
        errors.add('${e.name}: ${_err(err)}');
      }
    }
  } else {
    final api = context.read<AppState>().api;
    if (api == null) return;
    try {
      final r = await api.delete(
        items.map((e) => e.path).toList(),
        permanent: permanent,
      );
      errors.addAll(r.errors);
      if (r.noTrash.isNotEmpty && context.mounted) {
        final again = await confirm(
          context,
          title: 'Çöp kutusu kullanılamıyor',
          text:
              '${r.noTrash.length} öğe için bu diskte çöp kutusu yok (salt okunur ya da desteklenmeyen disk). Kalıcı olarak silinsin mi?',
          ok: 'Kalıcı sil',
          danger: true,
        );
        if (again) {
          final r2 = await api.delete(r.noTrash, permanent: true);
          errors.addAll(r2.errors);
        }
      }
    } catch (err) {
      errors.add(_err(err));
    }
  }
  await c.refresh(quiet: true);
  if (!context.mounted) return;
  if (errors.isNotEmpty) {
    toast(context, errors.take(3).join('\n'), error: true);
  } else {
    toast(context, perm ? 'Silindi' : 'Çöp kutusuna taşındı');
  }
}

Future<void> showProperties(
  BuildContext context,
  PaneController c,
  FileItem e,
) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _PropsDialog(c: c, item: e),
  );
}

class _PropsDialog extends StatefulWidget {
  final PaneController c;
  final FileItem item;
  const _PropsDialog({required this.c, required this.item});
  @override
  State<_PropsDialog> createState() => _PropsDialogState();
}

class _PropsDialogState extends State<_PropsDialog> {
  int? _size, _files, _dirs;
  bool _complete = true, _loading = false;
  String? _hash;
  bool _hashing = false;

  @override
  void initState() {
    super.initState();
    if (widget.item.isDir) _deep();
  }

  Future<void> _deep() async {
    setState(() => _loading = true);
    try {
      if (widget.c.remote) {
        final j = await context.read<AppState>().api!.stat(
          widget.item.path,
          deep: true,
        );
        _size = (j['size'] as num?)?.toInt();
        _files = (j['files'] as num?)?.toInt();
        _dirs = (j['dirs'] as num?)?.toInt();
        _complete = j['complete'] != false;
      } else {
        final w = await LocalFs.walk(widget.item.path, hidden: true);
        var s = 0;
        for (final f in w.files) {
          try {
            s += f.lengthSync();
          } catch (_) {}
        }
        _size = s;
        _files = w.files.length;
        _dirs = w.dirs.length;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _sha() async {
    setState(() => _hashing = true);
    try {
      _hash = widget.c.remote
          ? await context.read<AppState>().api!.hash(widget.item.path)
          : (await _localSha(widget.item.path));
    } catch (e) {
      _hash = 'Hesaplanamadı: ${_err(e)}';
    }
    if (mounted) setState(() => _hashing = false);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.item;
    Widget row(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(k, style: const TextStyle(color: C.muted)),
          ),
          Expanded(child: SelectableText(v)),
        ],
      ),
    );
    return AlertDialog(
      title: Row(
        children: [
          FileIcon(item: e, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            row('Konum', e.path),
            row('Tür', e.isDir ? 'Klasör' : (e.ext.isEmpty ? 'Dosya' : '${e.ext.toUpperCase()} dosyası')),
            if (!e.isDir) row('Boyut', '${formatBytes(e.size)} (${e.size} bayt)'),
            if (e.isDir)
              row(
                'Boyut',
                _loading
                    ? 'Hesaplanıyor…'
                    : (_size == null
                          ? '-'
                          : '${formatBytes(_size!)}${_complete ? '' : ' (en az)'} · $_files dosya, $_dirs klasör'),
              ),
            row('Değiştirilme', formatDate(e.mtime)),
            if (e.link) row('Kısayol', 'Evet (sembolik bağlantı)'),
            if (!e.isDir)
              row(
                'SHA-256',
                _hash ?? (_hashing ? 'Hesaplanıyor…' : '—'),
              ),
          ],
        ),
      ),
      actions: [
        if (!e.isDir && _hash == null)
          TextButton(
            onPressed: _hashing ? null : _sha,
            child: const Text('Sağlama hesapla'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kapat'),
        ),
      ],
    );
  }
}

Future<String> _localSha(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();

/// Asks what to do with an existing file.
Future<(ConflictChoice, bool)?> askConflict(
  BuildContext context,
  ConflictInfo info,
) {
  final t = info.task;
  final up = t.kind == TransferKind.upload;
  var all = false;
  return showDialog<(ConflictChoice, bool)>(
    context: context,
    barrierDismissible: false,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('Bu dosya zaten var'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '"${t.name}" ${up ? 'sunucuda' : 'bu cihazda'} zaten var.',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              _cmp('Mevcut', info.existingSize, info.existingMtime),
              _cmp(
                'Yeni',
                t.size,
                DateTime.fromMillisecondsSinceEpoch(t.mtime),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: all,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (v) => set(() => all = v ?? false),
                title: const Text('Sonrakiler için de aynısını yap'),
              ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, (ConflictChoice.skip, all)),
            child: const Text('Atla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, (ConflictChoice.rename, all)),
            child: const Text('İkisini de tut'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: C.warn),
            onPressed: () => Navigator.pop(c, (ConflictChoice.overwrite, all)),
            child: const Text('Üzerine yaz'),
          ),
        ],
      ),
    ),
  );
}

Widget _cmp(String label, int size, DateTime? at) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 3),
  child: Row(
    children: [
      SizedBox(
        width: 70,
        child: Text(label, style: const TextStyle(color: C.muted)),
      ),
      Text(formatBytes(size)),
      const SizedBox(width: 12),
      if (at != null)
        Text(formatDate(at), style: const TextStyle(color: C.muted)),
    ],
  ),
);

/// Image / text preview.
Future<void> showPreview(
  BuildContext context,
  PaneController c,
  FileItem e,
) async {
  final app = context.read<AppState>();
  Widget body;
  if (e.kind == FileKind.image && canThumb(e.name)) {
    body = InteractiveViewer(
      maxScale: 6,
      child: c.remote
          ? Image.network(
              app.api!.thumbUrl(e.path, width: 1024),
              fit: BoxFit.contain,
              loadingBuilder: (_, child, p) => p == null
                  ? child
                  : const Center(child: CircularProgressIndicator()),
              errorBuilder: (_, _, _) =>
                  const Center(child: Text('Önizleme yüklenemedi')),
            )
          : Image.file(File(e.path), fit: BoxFit.contain),
    );
  } else {
    body = FutureBuilder<String>(
      future: c.remote
          ? app.api!.readText(e.path)
          : File(e.path)
                .openRead(0, 256 * 1024)
                .fold<List<int>>([], (a, b) => a..addAll(b))
                .then((b) => String.fromCharCodes(b)),
      builder: (_, s) {
        if (s.hasError) return Center(child: Text(_err(s.error!)));
        if (!s.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            s.data!,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        );
      },
    );
  }
  await showDialog<void>(
    context: context,
    builder: (c) => Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 900,
        height: 640,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(c),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(child: Container(color: const Color(0xFFF7FAFB), child: body)),
          ],
        ),
      ),
    ),
  );
}
