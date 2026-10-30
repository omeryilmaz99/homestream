import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/api.dart';
import '../core/format.dart';
import '../core/local_fs.dart';
import '../core/models.dart';
import 'app_state.dart';

/// One side of the transfer screen: this device (local) or the server (remote).
class PaneController extends ChangeNotifier {
  final bool remote;
  final AppState app;
  PaneController({required this.remote, required this.app});

  String? path;
  List<FileItem> _all = [];
  List<FileItem> items = [];
  bool loading = false;
  String? error;
  int free = 0;
  int total = 0;
  bool writable = true;
  List<Place> places = [];
  String home = '';

  final Set<String> selected = {};
  String? _anchor;
  String filter = '';
  final List<String> _back = [];
  final List<String> _fwd = [];

  // server-side search
  String? searchQuery;
  bool searchComplete = true;

  int _gen = 0;
  bool _disposed = false;

  String get key => remote ? 'server.${app.server?.id ?? ''}' : 'local';

  bool get canBack => _back.isNotEmpty;
  bool get canForward => _fwd.isNotEmpty;

  String? get parentPath {
    final p0 = path;
    if (p0 == null) return null;
    if (remote) {
      if (p0 == '/') return null;
      final i = p0.lastIndexOf('/');
      return i <= 0 ? '/' : p0.substring(0, i);
    }
    return LocalFs.parent(p0);
  }

  String join(String dir, String name) {
    if (remote) return dir.endsWith('/') ? '$dir$name' : '$dir/$name';
    return p.join(dir, name);
  }

  String parentOf(String path) {
    if (remote) {
      final i = path.lastIndexOf('/');
      return i <= 0 ? '/' : path.substring(0, i);
    }
    return p.dirname(path);
  }

  String baseName(String path) {
    if (remote) return path == '/' ? '/' : path.split('/').last;
    final b = p.basename(path);
    return b.isEmpty ? path : b;
  }

