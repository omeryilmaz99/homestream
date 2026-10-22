// Data objects of the music API (see docs/MUSIC_API.md).

int _i(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
String _s(dynamic v) => v == null ? '' : '$v';
bool _b(dynamic v) => v == true;
List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
    v is List ? v.whereType<Map<String, dynamic>>().map(f).toList() : <T>[];

class Profile {
  final String id;
  final String name;
  final String color;
  final String avatar;
  Profile({
    required this.id,
    required this.name,
    required this.color,
    required this.avatar,
  });
  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
    id: _s(j['id']),
    name: _s(j['name']),
    color: _s(j['color']).isEmpty ? '#1DB954' : _s(j['color']),
    avatar: _s(j['avatar']),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': color,
    'avatar': avatar,
  };
}

class Track {
  final String id;
  final String title;
  final String artist;
  final String artistId;
  final String album;
  final String albumId;
  final String albumArtist;
  final int trackNo;
  final int discNo;
  final int year;
  final String genre;
  final double duration;
  final String cover; // server path with ?v=
  final String coverId;
  final bool isVideo;
  final String codec;
  final int bitrate;
  final int sampleRate;
  final int bitDepth;
  final int channels;
  final bool lossless;
  final int size;
  final String ext;
  final String path;
  final String dir; // folder key (browse)
  final int addedAt;
  bool liked;
  int playCount;
  int lastPlayedAt;

  Track({
    required this.id,
    required this.title,
    this.artist = '',
    this.artistId = '',
    this.album = '',
    this.albumId = '',
    this.albumArtist = '',
    this.trackNo = 0,
    this.discNo = 0,
    this.year = 0,
    this.genre = '',
    this.duration = 0,
    this.cover = '',
    this.coverId = '',
    this.isVideo = false,
    this.codec = '',
    this.bitrate = 0,
    this.sampleRate = 0,
    this.bitDepth = 0,
    this.channels = 0,
    this.lossless = false,
    this.size = 0,
    this.ext = '',
    this.path = '',
    this.dir = '',
    this.addedAt = 0,
    this.liked = false,
    this.playCount = 0,
    this.lastPlayedAt = 0,
  });

