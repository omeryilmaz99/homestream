import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Files on this computer / phone.
class LocalFs {
  static String get home {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ?? 'C:\\';
    }
    if (Platform.isAndroid) return '/storage/emulated/0';
    return Platform.environment['HOME'] ?? '/';
  }

  static String? _androidDownloads;

  /// Where downloads go by default.
  static Future<String> defaultDownloadDir() async {
    if (Platform.isAndroid) {
      return _androidDownloads ??= '/storage/emulated/0/Download';
    }
    try {
      final d = await getDownloadsDirectory();
      if (d != null) return d.path;
    } catch (_) {}
    return p.join(home, 'Downloads');
  }

  static Future<List<Place>> places() async {
    final out = <Place>[];
    void add(String name, String path, String kind) {
      if (out.any((e) => e.path == path)) return;
      if (Directory(path).existsSync()) {
        out.add(Place(name: name, path: path, kind: kind));
      }
    }

    if (Platform.isAndroid) {
      const root = '/storage/emulated/0';
      add('Telefon', root, 'phone');
      add('İndirilenler', '$root/Download', 'download');
      add('Kamera', '$root/DCIM', 'pictures');
      add('Resimler', '$root/Pictures', 'pictures');
      add('Filmler', '$root/Movies', 'videos');
      add('Müzik', '$root/Music', 'music');
      add('Belgeler', '$root/Documents', 'documents');
      try {
        final dirs = await getExternalStorageDirectories() ?? [];
        for (final d in dirs) {
          final i = d.path.indexOf('/Android/');
          if (i <= 0) continue;
          final r = d.path.substring(0, i);
          if (r != root) add('SD kart', r, 'sdcard');
        }
      } catch (_) {}
      return out;
    }

    final h = home;
    add('Ana klasör', h, 'home');
    add('Masaüstü', p.join(h, 'Desktop'), 'desktop');
    add('Masaüstü', p.join(h, 'Masaüstü'), 'desktop');
    add('İndirilenler', p.join(h, 'Downloads'), 'download');
    add('İndirilenler', p.join(h, 'İndirilenler'), 'download');
    add('Belgeler', p.join(h, 'Documents'), 'documents');
    add('Belgeler', p.join(h, 'Belgeler'), 'documents');
    add('Resimler', p.join(h, 'Pictures'), 'pictures');
    add('Videolar', p.join(h, 'Videos'), 'videos');
    add('Müzik', p.join(h, 'Music'), 'music');
    if (Platform.isWindows) {
      for (var c = 'A'.codeUnitAt(0); c <= 'Z'.codeUnitAt(0); c++) {
        final d = '${String.fromCharCode(c)}:\\';
        try {
          if (Directory(d).existsSync()) {
            out.add(Place(name: 'Sürücü ${String.fromCharCode(c)}:', path: d, kind: 'drive'));
          }
        } catch (_) {}
      }
    } else {
      final user = Platform.environment['USER'] ?? '';
      for (final base in ['/media/$user', '/run/media/$user', '/mnt']) {
        try {
          for (final e in Directory(base).listSync()) {
            if (e is Directory) add(p.basename(e.path), e.path, 'drive');
          }
        } catch (_) {}
      }
      add('Sistem (/)', '/', 'drive');
    }
    return out;
  }

  static bool isRoot(String path) {
    if (Platform.isWindows) return RegExp(r'^[A-Za-z]:\\?$').hasMatch(path);
    return path == '/';
  }

  static String? parent(String path) {
    if (isRoot(path)) return null;
    final d = p.dirname(path);
    if (Platform.isWindows && RegExp(r'^[A-Za-z]:$').hasMatch(d)) return '$d\\';
    return d == path ? null : d;
  }

  static Future<Listing> list(String path, {bool hidden = true}) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      throw FileSystemException('Klasör bulunamadı', path);
    }
    final items = <FileItem>[];
    await for (final e in dir.list(followLinks: false).handleError((_) {})) {
      final name = p.basename(e.path);
      if (name.endsWith('.hspart')) continue;
      try {
        var st = await e.stat();
        final isLink = e is Link;
        if (isLink) {
          st = await FileStat.stat(e.path);
          if (st.type == FileSystemEntityType.notFound) continue;
        }
        final isDir = st.type == FileSystemEntityType.directory;
        items.add(
          FileItem(
            name: name,
            path: e.path,
            isDir: isDir,
            size: isDir ? 0 : st.size,
            mtime: st.modified,
            hidden: name.startsWith('.') || _winHidden(name),
            link: isLink,
          ),
        );
      } catch (_) {}
    }
    return Listing(path: path, parent: parent(path), items: items);
  }

  static bool _winHidden(String name) =>
      Platform.isWindows &&
      const [
        'desktop.ini',
        'thumbs.db',
        r'$recycle.bin',
        'system volume information',
        'ntuser.dat',
      ].contains(name.toLowerCase());

  /// "Film: 1?.mkv" → "Film_ 1_.mkv" on Windows (and FAT disks on Android).
  static String safeName(String name) {
    var n = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    if (Platform.isWindows) {
      n = n.replaceAll(RegExp(r'[. ]+$'), '');
      final stem = n.split('.').first.toUpperCase();
      if (RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$').hasMatch(stem)) {
        n = '_$n';
      }
    }
    return n.isEmpty ? '_' : n;
  }

  static String uniquePath(String path) {
    if (FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound) {
      return path;
    }
    final dir = p.dirname(path);
    final ext = p.extension(path);
    final stem = p.basenameWithoutExtension(path);
    for (var i = 2; i < 10000; i++) {
      final c = p.join(dir, '$stem ($i)$ext');
      if (FileSystemEntity.typeSync(c) == FileSystemEntityType.notFound &&
          FileSystemEntity.typeSync('$c.hspart') ==
              FileSystemEntityType.notFound) {
        return c;
      }
    }
    return p.join(dir, '$stem (${DateTime.now().millisecondsSinceEpoch})$ext');
  }

  static Future<void> mkdir(String path) async {
    final d = Directory(path);
    if (await d.exists()) {
      throw FileSystemException('Aynı adda bir klasör var', path);
    }
    await d.create();
  }

  static Future<String> rename(String path, String name) async {
    final target = p.join(p.dirname(path), name);
    if (target != path &&
        FileSystemEntity.typeSync(target) != FileSystemEntityType.notFound &&
        target.toLowerCase() != path.toLowerCase()) {
      throw FileSystemException('Aynı adda bir öğe zaten var', target);
    }
    final t = FileSystemEntity.typeSync(path, followLinks: false);
    if (t == FileSystemEntityType.directory) {
      await Directory(path).rename(target);
    } else if (t == FileSystemEntityType.link) {
      await Link(path).rename(target);
    } else {
      await File(path).rename(target);
    }
    return target;
  }

  static Future<void> delete(String path) async {
    final t = FileSystemEntity.typeSync(path, followLinks: false);
    if (t == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else if (t == FileSystemEntityType.link) {
      await Link(path).delete();
    } else {
      await File(path).delete();
    }
  }

  /// All files below [dir] (for uploading a folder), plus its sub-folders.
  static Future<({List<File> files, List<String> dirs})> walk(
    String dir, {
    bool hidden = false,
  }) async {
    final files = <File>[];
    final dirs = <String>[];
    await for (final e
        in Directory(
          dir,
        ).list(recursive: true, followLinks: false).handleError((_) {})) {
      final rel = p.relative(e.path, from: dir);
      final parts = p.split(rel);
      if (!hidden && parts.any((s) => s.startsWith('.'))) continue;
      if (e.path.endsWith('.hspart')) continue;
      if (e is File) {
        files.add(e);
      } else if (e is Directory) {
        dirs.add(rel);
      }
    }
    return (files: files, dirs: dirs);
  }

  static String errorText(Object e) {
    if (e is FileSystemException) {
      final code = e.osError?.errorCode;
      final m = (e.osError?.message ?? '').toLowerCase();
      if (code == 28 || code == 112 || m.contains('no space')) {
        return 'Bu cihazda yer kalmadı';
      }
      if (code == 13 || code == 5 || code == 1 || m.contains('denied')) {
        return 'İzin yok: ${e.path ?? ''}';
      }
      if (code == 2 || code == 3) return 'Bulunamadı: ${e.path ?? ''}';
      if (code == 30) return 'Disk salt okunur';
      if (code == 32 || code == 33) {
        return 'Dosya başka bir programda açık';
      }
      if (code == 206 || code == 36) return 'Dosya adı ya da yol çok uzun';
      return e.message.isNotEmpty ? e.message : '$e';
    }
    return '$e';
  }
}
