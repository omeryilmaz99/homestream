import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/platform.dart';
import '../../state/app_state.dart';
import '../../state/pane.dart';
import '../item_actions.dart';
import '../theme.dart';
import 'common.dart';

class DragPayload {
  final PaneController from;
  final List<FileItem> items;
  DragPayload(this.from, this.items);
}

/// What a pane asks of the screen around it.
abstract class PaneHost {
  Future<void> send(PaneController from, List<FileItem> items, {String? intoDir});
  Future<void> osDrop(PaneController to, List<String> paths, {String? intoDir});
  void openFile(PaneController c, FileItem e);
  bool canPaste(PaneController c);
  void clip(PaneController c, List<FileItem> items, {required bool cut});
  Future<void> paste(PaneController c, {String? intoDir});
}

class FilePane extends StatefulWidget {
  final PaneController c;
  final PaneHost host;
  final bool compact;
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? headerAction;
  const FilePane({
    super.key,
    required this.c,
    required this.host,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.compact = false,
    this.headerAction,
  });

  @override
  State<FilePane> createState() => _FilePaneState();
}

class _FilePaneState extends State<FilePane> {
  final _focus = FocusNode();
  final _filter = TextEditingController();
  final _scroll = ScrollController();
  bool _dropHover = false;
  bool _editPath = false;
  late final _pathCtl = TextEditingController();

  PaneController get c => widget.c;
  bool get desktop => AppPlatform.isDesktop && !widget.compact;
  bool get selectMode => widget.compact && c.selected.isNotEmpty;

  @override
  void dispose() {
    _focus.dispose();
    _filter.dispose();
    _scroll.dispose();
    _pathCtl.dispose();
    super.dispose();
  }

  bool get _ctrl =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;
  bool get _shift => HardwareKeyboard.instance.isShiftPressed;

  void _open(FileItem e) {
    if (e.isDir) {
      c.open(e.path);
      _filter.clear();
    } else {
      widget.host.openFile(c, e);
    }
  }

  void _tap(FileItem e) {
    _focus.requestFocus();
    if (widget.compact || !AppPlatform.isDesktop) {
      if (c.selected.isNotEmpty) {
        c.toggle(e);
      } else {
        _open(e);
      }
      return;
    }
    c.tap(e, ctrl: _ctrl, shift: _shift);
  }

  List<FileItem> _targets(FileItem? e) {
    if (e == null) return c.selection;
    if (c.isSelected(e)) return c.selection;
    return [e];
  }

