// Data models mirroring docs/API.md.

double _d(dynamic v) => v is num ? v.toDouble() : (double.tryParse('$v') ?? 0);
int _i(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);
String _s(dynamic v) => v == null ? '' : '$v';
bool _b(dynamic v) => v == true;

enum ItemType { movie, series, episode }

ItemType _type(dynamic v) {
  switch (v) {
    case 'series':
      return ItemType.series;
    case 'episode':
      return ItemType.episode;
    default:
      return ItemType.movie;
  }
}

class UserData {
  final double position;
  final bool played;
  final int playCount;
  final int lastPlayedAt;
  final bool liked;

  const UserData({
    this.position = 0,
    this.played = false,
    this.playCount = 0,
    this.lastPlayedAt = 0,
    this.liked = false,
  });

  factory UserData.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const UserData();
    return UserData(
      position: _d(j['position']),
      played: _b(j['played']),
      playCount: _i(j['playCount']),
      lastPlayedAt: _i(j['lastPlayedAt']),
      liked: _b(j['liked']),
    );
  }

  UserData copyWith({double? position, bool? played, bool? liked}) => UserData(
    position: position ?? this.position,
    played: played ?? this.played,
    playCount: playCount,
    lastPlayedAt: lastPlayedAt,
    liked: liked ?? this.liked,
  );
}

class AudioStream {
  final int index;
  final String codec;
  final String language;
  final int channels;
  final String title;
  AudioStream.fromJson(Map<String, dynamic> j)
    : index = _i(j['index']),
      codec = _s(j['codec']),
      language = _s(j['language']),
      channels = _i(j['channels']),
      title = _s(j['title']);
}

class SubtitleStream {
  final int index;
  final String codec;
  final String language;
  final String title;
  final bool forced;
  SubtitleStream.fromJson(Map<String, dynamic> j)
    : index = _i(j['index']),
      codec = _s(j['codec']),
      language = _s(j['language']),
      title = _s(j['title']),
      forced = _b(j['forced']);
}

class ExternalSubtitle {
  final String id;
  final String language;
  final String title;
  final String format;
  final String url;
  ExternalSubtitle.fromJson(Map<String, dynamic> j)
    : id = _s(j['id']),
      language = _s(j['language']),
      title = _s(j['title']),
      format = _s(j['format']),
      url = _s(j['url']);
}

class MediaFile {
  final String path;
  final int size;
  final String container;
  final String videoCodec;
  final int width;
  final int height;
  final bool hdr;
  final int bitrate;
  final List<AudioStream> audio;
  final List<SubtitleStream> subtitles;
  final List<ExternalSubtitle> externalSubtitles;
  final String streamUrl;

  MediaFile.fromJson(Map<String, dynamic> j)
    : path = _s(j['path']),
      size = _i(j['size']),
      container = _s(j['container']),
      videoCodec = _s(j['videoCodec']),
      width = _i(j['width']),
      height = _i(j['height']),
      hdr = _b(j['hdr']),
      bitrate = _i(j['bitrate']),
      audio = ((j['audio'] as List?) ?? [])
          .map((e) => AudioStream.fromJson(e as Map<String, dynamic>))
          .toList(),
      subtitles = ((j['subtitles'] as List?) ?? [])
          .map((e) => SubtitleStream.fromJson(e as Map<String, dynamic>))
          .toList(),
      externalSubtitles = ((j['externalSubtitles'] as List?) ?? [])
          .map((e) => ExternalSubtitle.fromJson(e as Map<String, dynamic>))
          .toList(),
      streamUrl = _s(j['streamUrl']);

  String get resolutionLabel {
    if (width >= 3200 || height >= 2000) return '4K';
    if (width >= 2400 || height >= 1400) return '1440p';
    if (width >= 1800 || height >= 1000) return '1080p';
    if (width >= 1200 || height >= 700) return '720p';
    if (height > 0) return 'SD';
    return '';
  }
}

class Season {
  final int number;
  final String title;
  final List<MediaItem> episodes;
  Season.fromJson(Map<String, dynamic> j)
    : number = _i(j['number']),
      title = _s(j['title']),
      episodes = ((j['episodes'] as List?) ?? [])
          .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
          .toList();
}