  factory Track.fromJson(Map<String, dynamic> j) => Track(
    id: _s(j['id']),
    title: _s(j['title']),
    artist: _s(j['artist']),
    artistId: _s(j['artistId']),
    album: _s(j['album']),
    albumId: _s(j['albumId']),
    albumArtist: _s(j['albumArtist']),
    trackNo: _i(j['trackNo']),
    discNo: _i(j['discNo']),
    year: _i(j['year']),
    genre: _s(j['genre']),
    duration: _d(j['duration']),
    cover: _s(j['cover']),
    coverId: _s(j['coverId']),
    isVideo: _b(j['isVideo']),
    codec: _s(j['codec']),
    bitrate: _i(j['bitrate']),
    sampleRate: _i(j['sampleRate']),
    bitDepth: _i(j['bitDepth']),
    channels: _i(j['channels']),
    lossless: _b(j['lossless']),
    size: _i(j['size']),
    ext: _s(j['ext']),
    path: _s(j['path']),
    dir: _s(j['dir']),
    addedAt: _i(j['addedAt']),
    liked: _b(j['liked']),
    playCount: _i(j['playCount']),
    lastPlayedAt: _i(j['lastPlayedAt']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'artistId': artistId,
    'album': album,
    'albumId': albumId,
    'albumArtist': albumArtist,
    'trackNo': trackNo,
    'discNo': discNo,
    'year': year,
    'genre': genre,
    'duration': duration,
    'cover': cover,
    'coverId': coverId,
    'isVideo': isVideo,
    'codec': codec,
    'bitrate': bitrate,
    'sampleRate': sampleRate,
    'bitDepth': bitDepth,
    'channels': channels,
    'lossless': lossless,
    'size': size,
    'ext': ext,
    'path': path,
    'dir': dir,
    'addedAt': addedAt,
    'liked': liked,
    'playCount': playCount,
    'lastPlayedAt': lastPlayedAt,
  };

  /// "FLAC • 24-bit / 96 kHz" style quality label.
  String get qualityLabel {
    final parts = <String>[];
    final c = _codecName(codec);
    if (c.isNotEmpty) parts.add(c);
    if (lossless) {
      final bits = bitDepth > 0 ? '$bitDepth-bit' : '';
      final rate = sampleRate > 0 ? _khz(sampleRate) : '';
      final q = [bits, rate].where((e) => e.isNotEmpty).join(' / ');
      if (q.isNotEmpty) parts.add(q);
    } else {
      if (bitrate > 0) parts.add('${(bitrate / 1000).round()} kbps');
      if (sampleRate > 0) parts.add(_khz(sampleRate));
    }
    return parts.join(' • ');
  }

  bool get hiRes => lossless && (bitDepth > 16 || sampleRate > 48000);

  static String _khz(int hz) {
    final k = hz / 1000;
    return k == k.roundToDouble()
        ? '${k.round()} kHz'
        : '${k.toStringAsFixed(1)} kHz';
  }

  static String _codecName(String c) {
    switch (c) {
      case 'mp3':
        return 'MP3';
      case 'aac':
        return 'AAC';
      case 'flac':
        return 'FLAC';
      case 'alac':
        return 'ALAC';
      case 'opus':
        return 'Opus';
      case 'vorbis':
        return 'Vorbis';
      case 'ape':
        return 'APE';
      case 'wavpack':
        return 'WavPack';
      case 'wmav2':
      case 'wmav1':
      case 'wmapro':
        return 'WMA';
      case '':
        return '';
    }
    if (c.startsWith('pcm_')) return 'PCM';
    if (c.startsWith('dsd_')) return 'DSD';
    return c.toUpperCase();
  }
}

class Album {
  final String id;
  final String title;
  final String artist;
  final String artistId;
  final int year;
  final String genre;
  final int trackCount;
  final double duration;
  final String cover;
  final int addedAt;
  Album({
    required this.id,
    required this.title,
    this.artist = '',
    this.artistId = '',
    this.year = 0,
    this.genre = '',
    this.trackCount = 0,
    this.duration = 0,
    this.cover = '',
    this.addedAt = 0,
  });
  factory Album.fromJson(Map<String, dynamic> j) => Album(
    id: _s(j['id']),
    title: _s(j['title']),
    artist: _s(j['artist']),
    artistId: _s(j['artistId']),
    year: _i(j['year']),
    genre: _s(j['genre']),
    trackCount: _i(j['trackCount']),
    duration: _d(j['duration']),
    cover: _s(j['cover']),
    addedAt: _i(j['addedAt']),
  );
}

class AlbumDetail {
  final Album album;
  final List<Track> tracks;
  final List<Album> moreByArtist;
  AlbumDetail(this.album, this.tracks, this.moreByArtist);
  factory AlbumDetail.fromJson(Map<String, dynamic> j) => AlbumDetail(
    Album.fromJson(j['album'] as Map<String, dynamic>),
    _list(j['tracks'], Track.fromJson),
    _list(j['moreByArtist'], Album.fromJson),
  );
}

class Artist {
  final String id;
  final String name;
  final int albumCount;
  final int trackCount;
  final String cover;
  Artist({
    required this.id,
    required this.name,
    this.albumCount = 0,
    this.trackCount = 0,
    this.cover = '',
  });
  factory Artist.fromJson(Map<String, dynamic> j) => Artist(
    id: _s(j['id']),
    name: _s(j['name']),
    albumCount: _i(j['albumCount']),
    trackCount: _i(j['trackCount']),
    cover: _s(j['cover']),
  );
}

class ArtistDetail {
  final Artist artist;
  final List<Track> top;
  final List<Album> albums;
  final List<Album> appearsOn;
  final List<Track> tracks;
  ArtistDetail(this.artist, this.top, this.albums, this.appearsOn, this.tracks);
  factory ArtistDetail.fromJson(Map<String, dynamic> j) => ArtistDetail(
    Artist.fromJson(j['artist'] as Map<String, dynamic>),
    _list(j['top'], Track.fromJson),
    _list(j['albums'], Album.fromJson),
    _list(j['appearsOn'], Album.fromJson),
    _list(j['tracks'], Track.fromJson),
  );
}

class Playlist {
  final String id;
  final String name;
  final int trackCount;
  final double duration;
  final List<String> covers;
  final int createdAt;
  final int updatedAt;
  final int missingCount;
  final List<Track> tracks;
  final List<String> trackIds;
  Playlist({
    required this.id,
    required this.name,
    this.trackCount = 0,
    this.duration = 0,
    this.covers = const [],
    this.createdAt = 0,
    this.updatedAt = 0,
    this.missingCount = 0,
    this.tracks = const [],
    this.trackIds = const [],
  });
  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
    id: _s(j['id']),
    name: _s(j['name']),
    trackCount: _i(j['trackCount']),
    duration: _d(j['duration']),
    covers: (j['covers'] as List? ?? []).map((e) => '$e').toList(),
    createdAt: _i(j['createdAt']),
    updatedAt: _i(j['updatedAt']),
    missingCount: _i(j['missingCount']),
    tracks: _list(j['tracks'], Track.fromJson),
    trackIds: (j['trackIds'] as List? ?? []).map((e) => '$e').toList(),
  );
}

