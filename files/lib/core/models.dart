import 'package:flutter/material.dart';

int _int(Object? v) => (v as num?)?.toInt() ?? 0;
double _dbl(Object? v) => (v as num?)?.toDouble() ?? 0;
String _str(Object? v) => v == null ? '' : '$v';

/// One file or folder, on this device or on the server.
class FileItem {
  final String name;
  final String path;
  final bool isDir;
  final int size;
  final DateTime mtime;
  final bool hidden;
  final bool link;
  final int count; // entries in a folder, -1 unknown
  const FileItem({
    required this.name,
    required this.path,
    required this.isDir,
    this.size = 0,
    required this.mtime,
    this.hidden = false,
    this.link = false,
    this.count = -1,
  });

  factory FileItem.remote(Map<String, dynamic> j, String dir) {
    final name = _str(j['name']);
    return FileItem(
      name: name,
      path: j['path'] != null
          ? _str(j['path'])
          : (dir == '/' ? '/$name' : '$dir/$name'),
      isDir: j['dir'] == true,
      size: _int(j['size']),
      mtime: DateTime.fromMillisecondsSinceEpoch(_int(j['mtime'])),
      hidden: j['hidden'] == true,
      link: j['link'] == true,
      count: j.containsKey('count') ? _int(j['count']) : -1,
    );
  }

  String get ext {
    final i = name.lastIndexOf('.');
    return i <= 0 ? '' : name.substring(i + 1).toLowerCase();
  }

  FileKind get kind => isDir ? FileKind.folder : kindOf(name);
}

enum FileKind {
  folder,
  image,
  video,
  audio,
  document,
  archive,
  code,
  apk,
  other,
}

const _exts = <FileKind, List<String>>{
  FileKind.image: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif', 'svg', 'tif', 'tiff', 'raw', 'dng'],
  FileKind.video: ['mp4', 'mkv', 'avi', 'mov', 'wmv', 'webm', 'm4v', 'ts', 'm2ts', 'flv', 'mpg', 'mpeg', '3gp'],
  FileKind.audio: ['mp3', 'flac', 'wav', 'm4a', 'aac', 'ogg', 'opus', 'wma', 'alac', 'aiff', 'ape', 'dsf'],
  FileKind.document: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'md', 'odt', 'ods', 'rtf', 'csv', 'epub', 'srt', 'ass', 'sub'],
  FileKind.archive: ['zip', 'rar', '7z', 'tar', 'gz', 'xz', 'bz2', 'zst', 'iso', 'img', 'tgz'],
  FileKind.code: ['dart', 'go', 'py', 'js', 'ts', 'json', 'yaml', 'yml', 'xml', 'html', 'css', 'sh', 'c', 'cpp', 'h', 'java', 'kt', 'conf', 'ini', 'log', 'toml', 'sql'],
  FileKind.apk: ['apk', 'exe', 'msi', 'deb', 'appimage', 'rpm'],
};

FileKind kindOf(String name) {
  final i = name.lastIndexOf('.');
  if (i <= 0) return FileKind.other;
  final e = name.substring(i + 1).toLowerCase();
  for (final k in _exts.entries) {
    if (k.value.contains(e)) return k.key;
  }
  return FileKind.other;
}

/// Images the server can make thumbnails of.
bool canThumb(String name) =>
    const ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(
      name.contains('.') ? name.split('.').last.toLowerCase() : '',
    );

bool isTextFile(String name) {
  final k = kindOf(name);
  final e = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return k == FileKind.code ||
      const ['txt', 'md', 'csv', 'srt', 'ass', 'nfo', 'log'].contains(e);
}

IconData kindIcon(FileKind k) => switch (k) {
  FileKind.folder => Icons.folder_rounded,
  FileKind.image => Icons.image_rounded,
  FileKind.video => Icons.movie_rounded,
  FileKind.audio => Icons.music_note_rounded,
  FileKind.document => Icons.description_rounded,
  FileKind.archive => Icons.inventory_2_rounded,
  FileKind.code => Icons.code_rounded,
  FileKind.apk => Icons.install_desktop_rounded,
  FileKind.other => Icons.insert_drive_file_rounded,
};

Color kindColor(FileKind k) => switch (k) {
  FileKind.folder => const Color(0xFF3DBDB9),
  FileKind.image => const Color(0xFF6C9EE0),
  FileKind.video => const Color(0xFF8C7AE6),
  FileKind.audio => const Color(0xFFE58FB1),
  FileKind.document => const Color(0xFF4DA3D9),
  FileKind.archive => const Color(0xFFE2A24F),
  FileKind.code => const Color(0xFF5AAE8A),
  FileKind.apk => const Color(0xFF7D8FA0),
  FileKind.other => const Color(0xFF94A7B1),
};

class Listing {
  final String path;
  final String? parent;
  final List<FileItem> items;
  final int total;
  final int free;
  final bool writable;
  Listing({
    required this.path,
    this.parent,
    required this.items,
    this.total = 0,
    this.free = 0,
    this.writable = true,
  });
}

/// A shortcut: home, library folder, disk, drive letter…
class Place {
  final String name;
  final String path;
  final String kind; // home | library | music | disk | root | folder | bookmark
  final int total;
  final int free;
  final bool available;
  const Place({
    required this.name,
    required this.path,
    required this.kind,
    this.total = 0,
    this.free = 0,
    this.available = true,
  });