class MediaItem {
  final String id;
  final ItemType type;
  final String title;
  final int year;
  final String overview;
  final List<String> genres;
  final double rating;
  final double duration;
  final String poster;
  final String backdrop;
  final bool posterGenerated;
  final int addedAt;
  final String seriesId;
  final String seriesTitle;
  final int season;
  final int episode;
  final int episodeCount;
  final int seasonCount;
  final int unwatchedCount;
  UserData userData;
  final MediaFile? file;
  final List<Season> seasons;
  final MediaItem? nextUp;

  MediaItem({
    required this.id,
    required this.type,
    required this.title,
    this.year = 0,
    this.overview = '',
    this.genres = const [],
    this.rating = 0,
    this.duration = 0,
    this.poster = '',
    this.backdrop = '',
    this.posterGenerated = false,
    this.addedAt = 0,
    this.seriesId = '',
    this.seriesTitle = '',
    this.season = 0,
    this.episode = 0,
    this.episodeCount = 0,
    this.seasonCount = 0,
    this.unwatchedCount = 0,
    this.userData = const UserData(),
    this.file,
    this.seasons = const [],
    this.nextUp,
  });

  factory MediaItem.fromJson(Map<String, dynamic> j) => MediaItem(
    id: _s(j['id']),
    type: _type(j['type']),
    title: _s(j['title']),
    year: _i(j['year']),
    overview: _s(j['overview']),
    genres: ((j['genres'] as List?) ?? []).map((e) => '$e').toList(),
    rating: _d(j['rating']),
    duration: _d(j['duration']),
    poster: _s(j['poster']),
    backdrop: _s(j['backdrop']),
    posterGenerated: _b(j['posterGenerated']),
    addedAt: _i(j['addedAt']),
    seriesId: _s(j['seriesId']),
    seriesTitle: _s(j['seriesTitle']),
    season: _i(j['season']),
    episode: _i(j['episode']),
    episodeCount: _i(j['episodeCount']),
    seasonCount: _i(j['seasonCount']),
    unwatchedCount: _i(j['unwatchedCount']),
    userData: UserData.fromJson(j['userData'] as Map<String, dynamic>?),
    file: j['file'] is Map<String, dynamic>
        ? MediaFile.fromJson(j['file'] as Map<String, dynamic>)
        : null,
    seasons: ((j['seasons'] as List?) ?? [])
        .map((e) => Season.fromJson(e as Map<String, dynamic>))
        .toList(),
    nextUp: j['nextUp'] is Map<String, dynamic>
        ? MediaItem.fromJson(j['nextUp'] as Map<String, dynamic>)
        : null,
  );

  bool get isPlayable => type != ItemType.series;
  bool get isEpisode => type == ItemType.episode;
  bool get isSeries => type == ItemType.series;

  /// 0..1 watched fraction for progress bars.
  double get progress {
    if (duration <= 0 || userData.position <= 0) return 0;
    return (userData.position / duration).clamp(0.0, 1.0);
  }

  bool get inProgress => userData.position > 5 && !userData.played;

  String get episodeCode =>
      'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';

  /// Title used in players / headers: "Dizi · S01E02 · Bölüm adı".
  String get displayTitle {
    if (!isEpisode) return title;
    final base = seriesTitle.isNotEmpty ? '$seriesTitle · ' : '';
    return '$base$episodeCode${title.isNotEmpty ? ' · $title' : ''}';
  }
}

class HomeRow {
  final String id;
  final String title;
  final List<MediaItem> items;
  HomeRow.fromJson(Map<String, dynamic> j)
    : id = _s(j['id']),
      title = _s(j['title']),
      items = ((j['items'] as List?) ?? [])
          .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
          .toList();
}

class HomeData {
  final List<MediaItem> hero;
  final List<HomeRow> rows;
  HomeData.fromJson(Map<String, dynamic> j)
    : hero = ((j['hero'] as List?) ?? [])
          .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      rows = ((j['rows'] as List?) ?? [])
          .map((e) => HomeRow.fromJson(e as Map<String, dynamic>))
          .toList();
}

class Related {
  final MediaItem? next;
  final List<MediaItem> episodes;
  final List<MediaItem> recommended;
  Related.fromJson(Map<String, dynamic> j)
    : next = j['next'] is Map<String, dynamic>
          ? MediaItem.fromJson(j['next'] as Map<String, dynamic>)
          : null,
      episodes = ((j['episodes'] as List?) ?? [])
          .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      recommended = ((j['recommended'] as List?) ?? [])
          .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
          .toList();
  Related.empty() : next = null, episodes = const [], recommended = const [];
}