/// A home screen tile.
class HomeCard {
  final String type; // album | artist | playlist | track | liked
  final String id;
  final String title;
  final String subtitle;
  final String cover;
  final List<String> covers;
  final Track? track;
  HomeCard({
    required this.type,
    required this.id,
    required this.title,
    this.subtitle = '',
    this.cover = '',
    this.covers = const [],
    this.track,
  });
  factory HomeCard.fromJson(Map<String, dynamic> j) => HomeCard(
    type: _s(j['type']),
    id: _s(j['id']),
    title: _s(j['title']),
    subtitle: _s(j['subtitle']),
    cover: _s(j['cover']),
    covers: (j['covers'] as List? ?? []).map((e) => '$e').toList(),
    track: j['track'] is Map<String, dynamic>
        ? Track.fromJson(j['track'] as Map<String, dynamic>)
        : null,
  );
}

class HomeRow {
  final String id;
  final String title;
  final String style; // square | round
  final List<HomeCard> items;
  HomeRow(this.id, this.title, this.style, this.items);
  factory HomeRow.fromJson(Map<String, dynamic> j) => HomeRow(
    _s(j['id']),
    _s(j['title']),
    _s(j['style']),
    _list(j['items'], HomeCard.fromJson),
  );
}

class HomeData {
  final List<HomeCard> quick;
  final List<HomeRow> rows;
  final int trackCount;
  HomeData(this.quick, this.rows, this.trackCount);
  factory HomeData.fromJson(Map<String, dynamic> j) => HomeData(
    _list(j['quick'], HomeCard.fromJson),
    _list(j['rows'], HomeRow.fromJson),
    _i(j['trackCount']),
  );
}

class Genre {
  final String name;
  final int trackCount;
  final String cover;
  Genre(this.name, this.trackCount, this.cover);
  factory Genre.fromJson(Map<String, dynamic> j) =>
      Genre(_s(j['name']), _i(j['trackCount']), _s(j['cover']));
}

class FolderEntry {
  final String name;
  final String path;
  final int count;
  final String cover;
  FolderEntry(this.name, this.path, this.count, this.cover);
  factory FolderEntry.fromJson(Map<String, dynamic> j) =>
      FolderEntry(_s(j['name']), _s(j['path']), _i(j['count']), _s(j['cover']));
}

class BrowseResult {
  final String path;
  final String name;
  final String? parent;
  final List<FolderEntry> dirs;
  final List<Track> tracks;
  final int count;
  final String cover;
  BrowseResult(
    this.path,
    this.name,
    this.parent,
    this.dirs,
    this.tracks,
    this.count,
    this.cover,
  );
  factory BrowseResult.fromJson(Map<String, dynamic> j) => BrowseResult(
    _s(j['path']),
    _s(j['name']),
    j['parent'] == null ? null : _s(j['parent']),
    _list(j['dirs'], FolderEntry.fromJson),
    _list(j['tracks'], Track.fromJson),
    _i(j['count']),
    _s(j['cover']),
  );
}