  Future<void> _menu(FileItem? e, Offset pos) async {
    if (e != null && !c.isSelected(e)) c.tap(e);
    final sel = _targets(e);
    final one = sel.length == 1 ? sel.first : null;
    final remote = c.remote;
    PopupMenuItem<String> item(String v, IconData i, String t, {bool danger = false, bool enabled = true}) =>
        PopupMenuItem(
          value: v,
          enabled: enabled,
          height: 42,
          child: Row(
            children: [
              Icon(i, size: 20, color: danger ? C.danger : C.text),
              const SizedBox(width: 12),
              Text(t, style: TextStyle(color: danger ? C.danger : null)),
            ],
          ),
        );
    final entries = <PopupMenuEntry<String>>[
      if (one != null) item('open', one.isDir ? Icons.folder_open_rounded : Icons.open_in_new_rounded, one.isDir ? 'Aç' : (remote ? 'Aç / Önizle' : 'Aç')),
      if (sel.isNotEmpty)
        item(
          'send',
          remote ? Icons.download_rounded : Icons.upload_rounded,
          remote ? 'Bu cihaza indir' : 'Sunucuya gönder',
        ),
      if (one != null) item('rename', Icons.drive_file_rename_outline_rounded, 'Yeniden adlandır'),
      if (remote && sel.isNotEmpty) ...[
        item('copy', Icons.copy_rounded, 'Kopyala'),
        item('cut', Icons.content_cut_rounded, 'Kes (taşı)'),
      ],
      if (remote && widget.host.canPaste(c))
        item('paste', Icons.content_paste_rounded, one != null && one.isDir ? 'Bu klasöre yapıştır' : 'Buraya yapıştır'),
      if (one != null && one.isDir)
        item(
          'bookmark',
          c.isBookmarked(one.path) ? Icons.bookmark_remove_rounded : Icons.bookmark_add_rounded,
          c.isBookmarked(one.path) ? 'Yer iminden çıkar' : 'Yer imlerine ekle',
        ),
      if (!remote && one != null && AppPlatform.isDesktop)
        item('reveal', Icons.folder_rounded, 'Klasörde göster'),
      if (one != null) item('props', Icons.info_outline_rounded, 'Özellikler'),
      if (sel.isEmpty) ...[
        item('mkdir', Icons.create_new_folder_rounded, 'Yeni klasör'),
        item('refresh', Icons.refresh_rounded, 'Yenile'),
        item('all', Icons.select_all_rounded, 'Tümünü seç'),
      ],
      if (sel.isNotEmpty) ...[
        const PopupMenuDivider(),
        item('delete', Icons.delete_outline_rounded, remote ? 'Çöp kutusuna taşı' : 'Sil', danger: true),
        if (remote) item('purge', Icons.delete_forever_rounded, 'Kalıcı sil', danger: true),
      ],
    ];
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: entries,
    );
    if (v == null || !mounted) return;
    _action(v, sel, one);
  }

  void _action(String v, List<FileItem> sel, FileItem? one) {
    switch (v) {
      case 'open':
        if (one != null) _open(one);
      case 'send':
        widget.host.send(c, sel);
      case 'rename':
        if (one != null) doRename(context, c, one);
      case 'copy':
        widget.host.clip(c, sel, cut: false);
      case 'cut':
        widget.host.clip(c, sel, cut: true);
      case 'paste':
        widget.host.paste(c, intoDir: one != null && one.isDir ? one.path : null);
      case 'bookmark':
        if (one != null) c.toggleBookmark(one.path);
      case 'reveal':
        if (one != null) AppPlatform.reveal(one.path);
      case 'props':
        if (one != null) showProperties(context, c, one);
      case 'mkdir':
        doMkdir(context, c);
      case 'refresh':
        c.refresh();
      case 'all':
        c.selectAll();
      case 'delete':
        doDelete(context, c, sel);
      case 'purge':
        doDelete(context, c, sel, permanent: true);
    }
  }

  Map<ShortcutActivator, VoidCallback> get _keys => {
    const SingleActivator(LogicalKeyboardKey.f5): c.refresh,
    const SingleActivator(LogicalKeyboardKey.keyR, control: true): c.refresh,
    const SingleActivator(LogicalKeyboardKey.backspace): c.up,
    const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): c.goBack,
    const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): c.goForward,
    const SingleActivator(LogicalKeyboardKey.keyA, control: true): c.selectAll,
    const SingleActivator(LogicalKeyboardKey.escape): c.clearSelection,
    const SingleActivator(LogicalKeyboardKey.delete): () => doDelete(context, c, c.selection),
    const SingleActivator(LogicalKeyboardKey.delete, shift: true): () =>
        doDelete(context, c, c.selection, permanent: true),
    const SingleActivator(LogicalKeyboardKey.f2): () {
      if (c.selection.length == 1) doRename(context, c, c.selection.first);
    },
    const SingleActivator(LogicalKeyboardKey.enter): () {
      if (c.selection.length == 1) _open(c.selection.first);
    },
    const SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true): () => doMkdir(context, c),
    const SingleActivator(LogicalKeyboardKey.keyC, control: true): () {
      if (c.remote && c.selection.isNotEmpty) widget.host.clip(c, c.selection, cut: false);
    },
    const SingleActivator(LogicalKeyboardKey.keyX, control: true): () {
      if (c.remote && c.selection.isNotEmpty) widget.host.clip(c, c.selection, cut: true);
    },
    const SingleActivator(LogicalKeyboardKey.keyV, control: true): () {
      if (c.remote && widget.host.canPaste(c)) widget.host.paste(c);
    },
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        Widget body = _body();
        // files dragged from the other pane
        body = DragTarget<DragPayload>(
          onWillAcceptWithDetails: (d) => d.data.from != c,
          onAcceptWithDetails: (d) => widget.host.send(d.data.from, d.data.items, intoDir: c.path),
          builder: (context, cand, _) => Stack(
            children: [
              body,
              if (cand.isNotEmpty || _dropHover) _dropOverlay(),
            ],
          ),
        );
        if (AppPlatform.isDesktop) {
          body = DropTarget(
            onDragEntered: (_) => setState(() => _dropHover = true),
            onDragExited: (_) => setState(() => _dropHover = false),
            onDragDone: (d) {
              setState(() => _dropHover = false);
              final paths = d.files.map((f) => f.path).where((p) => p.isNotEmpty).toList();
              if (paths.isNotEmpty) widget.host.osDrop(c, paths);
            },
            child: body,
          );
        }
        return CallbackShortcuts(
          bindings: _keys,
          child: Focus(
            focusNode: _focus,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _focus.requestFocus(),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(widget.compact ? 20 : 24),
                  boxShadow: C.shadow(),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    _header(),
                    _pathBar(),
                    if (!widget.compact || c.selected.isEmpty) _toolbar(),
                    if (c.error != null) _errorBox(),
                    Expanded(child: body),
                    _footer(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _dropOverlay() => Positioned.fill(
    child: IgnorePointer(
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: C.teal.withValues(alpha: 0.08),
          border: Border.all(color: C.teal, width: 2),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              gradient: C.button,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              c.remote ? 'Bırak: sunucuya gönder' : 'Bırak: bu cihaza indir',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _header() {
    final pad = widget.compact
        ? const EdgeInsets.fromLTRB(14, 10, 8, 4)
        : const EdgeInsets.fromLTRB(18, 16, 12, 6);
    final sel = c.selected.length;
    if (selectMode) {
      return Padding(
        padding: pad,
        child: Row(
          children: [
            IconButton(onPressed: c.clearSelection, icon: const Icon(Icons.close_rounded)),
            Expanded(
              child: Text(
                '$sel seçili · ${formatBytes(c.selectionSize)}',
                style: const TextStyle(fontWeight: FontWeight.w600, color: C.ink),
              ),
            ),
            IconButton(
              tooltip: 'Tümünü seç',
              onPressed: c.selectAll,
              icon: const Icon(Icons.select_all_rounded, color: C.teal),
            ),
            IconButton(
              tooltip: 'Diğer işlemler',
              onPressed: () {
                final box = context.findRenderObject() as RenderBox?;
                final pos = box == null ? Offset.zero : box.localToGlobal(Offset(box.size.width - 40, 40));
                _menu(null, pos);
              },
              icon: const Icon(Icons.more_vert_rounded),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: pad,
      child: Row(
        children: [
          Container(
            width: widget.compact ? 34 : 40,
            height: widget.compact ? 34 : 40,
            decoration: BoxDecoration(
              gradient: c.remote ? C.gradient : C.gradientSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(widget.icon, color: Colors.white, size: widget.compact ? 18 : 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: widget.compact ? 15 : 16.5,
                    fontWeight: FontWeight.w700,
                    color: C.ink,
                  ),
                ),
                Text(
                  c.total > 0
                      ? '${formatBytes(c.free)} boş / ${formatBytes(c.total)}'
                      : widget.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: C.muted),
                ),
              ],
            ),
          ),
          _placesButton(),
          ?widget.headerAction,
        ],
      ),
    );
  }

  Widget _placesButton() {
    final bm = c.bookmarks;
    return PopupMenuButton<String>(
      tooltip: 'Konumlar',
      icon: const Icon(Icons.bookmarks_rounded, color: C.teal),
      onOpened: c.loadPlaces,
      itemBuilder: (_) => [
        for (final p in c.places)
          PopupMenuItem(
            value: p.path,
            enabled: p.available,
            child: Row(
              children: [
                Icon(p.icon, size: 20, color: C.teal),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (p.total > 0)
                        Text(
                          '${formatBytes(p.free)} boş',
                          style: const TextStyle(fontSize: 11.5, color: C.muted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (bm.isNotEmpty) const PopupMenuDivider(),
        for (final b in bm)
          PopupMenuItem(
            value: b,
            child: Row(
              children: [
                const Icon(Icons.bookmark_rounded, size: 20, color: C.blue),
                const SizedBox(width: 12),
                Expanded(child: Text(c.baseName(b), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        if (c.path != null) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: '__bm',
            child: Row(
              children: [
                Icon(
                  c.isBookmarked(c.path!) ? Icons.bookmark_remove_rounded : Icons.bookmark_add_rounded,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(c.isBookmarked(c.path!) ? 'Bu klasörü yer iminden çıkar' : 'Bu klasörü yer imlerine ekle'),
              ],
            ),
          ),
        ],
      ],
      onSelected: (v) {
        if (v == '__bm') {
          c.toggleBookmark(c.path!);
        } else {
          c.open(v);
        }
      },
    );
  }

  Widget _pathBar() {
    final crumbs = c.crumbs;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.compact ? 8 : 12, vertical: 2),
      child: Row(
        children: [
          _navBtn(Icons.arrow_back_rounded, 'Geri', c.canBack ? c.goBack : null),
          if (!widget.compact) _navBtn(Icons.arrow_forward_rounded, 'İleri', c.canForward ? c.goForward : null),
          _navBtn(Icons.arrow_upward_rounded, 'Üst klasör', c.parentPath != null ? c.up : null),
          const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F8F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _editPath
                  ? TextField(
                      controller: _pathCtl,
                      autofocus: true,
                      style: const TextStyle(fontSize: 13.5),
                      decoration: const InputDecoration(
                        isDense: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onSubmitted: (v) {
                        setState(() => _editPath = false);
                        if (v.trim().isNotEmpty) c.open(v.trim());
                      },
                      onTapOutside: (_) => setState(() => _editPath = false),
                    )
                  : GestureDetector(
                      onDoubleTap: () {
                        _pathCtl.text = c.path ?? '';
                        setState(() => _editPath = true);
                      },
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        children: [
                          for (var i = crumbs.length - 1; i >= 0; i--) ...[
                            _crumb(crumbs[i].$1, crumbs[i].$2, last: i == crumbs.length - 1),
                            if (i > 0)
                              const Icon(Icons.chevron_right_rounded, size: 16, color: C.faint),
                          ],
                        ],
                      ),
                    ),
            ),
          ),
          if (!widget.compact)
            _navBtn(Icons.edit_location_alt_rounded, 'Yolu yaz', () {
              _pathCtl.text = c.path ?? '';
              setState(() => _editPath = true);
            }),
        ],
      ),
    );
  }

  Widget _crumb(String label, String path, {required bool last}) => Center(
    child: DragTarget<DragPayload>(
      onWillAcceptWithDetails: (d) => d.data.from != c,
      onAcceptWithDetails: (d) => widget.host.send(d.data.from, d.data.items, intoDir: path),
      builder: (_, cand, _) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: last ? null : () => c.open(path),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: cand.isNotEmpty
              ? BoxDecoration(color: C.tint, borderRadius: BorderRadius.circular(8))
              : null,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: last ? C.ink : C.muted,
              fontWeight: last ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _navBtn(IconData i, String tip, VoidCallback? on) => IconButton(
    tooltip: tip,
    visualDensity: VisualDensity.compact,
    onPressed: on,
    icon: Icon(i, size: 20, color: on == null ? C.faint : C.text),
  );

  Widget _toolbar() {
    final prefs = context.read<AppState>().prefs;
    return Padding(
      padding: EdgeInsets.fromLTRB(widget.compact ? 10 : 14, 4, widget.compact ? 6 : 10, 6),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 38,
              child: TextField(
                controller: _filter,
                onChanged: c.setFilter,
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) c.search(v);
                },
                style: const TextStyle(fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: c.searchQuery != null
                      ? '"${c.searchQuery}" sonuçları'
                      : 'Süz · Enter: alt klasörlerde ara',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: (_filter.text.isNotEmpty || c.searchQuery != null)
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _filter.clear();
                            c.setFilter('');
                            c.clearSearch();
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Yeni klasör',
            onPressed: c.path == null ? null : () => doMkdir(context, c),
            icon: const Icon(Icons.create_new_folder_outlined, color: C.teal),
          ),
          if (!widget.compact)
            IconButton(
              tooltip: 'Yenile (F5)',
              onPressed: c.refresh,
              icon: const Icon(Icons.refresh_rounded, color: C.teal),
            ),
          PopupMenuButton<String>(
            tooltip: 'Görünüm',
            icon: const Icon(Icons.tune_rounded, color: C.teal),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(value: 'name', checked: prefs.sortBy == 'name', child: const Text('Ada göre')),
              CheckedPopupMenuItem(value: 'date', checked: prefs.sortBy == 'date', child: const Text('Tarihe göre')),
              CheckedPopupMenuItem(value: 'size', checked: prefs.sortBy == 'size', child: const Text('Boyuta göre')),
              CheckedPopupMenuItem(value: 'type', checked: prefs.sortBy == 'type', child: const Text('Türe göre')),
              const PopupMenuDivider(),
              CheckedPopupMenuItem(value: 'desc', checked: !prefs.sortAsc, child: const Text('Ters sırala')),
              CheckedPopupMenuItem(value: 'grid', checked: prefs.gridView, child: const Text('Izgara görünümü')),
              CheckedPopupMenuItem(value: 'hidden', checked: prefs.showHidden, child: const Text('Gizli dosyaları göster')),
              if (widget.compact) const PopupMenuItem(value: 'refresh', child: Text('Yenile')),
            ],
            onSelected: (v) {
              switch (v) {
                case 'desc':
                  prefs.sortAsc = !prefs.sortAsc;
                case 'grid':
                  prefs.gridView = !prefs.gridView;
                case 'hidden':
                  prefs.showHidden = !prefs.showHidden;
                case 'refresh':
                  c.refresh();
                  return;
                default:
                  prefs.sortBy = v;
              }
              c.resort();
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _errorBox() => Container(
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
    decoration: BoxDecoration(
      color: C.danger.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, color: C.danger, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(c.error!, style: const TextStyle(fontSize: 13))),
        TextButton(onPressed: c.refresh, child: const Text('Tekrar')),
      ],
    ),
  );

  Widget _body() {
    if (c.path == null && c.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (c.path == null) {
      return EmptyState(
        icon: Icons.folder_off_rounded,
        title: 'Klasör açılamadı',
        action: TextButton(onPressed: c.init, child: const Text('Tekrar dene')),
      );
    }
    final items = c.items;
    final grid = context.read<AppState>().prefs.gridView;
    Widget list;
    if (items.isEmpty && !c.loading) {
      list = ListView(
        children: [
          const SizedBox(height: 40),
          EmptyState(
            icon: c.searchQuery != null ? Icons.search_off_rounded : Icons.folder_open_rounded,
            title: c.searchQuery != null
                ? 'Sonuç yok'
                : (c.filter.isNotEmpty ? 'Eşleşen yok' : 'Klasör boş'),
            text: c.searchQuery == null && c.filter.isEmpty
                ? (AppPlatform.isDesktop
                      ? 'Dosyaları buraya sürükleyip bırakabilirsin.'
                      : null)
                : null,
          ),
        ],
      );
    } else if (grid) {
      list = GridView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: widget.compact ? 104 : 124,
          mainAxisExtent: widget.compact ? 112 : 128,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => _wrapItem(items[i], _gridTile(items[i])),
      );
    } else {
      list = ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(6, 0, 6, 16),
        itemCount: items.length,
        itemExtent: widget.compact ? 58 : 56,
        itemBuilder: (_, i) => _wrapItem(items[i], _row(items[i])),
      );
    }
    list = Scrollbar(controller: _scroll, child: list);
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () => c.refresh(quiet: true),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onSecondaryTapDown: (d) {
              c.clearSelection();
              _menu(null, d.globalPosition);
            },
            child: list,
          ),
        ),
        if (c.loading)
          const Positioned(left: 0, right: 0, top: 0, child: LinearProgressIndicator(minHeight: 2)),
      ],
    );
  }

  Widget _wrapItem(FileItem e, Widget child) {
    final sel = c.isSelected(e);
    Widget w = Material(
      color: sel ? C.teal.withValues(alpha: 0.11) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _tap(e),
        onDoubleTap: desktop ? () => _open(e) : null,
        onLongPress: desktop
            ? null
            : () {
                HapticFeedback.selectionClick();
                c.toggle(e);
              },
        onSecondaryTapDown: (d) => _menu(e, d.globalPosition),
        child: child,
      ),
    );
    if (e.isDir) {
      w = DragTarget<DragPayload>(
        onWillAcceptWithDetails: (d) => d.data.from != c,
        onAcceptWithDetails: (d) => widget.host.send(d.data.from, d.data.items, intoDir: e.path),
        builder: (_, cand, _) => cand.isEmpty
            ? w
            : DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: C.teal, width: 2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: w,
              ),
      );
    }
    if (!AppPlatform.isDesktop) return w;
    return Draggable<DragPayload>(
      data: DragPayload(c, sel ? c.selection : [e]),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () {
        if (!sel) c.tap(e);
      },
      feedback: _dragChip(sel ? c.selection.length : 1, e),
      child: w,
    );
  }

  Widget _dragChip(int n, FileItem e) => Material(
    color: Colors.transparent,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: C.button,
        borderRadius: BorderRadius.circular(14),
        boxShadow: C.shadow(2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(kindIcon(e.kind), color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(
            n == 1 ? e.name : '$n öğe',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );

  String? _thumb(FileItem e, int w) =>
      c.remote && canThumb(e.name) ? context.read<AppState>().api?.thumbUrl(e.path, width: w) : null;

  Widget _row(FileItem e) {
    final wide = !widget.compact && MediaQuery.sizeOf(context).width > 1180;
    final sub = e.isDir
        ? (e.count >= 0 ? '${e.count > 10000 ? '10000+' : e.count} öğe' : 'Klasör')
        : formatBytes(e.size);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          if (selectMode)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Checkbox(value: c.isSelected(e), onChanged: (_) => c.toggle(e)),
            ),
          FileIcon(item: e, size: 38, thumbUrl: _thumb(e, 96), localThumb: !c.remote),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: e.hidden ? C.muted : C.ink,
                  ),
                ),
                if (!wide)
                  Text(
                    c.searchQuery != null
                        ? c.baseName(c.parentOf(e.path))
                        : '$sub · ${formatDate(e.mtime)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: C.muted),
                  ),
              ],
            ),
          ),
          if (wide) ...[
            SizedBox(
              width: 90,
              child: Text(sub, textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, color: C.muted)),
            ),
            SizedBox(
              width: 120,
              child: Text(formatDate(e.mtime), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, color: C.muted)),
            ),
          ],
          if (!desktop && !selectMode)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.more_vert_rounded, size: 20, color: C.muted),
              onPressed: () => _sheet(e),
            ),
        ],
      ),
    );
  }

  Widget _gridTile(FileItem e) => Padding(
    padding: const EdgeInsets.all(6),
    child: Column(
      children: [
        Stack(
          children: [
            FileIcon(item: e, size: widget.compact ? 58 : 68, thumbUrl: _thumb(e, 200), localThumb: !c.remote),
            if (selectMode && c.isSelected(e))
              const Positioned(
                right: 0,
                top: 0,
                child: Icon(Icons.check_circle_rounded, color: C.teal, size: 20),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          e.name,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: C.ink, height: 1.2),
        ),
      ],
    ),
  );

  /// Bottom sheet with the item actions (phones).
  Future<void> _sheet(FileItem e) async {
    final remote = c.remote;
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (s) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: FileIcon(item: e, size: 40, thumbUrl: _thumb(e, 96), localThumb: !remote),
              title: Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(e.isDir ? 'Klasör' : '${formatBytes(e.size)} · ${formatDate(e.mtime)}'),
            ),
            const Divider(),
            _st(s, 'send', remote ? Icons.download_rounded : Icons.upload_rounded, remote ? 'Bu cihaza indir' : 'Sunucuya gönder'),
            if (!e.isDir) _st(s, 'open', Icons.open_in_new_rounded, remote ? 'Önizle' : 'Aç'),
            _st(s, 'rename', Icons.drive_file_rename_outline_rounded, 'Yeniden adlandır'),
            if (remote) _st(s, 'copy', Icons.copy_rounded, 'Kopyala'),
            if (remote) _st(s, 'cut', Icons.content_cut_rounded, 'Taşı'),
            if (remote && e.isDir && widget.host.canPaste(c)) _st(s, 'paste', Icons.content_paste_rounded, 'Bu klasöre yapıştır'),
            if (e.isDir)
              _st(s, 'bookmark', Icons.bookmark_add_rounded, c.isBookmarked(e.path) ? 'Yer iminden çıkar' : 'Yer imlerine ekle'),
            _st(s, 'props', Icons.info_outline_rounded, 'Özellikler'),
            _st(s, 'delete', Icons.delete_outline_rounded, remote ? 'Çöp kutusuna taşı' : 'Sil', danger: true),
          ],
        ),
      ),
    );
    if (v != null && mounted) _action(v, [e], e);
  }

  Widget _st(BuildContext s, String v, IconData i, String t, {bool danger = false}) => ListTile(
    dense: true,
    leading: Icon(i, color: danger ? C.danger : C.teal),
    title: Text(t, style: TextStyle(color: danger ? C.danger : C.ink, fontSize: 15)),
    onTap: () => Navigator.pop(s, v),
  );

  Widget _footer() {
    final n = c.items.length;
    final sel = c.selected.length;
    final text = sel > 0
        ? '$sel seçili · ${formatBytes(c.selectionSize)}'
        : '$n öğe${c.searchQuery != null && !c.searchComplete ? ' (ilk sonuçlar)' : ''}';
    return Container(
      padding: EdgeInsets.fromLTRB(16, 6, 8, widget.compact ? 6 : 8),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.line))),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12.5, color: C.muted)),
          ),
          if (!c.writable)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Tooltip(
                message: 'Bu klasöre yazma izni yok',
                child: Icon(Icons.lock_outline_rounded, size: 16, color: C.warn),
              ),
            ),
          if (sel > 0)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: C.teal,
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => widget.host.send(c, c.selection),
              icon: Icon(c.remote ? Icons.download_rounded : Icons.upload_rounded, size: 18),
              label: Text(c.remote ? 'İndir' : 'Gönder'),
            ),
        ],
      ),
    );
  }
}