  /// Breadcrumb parts: (label, path).
  List<(String, String)> get crumbs {
    final p0 = path;
    if (p0 == null) return [];
    final out = <(String, String)>[];
    if (remote) {
      out.add(('/', '/'));
      var acc = '';
      for (final s in p0.split('/').where((s) => s.isNotEmpty)) {
        acc = '$acc/$s';
        out.add((s, acc));
      }
      return out;
    }
    if (Platform.isWindows) {
      final parts = p0.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty);
      var acc = '';
      for (final s in parts) {
        acc = acc.isEmpty ? '$s\\' : p.join(acc, s);
        out.add((s, acc));
      }
      return out;
    }
    out.add(('/', '/'));
    var acc = '';
    for (final s in p0.split('/').where((s) => s.isNotEmpty)) {
      acc = '$acc/$s';
      out.add((s, acc));
    }
    return out;
  }

  Future<void> init() async {
    await loadPlaces();
    final last = app.prefs.lastPath(key);
    await open(last ?? (home.isNotEmpty ? home : (remote ? '/' : LocalFs.home)),
        push: false, fallback: true);
  }

  Future<void> loadPlaces() async {
    try {
      if (remote) {
        final api = app.api;
        if (api == null) return;
        final r = await api.roots();
        home = r.home;
        places = r.places;
      } else {
        home = LocalFs.home;
        places = await LocalFs.places();
      }
      _notify();
    } catch (_) {}
  }

  List<String> get bookmarks => app.prefs.bookmarks(key);
  bool isBookmarked(String p) => bookmarks.contains(p);
  void toggleBookmark(String p) {
    final b = [...bookmarks];
    b.contains(p) ? b.remove(p) : b.add(p);
    app.prefs.setBookmarks(key, b);
    _notify();
  }

  Future<Listing> _list(String dir) async {
    if (remote) {
      final api = app.api;
      if (api == null) throw ApiException('Sunucuya bağlı değil');
      return api.list(dir);
    }
    return LocalFs.list(dir);
  }

  Future<void> open(
    String dir, {
    bool push = true,
    bool fallback = false,
    bool quiet = false,
  }) async {
    final gen = ++_gen;
    if (!quiet) {
      loading = true;
      error = null;
      _notify();
    }
    try {
      final l = await _list(dir);
      if (gen != _gen || _disposed) return;
      if (push && path != null && path != l.path) {
        _back.add(path!);
        if (_back.length > 50) _back.removeAt(0);
        _fwd.clear();
      }
      final changedDir = path != l.path;
      path = l.path;
      _all = l.items;
      free = l.free;
      total = l.total;
      writable = l.writable;
      error = null;
      searchQuery = null;
      if (changedDir) {
        selected.clear();
        filter = '';
      } else {
        selected.removeWhere((n) => !_all.any((e) => e.path == n));
      }
      _apply();
      app.prefs.setLastPath(key, l.path);
      if (remote) app.setWatch({l.path});
    } catch (e) {
      if (gen != _gen || _disposed) return;
      if (fallback) {
        // the last folder is gone (disk removed): go to the start folder
        final start = home.isNotEmpty ? home : (remote ? '/' : LocalFs.home);
        if (dir != start) {
          loading = false;
          return open(start, push: false);
        }
      }
      if (!quiet) {
        error = _errText(e);
        if (path == null || path != dir) {
          // keep showing the old folder; tell what failed
        }
      }
    } finally {
      if (gen == _gen && !_disposed) {
        loading = false;
        _notify();
      }
    }
  }

  String _errText(Object e) {
    if (e is ApiException) return e.message;
    if (e is FileSystemException) {
      if (e.osError?.errorCode == 13 ||
          e.osError?.errorCode == 5 ||
          e.osError?.errorCode == 1) {
        return Platform.isAndroid
            ? 'Bu klasörü açma izni yok. Ayarlardan "Tüm dosyalara erişim" iznini ver.'
            : 'Bu klasörü açma izni yok.';
      }
      return LocalFs.errorText(e);
    }
    return '$e';
  }

  Future<void> refresh({bool quiet = false}) async {
    final p0 = path;
    if (p0 == null) return init();
    if (searchQuery != null) return search(searchQuery!);
    await open(p0, push: false, quiet: quiet);
  }

  Future<void> up() async {
    final par = parentPath;
    if (par != null) await open(par);
  }

  Future<void> goBack() async {
    if (_back.isEmpty) return;
    final cur = path;
    final to = _back.removeLast();
    if (cur != null) _fwd.add(cur);
    await open(to, push: false);
  }

  Future<void> goForward() async {
    if (_fwd.isEmpty) return;
    final cur = path;
    final to = _fwd.removeLast();
    if (cur != null) _back.add(cur);
    await open(to, push: false);
  }

  // ---- search / filter / sort ----

  void setFilter(String v) {
    filter = v;
    _apply();
    _notify();
  }

  Future<void> search(String q) async {
    final dir = path;
    if (dir == null || q.trim().isEmpty) return;
    final gen = ++_gen;
    loading = true;
    error = null;
    searchQuery = q.trim();
    _notify();
    try {
      List<FileItem> results;
      if (remote) {
        final r = await app.api!.search(dir, q.trim());
        results = r.results;
        searchComplete = r.complete;
      } else {
        results = await _localSearch(dir, q.trim());
      }
      if (gen != _gen) return;
      _all = results;
      selected.clear();
      filter = '';
      _apply();
    } catch (e) {
      if (gen == _gen) error = _errText(e);
    } finally {
      if (gen == _gen) {
        loading = false;
        _notify();
      }
    }
  }

  Future<List<FileItem>> _localSearch(String dir, String q) async {
    final f = foldText(q);
    final out = <FileItem>[];
    final sw = Stopwatch()..start();
    searchComplete = true;
    await for (final e
        in Directory(dir).list(recursive: true, followLinks: false).handleError((_) {})) {
      if (sw.elapsed.inSeconds > 15 || out.length >= 500) {
        searchComplete = false;
        break;
      }
      final name = p.basename(e.path);
      if (!foldText(name).contains(f)) continue;
      try {
        final st = await e.stat();
        out.add(
          FileItem(
            name: name,
            path: e.path,
            isDir: st.type == FileSystemEntityType.directory,
            size: st.size,
            mtime: st.modified,
          ),
        );
      } catch (_) {}
    }
    return out;
  }

  void clearSearch() {
    if (searchQuery == null) return;
    searchQuery = null;
    refresh();
  }

  void resort() {
    _apply();
    _notify();
  }

  void _apply() {
    final prefs = app.prefs;
    final f = foldText(filter.trim());
    var list = _all.where((e) {
      if (!prefs.showHidden && e.hidden && searchQuery == null) return false;
      if (f.isNotEmpty && !foldText(e.name).contains(f)) return false;
      return true;
    }).toList();
    final by = prefs.sortBy;
    final asc = prefs.sortAsc ? 1 : -1;
    list.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      int c;
      switch (by) {
        case 'size':
          c = a.size.compareTo(b.size);
        case 'date':
          c = a.mtime.compareTo(b.mtime);
        case 'type':
          c = a.ext.compareTo(b.ext);
        default:
          c = 0;
      }
      if (c == 0) c = naturalCompare(a.name, b.name);
      return c * asc;
    });
    items = list;
  }

  // ---- selection ----

  bool isSelected(FileItem e) => selected.contains(e.path);

  List<FileItem> get selection =>
      items.where((e) => selected.contains(e.path)).toList();

  int get selectionSize => selection.fold(0, (a, e) => a + e.size);

  void tap(FileItem e, {bool ctrl = false, bool shift = false}) {
    if (shift && _anchor != null) {
      final a = items.indexWhere((x) => x.path == _anchor);
      final b = items.indexOf(e);
      if (a >= 0 && b >= 0) {
        if (!ctrl) selected.clear();
        for (var i = a < b ? a : b; i <= (a < b ? b : a); i++) {
          selected.add(items[i].path);
        }
        _notify();
        return;
      }
    }
    if (ctrl) {
      selected.contains(e.path)
          ? selected.remove(e.path)
          : selected.add(e.path);
    } else {
      selected
        ..clear()
        ..add(e.path);
    }
    _anchor = e.path;
    _notify();
  }

  void toggle(FileItem e) {
    selected.contains(e.path) ? selected.remove(e.path) : selected.add(e.path);
    _anchor = e.path;
    _notify();
  }

  void selectAll() {
    if (selected.length == items.length) {
      selected.clear();
    } else {
      selected
        ..clear()
        ..addAll(items.map((e) => e.path));
    }
    _notify();
  }

  void clearSelection() {
    if (selected.isEmpty) return;
    selected.clear();
    _notify();
  }

  // ---- operations ----

  Future<void> mkdir(String name) async {
    final dir = path!;
    final target = join(dir, name);
    if (remote) {
      await app.api!.mkdir(target);
    } else {
      await LocalFs.mkdir(target);
    }
    await refresh(quiet: true);
    selected
      ..clear()
      ..add(target);
    _notify();
  }

  Future<void> rename(FileItem e, String name) async {
    if (remote) {
      await app.api!.rename(e.path, name);
    } else {
      await LocalFs.rename(e.path, name);
    }
    await refresh(quiet: true);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
