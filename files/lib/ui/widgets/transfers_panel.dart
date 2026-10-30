import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/platform.dart';
import '../../core/transfers.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'common.dart';

/// Summary strip at the bottom of the transfer screen; tap to open the queue.
class TransferDock extends StatelessWidget {
  final VoidCallback onOpen;
  const TransferDock({super.key, required this.onOpen});
  @override
  Widget build(BuildContext context) {
    final tm = context.watch<AppState>().transfers;
    final active = tm.activeCount;
    final failed = tm.tasks.where((t) => t.state == TransferState.failed).length;
    if (active == 0 && failed == 0 && tm.tasks.isEmpty) {
      return const SizedBox.shrink();
    }
    final total = tm.totalBytes, done = tm.doneBytes;
    final pct = total <= 0 ? 0.0 : done / total;
    final eta = tm.eta;
    final waiting = tm.tasks.where((t) => t.state == TransferState.waiting).length;
    String title;
    if (active > 0) {
      title = !tm.online || waiting == active
          ? 'Bağlantı bekleniyor · $active aktarım'
          : '$active aktarım · ${formatSpeed(tm.speed)}${eta != null ? ' · ${formatDuration(eta)} kaldı' : ''}';
    } else if (failed > 0) {
      title = '$failed aktarım başarısız';
    } else {
      title = 'Aktarımlar tamamlandı';
    }
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      radius: 18,
      onTap: onOpen,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: failed > 0 && active == 0 ? null : C.gradient,
              color: failed > 0 && active == 0 ? C.danger : null,
              shape: BoxShape.circle,
            ),
            child: Icon(
              active > 0
                  ? Icons.swap_vert_rounded
                  : (failed > 0 ? Icons.error_outline_rounded : Icons.done_all_rounded),
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, color: C.ink)),
                if (active > 0) ...[
                  const SizedBox(height: 6),
                  Bar(value: pct, height: 5),
                  const SizedBox(height: 4),
                  Text('${formatBytes(done)} / ${formatBytes(total)}', style: const TextStyle(fontSize: 11.5, color: C.muted)),
                ],
              ],
            ),
          ),
          if (active > 0)
            IconButton(
              tooltip: 'Tümünü duraklat',
              onPressed: tm.pauseAll,
              icon: const Icon(Icons.pause_rounded, color: C.teal),
            )
          else if (failed > 0 || tm.tasks.any((t) => t.state == TransferState.paused))
            IconButton(
              tooltip: 'Devam et / tekrar dene',
              onPressed: tm.resumeAll,
              icon: const Icon(Icons.play_arrow_rounded, color: C.teal),
            ),
          const Icon(Icons.keyboard_arrow_up_rounded, color: C.muted),
        ],
      ),
    );
  }
}

Future<void> showTransfers(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  constraints: const BoxConstraints(maxWidth: 760),
  builder: (_) => const FractionallySizedBox(heightFactor: 0.82, child: TransfersList()),
);

class TransfersList extends StatelessWidget {
  final bool showHeader;
  const TransfersList({super.key, this.showHeader = true});

  @override
  Widget build(BuildContext context) {
    final tm = context.watch<AppState>().transfers;
    final list = [...tm.tasks]..sort((a, b) => _rank(a).compareTo(_rank(b)));
    return Column(
      children: [
        if (showHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Aktarımlar', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: C.ink)),
                ),
                if (tm.hasActive)
                  TextButton.icon(onPressed: tm.pauseAll, icon: const Icon(Icons.pause_rounded), label: const Text('Duraklat')),
                if (tm.tasks.any((t) => t.state == TransferState.paused || t.state == TransferState.failed))
                  TextButton.icon(onPressed: tm.resumeAll, icon: const Icon(Icons.play_arrow_rounded), label: const Text('Devam')),
                PopupMenuButton<String>(
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'clear', child: Text('Bitenleri temizle')),
                    PopupMenuItem(value: 'cancel', child: Text('Tümünü iptal et')),
                  ],
                  onSelected: (v) async {
                    if (v == 'clear') tm.clearFinished();
                    if (v == 'cancel' &&
                        await confirm(context, title: 'Tüm aktarımlar iptal edilsin mi?', ok: 'İptal et', danger: true)) {
                      tm.cancelAll();
                    }
                  },
                ),
              ],
            ),
          ),
        Expanded(
          child: list.isEmpty
              ? const EmptyState(
                  icon: Icons.swap_vert_rounded,
                  title: 'Aktarım yok',
                  text: 'Gönderdiğin ve indirdiğin dosyalar burada görünür.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (_, i) => _TaskTile(task: list[i], tm: tm),
                ),
        ),
      ],
    );
  }

  static int _rank(TransferTask t) => switch (t.state) {
    TransferState.running || TransferState.verifying => 0,
    TransferState.waiting => 1,
    TransferState.failed => 2,
    TransferState.queued => 3,
    TransferState.paused => 4,
    _ => 5,
  };
}