  factory Place.fromJson(Map<String, dynamic> j) => Place(
    name: _str(j['name']),
    path: _str(j['path']),
    kind: _str(j['kind']),
    total: _int(j['total']),
    free: _int(j['free']),
    available: j['available'] != false,
  );

  IconData get icon => switch (kind) {
    'home' => Icons.home_rounded,
    'library' => Icons.video_library_rounded,
    'music' => Icons.library_music_rounded,
    'disk' => Icons.usb_rounded,
    'root' => Icons.dns_rounded,
    'drive' => Icons.storage_rounded,
    'bookmark' => Icons.bookmark_rounded,
    'download' => Icons.download_rounded,
    'desktop' => Icons.desktop_windows_rounded,
    'documents' => Icons.description_rounded,
    'pictures' => Icons.photo_library_rounded,
    'videos' => Icons.movie_rounded,
    'sdcard' => Icons.sd_card_rounded,
    'phone' => Icons.smartphone_rounded,
    _ => Icons.folder_rounded,
  };
}

class Partition {
  final String name, path, label, fs, mountpoint;
  final int size, total, free;
  final bool canEject, canMount;
  Partition.fromJson(Map<String, dynamic> j)
    : name = _str(j['name']),
      path = _str(j['path']),
      label = _str(j['label']),
      fs = _str(j['fs']),
      mountpoint = _str(j['mountpoint']),
      size = _int(j['size']),
      total = _int(j['total']),
      free = _int(j['free']),
      canEject = j['canEject'] == true,
      canMount = j['canMount'] == true;
  String get title => label.isNotEmpty
      ? label
      : (mountpoint.isNotEmpty ? mountpoint.split('/').last : name);
}

class DiskInfo {
  final String name, path, model, transport;
  final int size;
  final bool removable, system;
  final List<Partition> partitions;
  DiskInfo.fromJson(Map<String, dynamic> j)
    : name = _str(j['name']),
      path = _str(j['path']),
      model = _str(j['model']),
      transport = _str(j['transport']),
      size = _int(j['size']),
      removable = j['removable'] == true,
      system = j['system'] == true,
      partitions = ((j['partitions'] as List?) ?? const [])
          .map((e) => Partition.fromJson(e as Map<String, dynamic>))
          .toList();
  String get title => model.isNotEmpty ? model : name;
}

class SessionInfo {
  final String id, device, platform, lastIp;
  final DateTime created, lastSeen;
  final bool online, current;
  SessionInfo.fromJson(Map<String, dynamic> j)
    : id = _str(j['id']),
      device = _str(j['device']),
      platform = _str(j['platform']),
      lastIp = _str(j['lastIp']),
      created = DateTime.fromMillisecondsSinceEpoch(_int(j['created']) * 1000),
      lastSeen = DateTime.fromMillisecondsSinceEpoch(
        _int(j['lastSeen']) * 1000,
      ),
      online = j['online'] == true,
      current = j['current'] == true;

  IconData get icon {
    final p = platform.toLowerCase();
    if (p.contains('android') || p.contains('ios')) {
      return Icons.smartphone_rounded;
    }
    if (p.contains('windows')) return Icons.desktop_windows_rounded;
    if (p.contains('linux')) return Icons.computer_rounded;
    return Icons.devices_other_rounded;
  }
}

class SystemInfo {
  final String hostname, os, arch;
  final int cpus, memTotal, memAvailable, homeTotal, homeFree;
  final double cpu, temperature, uptime, rxRate, txRate;
  final List<double> load;
  final List<String> ips;
  SystemInfo.fromJson(Map<String, dynamic> j)
    : hostname = _str(j['hostname']),
      os = _str(j['os']),
      arch = _str(j['arch']),
      cpus = _int(j['cpus']),
      memTotal = _int(j['memTotal']),
      memAvailable = _int(j['memAvailable']),
      homeTotal = _int(j['homeTotal']),
      homeFree = _int(j['homeFree']),
      cpu = _dbl(j['cpu']),
      temperature = _dbl(j['temperature']),
      uptime = _dbl(j['uptime']),
      rxRate = _dbl(j['rxRate']),
      txRate = _dbl(j['txRate']),
      load = ((j['load'] as List?) ?? const []).map(_dbl).toList(),
      ips = ((j['ips'] as List?) ?? const []).map(_str).toList();
}

class TrashItem {
  final String id, name, orig;
  final DateTime deleted;
  final bool isDir;
  final int size;
  TrashItem.fromJson(Map<String, dynamic> j)
    : id = _str(j['id']),
      name = _str(j['name']),
      orig = _str(j['orig']),
      deleted = DateTime.fromMillisecondsSinceEpoch(_int(j['deleted'])),
      isDir = j['dir'] == true,
      size = _int(j['size']);
}

/// A copy/move running on the server.
class ServerJob {
  final String id, kind, dest, current, state, error;
  final List<String> names;
  final int total, done, files, filesDone;
  ServerJob.fromJson(Map<String, dynamic> j)
    : id = _str(j['id']),
      kind = _str(j['kind']),
      dest = _str(j['dest']),
      current = _str(j['current']),
      state = _str(j['state']),
      error = _str(j['error']),
      names = ((j['names'] as List?) ?? const []).map(_str).toList(),
      total = _int(j['total']),
      done = _int(j['done']),
      files = _int(j['files']),
      filesDone = _int(j['filesDone']);
  bool get running => state == 'running';
  double get progress => total <= 0 ? 0 : (done / total).clamp(0, 1);
}