class Profile {
  final String id;
  final String name;
  final String color;
  final String avatar;
  Profile.fromJson(Map<String, dynamic> j)
    : id = _s(j['id']),
      name = _s(j['name']),
      color = _s(j['color']),
      avatar = _s(j['avatar']);
}

class SearchResults {
  final List<MediaItem> movies;
  final List<MediaItem> series;
  final List<MediaItem> episodes;
  SearchResults.fromJson(Map<String, dynamic> j)
    : movies = _list(j['movies']),
      series = _list(j['series']),
      episodes = _list(j['episodes']);
  bool get isEmpty => movies.isEmpty && series.isEmpty && episodes.isEmpty;
}

List<MediaItem> _list(dynamic v) => ((v as List?) ?? [])
    .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
    .toList();

class BrowseEntry {
  final String name;
  final String path;
  final bool isDir;
  final int size;
  final String itemId;
  final double duration;
  final UserData userData;
  final String thumb;
  BrowseEntry.fromJson(Map<String, dynamic> j)
    : name = _s(j['name']),
      path = _s(j['path']),
      isDir = j['type'] == 'dir',
      size = _i(j['size']),
      itemId = _s(j['itemId']),
      duration = _d(j['duration']),
      userData = UserData.fromJson(j['userData'] as Map<String, dynamic>?),
      thumb = _s(j['thumb']);
}

class BrowseResult {
  final String path;
  final String name;
  final String? parent;
  final List<BrowseEntry> entries;
  BrowseResult.fromJson(Map<String, dynamic> j)
    : path = _s(j['path']),
      name = _s(j['name']),
      parent = j['parent'] as String?,
      entries = ((j['entries'] as List?) ?? [])
          .map((e) => BrowseEntry.fromJson(e as Map<String, dynamic>))
          .toList();
}

class ServerInfo {
  final String id;
  final String name;
  final String version;
  final int movieCount;
  final int seriesCount;
  final int episodeCount;
  final bool scanning;
  ServerInfo.fromJson(Map<String, dynamic> j)
    : id = _s(j['id']),
      name = _s(j['name']),
      version = _s(j['version']),
      movieCount = _i(j['movieCount']),
      seriesCount = _i(j['seriesCount']),
      episodeCount = _i(j['episodeCount']),
      scanning = _b(j['scanning']);
}

class LibraryFolder {
  final String id;
  final String path;
  final String name;
  final bool available;
  final int itemCount;
  LibraryFolder.fromJson(Map<String, dynamic> j)
    : id = _s(j['id']),
      path = _s(j['path']),
      name = _s(j['name']),
      available = j['available'] != false,
      itemCount = _i(j['itemCount']);
}

class ServerSettings {
  final String serverName;
  final List<LibraryFolder> libraryFolders;
  final String tmdbApiKey;
  final bool tmdbEnabled;
  final String metadataLanguage;
  final int scanIntervalMinutes;
  ServerSettings.fromJson(Map<String, dynamic> j)
    : serverName = _s(j['serverName']),
      libraryFolders = ((j['libraryFolders'] as List?) ?? [])
          .map((e) => LibraryFolder.fromJson(e as Map<String, dynamic>))
          .toList(),
      tmdbApiKey = _s(j['tmdbApiKey']),
      tmdbEnabled = _b(j['tmdbEnabled']),
      metadataLanguage = _s(j['metadataLanguage']),
      scanIntervalMinutes = _i(j['scanIntervalMinutes']);
}

class ScanStatus {
  final bool running;
  final String phase;
  final int done;
  final int total;
  final int lastScanAt;
  final String lastError;
  ScanStatus.fromJson(Map<String, dynamic> j)
    : running = _b(j['running']),
      phase = _s(j['phase']),
      done = _i(j['done']),
      total = _i(j['total']),
      lastScanAt = _i(j['lastScanAt']),
      lastError = _s(j['lastError']);
}

class FsDir {
  final String name;
  final String path;
  FsDir.fromJson(Map<String, dynamic> j)
    : name = _s(j['name']),
      path = _s(j['path']);
}

class FsListing {
  final String path;
  final String? parent;
  final List<FsDir> dirs;
  FsListing.fromJson(Map<String, dynamic> j)
    : path = _s(j['path']),
      parent = j['parent'] as String?,
      dirs = ((j['dirs'] as List?) ?? [])
          .map((e) => FsDir.fromJson(e as Map<String, dynamic>))
          .toList();
}