class _TaskTile extends StatelessWidget {
  final TransferTask task;
  final TransferManager tm;
  const _TaskTile({required this.task, required this.tm});

  @override
  Widget build(BuildContext context) {
    final t = task;
    final up = t.kind == TransferKind.upload;
    final (String status, Color color) = switch (t.state) {
      TransferState.queued => ('Sırada', C.muted),
      TransferState.running => (
        '${formatBytes(t.done)} / ${formatBytes(t.size)} · ${formatSpeed(t.speed)}',
        C.teal,
      ),
      TransferState.waiting => (t.error ?? 'Bağlantı bekleniyor', C.warn),
      TransferState.paused => ('Duraklatıldı · ${formatBytes(t.done)} / ${formatBytes(t.size)}', C.muted),
      TransferState.verifying => ('Doğrulanıyor…', C.blue),
      TransferState.done => ('Tamamlandı · ${formatBytes(t.size)}', C.ok),
      TransferState.failed => (t.error ?? 'Başarısız', C.danger),
      TransferState.canceled => ('İptal edildi', C.muted),
      TransferState.skipped => ('Atlandı (zaten vardı)', C.muted),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6FAFB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: kindColor(kindOf(t.name)).withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(kindIcon(kindOf(t.name)), color: kindColor(kindOf(t.name)), size: 20),
              ),
              Positioned(
                right: -4,
                bottom: -4,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: up ? C.teal : C.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 11, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, color: C.ink, fontSize: 13.5)),
                Text(
                  up ? '→ ${t.remotePath}' : '→ ${t.localPath}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: C.muted),
                ),
                const SizedBox(height: 5),
                if (t.state == TransferState.running || t.state == TransferState.paused || t.state == TransferState.waiting)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Bar(value: t.progress, height: 4, color: t.state == TransferState.running ? null : C.faint),
                  ),
                Text(status, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: color)),
              ],
            ),
          ),
          ..._buttons(context),
        ],
      ),
    );
  }

  List<Widget> _buttons(BuildContext context) {
    final t = task;
    Widget b(IconData i, String tip, VoidCallback on, {Color color = C.teal}) => IconButton(
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      onPressed: on,
      icon: Icon(i, color: color, size: 20),
    );
    switch (t.state) {
      case TransferState.running || TransferState.queued || TransferState.waiting || TransferState.verifying:
        return [
          b(Icons.pause_rounded, 'Duraklat', () => tm.pause(t)),
          b(Icons.close_rounded, 'İptal', () => tm.cancel(t), color: C.muted),
        ];
      case TransferState.paused:
        return [
          b(Icons.play_arrow_rounded, 'Devam et', () => tm.resume(t)),
          b(Icons.close_rounded, 'İptal', () => tm.cancel(t), color: C.muted),
        ];
      case TransferState.failed:
        return [
          b(Icons.refresh_rounded, 'Tekrar dene', () => tm.resume(t)),
          b(Icons.close_rounded, 'Kaldır', () => tm.cancel(t), color: C.muted),
        ];
      case TransferState.done:
        if (t.kind == TransferKind.download) {
          return [
            b(Icons.open_in_new_rounded, 'Aç', () async {
              final err = await AppPlatform.openFile(t.localPath);
              if (err != null && context.mounted) toast(context, err, error: true);
            }),
          ];
        }
        return [];
      default:
        return [];
    }
  }
}