class SearchResults {
  final List<Track> tracks;
  final List<Album> albums;
  final List<Artist> artists;
  final List<Playlist> playlists;
  final List<FolderEntry> folders;
  SearchResults(
    this.tracks,
    this.albums,
    this.artists,
    this.playlists,
    this.folders,
  );
  factory SearchResults.fromJson(Map<String, dynamic> j) => SearchResults(
    _list(j['tracks'], Track.fromJson),
    _list(j['albums'], Album.fromJson),
    _list(j['artists'], Artist.fromJson),
    _list(j['playlists'], Playlist.fromJson),
    _list(j['folders'], FolderEntry.fromJson),
  );
  bool get isEmpty =>
      tracks.isEmpty &&
      albums.isEmpty &&
      artists.isEmpty &&
      playlists.isEmpty &&
      folders.isEmpty;
}

class MusicFolder {
  final int id;
  final String path;
  final String name;
  final bool isDefault;
  final bool available;
  final int trackCount;
  MusicFolder(
    this.id,
    this.path,
    this.name,
    this.isDefault,
    this.available,
    this.trackCount,
  );
  factory MusicFolder.fromJson(Map<String, dynamic> j) => MusicFolder(
    _i(j['id']),
    _s(j['path']),
    _s(j['name']),
    _b(j['isDefault']),
    _b(j['available']),
    _i(j['trackCount']),
  );
}

class MusicSettings {
  final String serverName;
  final List<MusicFolder> folders;
  final bool onlineCovers;
  final int scanIntervalMinutes;
  final bool ffmpeg;
  MusicSettings(
    this.serverName,
    this.folders,
    this.onlineCovers,
    this.scanIntervalMinutes,
    this.ffmpeg,
  );
  factory MusicSettings.fromJson(Map<String, dynamic> j) => MusicSettings(
    _s(j['serverName']),
    _list(j['folders'], MusicFolder.fromJson),
    _b(j['onlineCovers']),
    _i(j['scanIntervalMinutes']),
    _b(j['ffmpeg']),
  );
}

class ScanStatus {
  final bool running;
  final String phase;
  final int done;
  final int total;
  final int lastScanAt;
  final String lastError;
  final String coverTask;
  final int coverDone;
  final int coverTotal;
  ScanStatus(
    this.running,
    this.phase,
    this.done,
    this.total,
    this.lastScanAt,
    this.lastError,
    this.coverTask,
    this.coverDone,
    this.coverTotal,
  );
  factory ScanStatus.fromJson(Map<String, dynamic> j) => ScanStatus(
    _b(j['running']),
    _s(j['phase']),
    _i(j['done']),
    _i(j['total']),
    _i(j['lastScanAt']),
    _s(j['lastError']),
    _s(j['coverTask']),
    _i(j['coverDone']),
    _i(j['coverTotal']),
  );
}

class FsListing {
  final String path;
  final String? parent;
  final List<(String, String)> dirs;
  FsListing(this.path, this.parent, this.dirs);
  factory FsListing.fromJson(Map<String, dynamic> j) =>
      FsListing(_s(j['path']), j['parent'] == null ? null : _s(j['parent']), [
        for (final d in (j['dirs'] as List? ?? []))
          if (d is Map) (_s(d['name']), _s(d['path'])),
      ]);
}

class ServerInfo {
  final String id;
  final String name;
  final String version;
  final bool music;
  final int trackCount;
  ServerInfo(this.id, this.name, this.version, this.music, this.trackCount);
  factory ServerInfo.fromJson(Map<String, dynamic> j) => ServerInfo(
    _s(j['id']),
    _s(j['name']),
    _s(j['version']),
    _b(j['music']),
    _i(j['trackCount']),
  );
}
