class MediaItem {
  final String subjectId;
  final String title;
  final String? coverUrl;
  final int subjectType; // 1: Movie, 2: Series, 9: Shorts/Clips
  final String? releaseDate;
  final String? imdbRating;
  final String? genre;
  final String? duration;
  final String? authorName;
  final String? authorAvatar;
  final bool isPost;
  final String? videoUrl;
  final String? deepLink;

  MediaItem({
    required this.subjectId,
    required this.title,
    this.coverUrl,
    required this.subjectType,
    this.releaseDate,
    this.imdbRating,
    this.genre,
    this.duration,
    this.authorName,
    this.authorAvatar,
    this.isPost = false,
    this.videoUrl,
    this.deepLink,
  });

  bool get isMovie => subjectType == 1;
  bool get isSeries => subjectType == 2;
  bool get isShort => subjectType == 9 || isPost;

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    final titleRaw = (json['title'] ?? json['name'] ?? json['content'] ?? '').toString();
    final cleanTitle = titleRaw.contains('[') ? titleRaw.split('[').first.trim() : titleRaw;

    String? cover;
    final rawCover = json['cover'] ?? json['coverImage'] ?? json['image'] ?? json['coverUrl'] ?? json['imageUrl'];
    if (rawCover is Map) {
      cover = rawCover['url']?.toString();
    } else if (rawCover is String && rawCover.isNotEmpty) {
      cover = rawCover;
    }

    String id = (json['subjectId'] ?? json['id'] ?? json['postId'] ?? '').toString();
    final dLink = json['deepLink']?.toString();
    if ((id.isEmpty || id == '0') && dLink != null && dLink.isNotEmpty) {
      final match = RegExp(r'(?:id|subjectId)=([0-9]+)').firstMatch(dLink);
      if (match != null) {
        id = match.group(1)!;
      }
    }

    final bool postFlag = json['isPost'] == true ||
        json['postId'] != null ||
        (dLink != null && (dLink.contains('/post/') || dLink.contains('detailVideo')));

    String? author;
    String? avatar;
    if (json['creator'] is Map) {
      author = json['creator']['nickname']?.toString();
      avatar = json['creator']['avatar']?.toString();
    } else if (json['user'] is Map) {
      author = json['user']['nickname']?.toString();
      avatar = json['user']['avatar']?.toString();
    }

    String? vUrl = json['videoUrl']?.toString();
    if (vUrl == null && json['media'] is Map) {
      final videos = json['media']['video'] as List<dynamic>? ?? [];
      if (videos.isNotEmpty && videos[0] is Map) {
        vUrl = videos[0]['url']?.toString();
      }
    }

    return MediaItem(
      subjectId: id,
      title: cleanTitle.isNotEmpty ? cleanTitle : 'Untitled',
      coverUrl: cover,
      subjectType: (json['subjectType'] as num?)?.toInt() ??
          (postFlag ? 9 : (json['subjectType']?.toString().toLowerCase().contains('series') == true ? 2 : 1)),
      releaseDate: json['releaseDate']?.toString(),
      imdbRating: json['imdbRatingValue']?.toString() ?? json['imdbRating']?.toString(),
      genre: json['genre']?.toString(),
      duration: json['duration']?.toString(),
      authorName: author,
      authorAvatar: avatar,
      isPost: postFlag,
      videoUrl: vUrl,
      deepLink: dLink,
    );
  }

  Map<String, dynamic> toJson() => {
        'subjectId': subjectId,
        'title': title,
        'coverUrl': coverUrl,
        'subjectType': subjectType,
        'releaseDate': releaseDate,
        'imdbRating': imdbRating,
        'genre': genre,
        'duration': duration,
        'authorName': authorName,
        'authorAvatar': authorAvatar,
        'isPost': isPost,
        'videoUrl': videoUrl,
        'deepLink': deepLink,
      };
}

class Actor {
  final String name;
  final String? character;
  final String? avatarUrl;

  Actor({required this.name, this.character, this.avatarUrl});

  factory Actor.fromJson(Map<String, dynamic> json) {
    return Actor(
      name: json['name']?.toString() ?? '',
      character: json['character']?.toString(),
      avatarUrl: json['avatarUrl']?.toString(),
    );
  }
}

class Dub {
  final String subjectId;
  final String lanName;

  Dub({required this.subjectId, required this.lanName});

  factory Dub.fromJson(Map<String, dynamic> json) {
    return Dub(
      subjectId: json['subjectId']?.toString() ?? '',
      lanName: json['lanName']?.toString() ?? 'Default',
    );
  }
}

class MediaDetail {
  final String subjectId;
  final String title;
  final String? coverUrl;
  final String? description;
  final String? releaseDate;
  final String? duration;
  final String? genre;
  final String? imdbRating;
  final String? country;
  final int subjectType;
  final List<Actor> actors;
  final List<Dub> dubs;

  MediaDetail({
    required this.subjectId,
    required this.title,
    this.coverUrl,
    this.description,
    this.releaseDate,
    this.duration,
    this.genre,
    this.imdbRating,
    this.country,
    required this.subjectType,
    required this.actors,
    required this.dubs,
  });

  bool get isMovie => subjectType == 1;
  bool get isSeries => subjectType == 2;

  factory MediaDetail.fromJson(Map<String, dynamic> json) {
    // Web BFF wraps all subject data under 'subject' key.
    // Flatten: prefer json['subject'] if present, else json itself.
    final subject = (json['subject'] is Map<String, dynamic>)
        ? json['subject'] as Map<String, dynamic>
        : json;

    final titleRaw = (subject['title'] ?? subject['name'] ?? '').toString();
    final cleanTitle = titleRaw.contains('[') ? titleRaw.split('[').first.trim() : titleRaw;

    String? cover;
    final rawCover = subject['cover'] ?? subject['coverImage'] ?? subject['image'] ?? subject['coverUrl'] ?? subject['imageUrl'];
    if (rawCover is Map) {
      cover = rawCover['url']?.toString();
    } else if (rawCover is String && rawCover.isNotEmpty) {
      cover = rawCover;
    }

    final staff = subject['staffList'] as List? ?? [];
    final actorsList = staff
        .where((s) => s['staffType'] == 1)
        .map((s) => Actor.fromJson(s as Map<String, dynamic>))
        .toList();

    final dubsList = (subject['dubs'] as List? ?? [])
        .map((d) => Dub.fromJson(d as Map<String, dynamic>))
        .toList();

    return MediaDetail(
      subjectId: (subject['subjectId'] ?? '').toString(),
      title: cleanTitle.isNotEmpty ? cleanTitle : 'Untitled',
      coverUrl: cover,
      description: subject['description']?.toString(),
      releaseDate: subject['releaseDate']?.toString(),
      duration: subject['duration']?.toString(),
      genre: subject['genre']?.toString(),
      imdbRating: subject['imdbRatingValue']?.toString(),
      country: subject['country']?.toString() ?? subject['region']?.toString(),
      subjectType: (subject['subjectType'] as num?)?.toInt() ?? 1,
      actors: actorsList,
      dubs: dubsList,
    );
  }
}


class SeasonInfo {
  final int seasonNumber;
  final int maxEp;

  SeasonInfo({required this.seasonNumber, required this.maxEp});

  factory SeasonInfo.fromJson(Map<String, dynamic> json) {
    return SeasonInfo(
      seasonNumber: (json['se'] as num?)?.toInt() ?? 1,
      maxEp: (json['maxEp'] as num?)?.toInt() ?? 1,
    );
  }
}

class StreamLink {
  final String id;
  final String format;
  final String resolutions;
  final String rawUrl;
  final String url;
  final String? signCookie;
  final int duration;
  final List<CaptionTrack> captions;

  StreamLink({
    required this.id,
    required this.format,
    required this.resolutions,
    String? rawUrl,
    required this.url,
    this.signCookie,
    this.duration = 0,
    this.captions = const [],
  }) : rawUrl = rawUrl ?? url;

  bool get isRealStream =>
      !url.contains('b164fbfb43477929') && !url.contains('macdn.aoneroom.com/other/');

  List<String> get availableResolutions =>
      resolutions.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  factory StreamLink.fromJson(Map<String, dynamic> json, {String? resolvedUrl}) {
    final raw = json['url']?.toString() ?? '';
    final finalUrl = resolvedUrl ?? raw;
    final fmt = finalUrl.contains('.mpd') || finalUrl.contains('/dash/')
        ? 'DASH'
        : (finalUrl.contains('.m3u8') ? 'HLS' : (json['format']?.toString() ?? 'MP4'));

    return StreamLink(
      id: json['id']?.toString() ?? '',
      format: fmt,
      resolutions: json['resolutions']?.toString() ?? '1080,720,480',
      rawUrl: raw,
      url: finalUrl,
      signCookie: json['signCookie']?.toString(),
      duration: (json['duration'] as num?)?.toInt() ?? 0,
    );
  }
}

class CaptionTrack {
  final String language;
  final String lanName;
  final String url;

  CaptionTrack({
    required this.language,
    required this.lanName,
    required this.url,
  });

  factory CaptionTrack.fromJson(Map<String, dynamic> json) {
    return CaptionTrack(
      language: json['language']?.toString() ?? 'en',
      lanName: json['lanName']?.toString() ?? json['language']?.toString() ?? 'English',
      url: json['url']?.toString() ?? '',
    );
  }
}

class ComingSoonItem {
  final String title;
  final String date;
  final String bookedCount;
  final String? coverUrl;

  ComingSoonItem({
    required this.title,
    required this.date,
    required this.bookedCount,
    this.coverUrl,
  });
}

class LocalRecord {
  final String subjectId;
  final String title;
  final String? coverUrl;
  final int subjectType;
  final DateTime updatedAt;
  int positionSeconds;
  int durationSeconds;
  bool isFavorite;
  bool isBookmarked;
  String? downloadPath;
  String? audioDownloadPath;
  List<String> categories;

  LocalRecord({
    required this.subjectId,
    required this.title,
    this.coverUrl,
    required this.subjectType,
    required this.updatedAt,
    this.positionSeconds = 0,
    this.durationSeconds = 0,
    this.isFavorite = false,
    this.isBookmarked = false,
    this.downloadPath,
    this.audioDownloadPath,
    List<String>? categories,
  }) : categories = categories ?? [];

  LocalRecord copyWith({
    String? subjectId,
    String? title,
    String? coverUrl,
    int? subjectType,
    DateTime? updatedAt,
    int? positionSeconds,
    int? durationSeconds,
    bool? isFavorite,
    bool? isBookmarked,
    String? downloadPath,
    String? audioDownloadPath,
    List<String>? categories,
  }) => LocalRecord(
    subjectId: subjectId ?? this.subjectId,
    title: title ?? this.title,
    coverUrl: coverUrl ?? this.coverUrl,
    subjectType: subjectType ?? this.subjectType,
    updatedAt: updatedAt ?? this.updatedAt,
    positionSeconds: positionSeconds ?? this.positionSeconds,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    isFavorite: isFavorite ?? this.isFavorite,
    isBookmarked: isBookmarked ?? this.isBookmarked,
    downloadPath: downloadPath ?? this.downloadPath,
    audioDownloadPath: audioDownloadPath ?? this.audioDownloadPath,
    categories: categories != null ? List<String>.from(categories) : List<String>.from(this.categories),
  );

  double get progressPercent {
    if (durationSeconds <= 0) return 0.0;
    return (positionSeconds / durationSeconds).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'subjectId': subjectId,
        'title': title,
        'coverUrl': coverUrl,
        'subjectType': subjectType,
        'updatedAt': updatedAt.toIso8601String(),
        'positionSeconds': positionSeconds,
        'durationSeconds': durationSeconds,
        'isFavorite': isFavorite,
        'isBookmarked': isBookmarked,
        'downloadPath': downloadPath,
        'audioDownloadPath': audioDownloadPath,
        'categories': categories,
      };

  factory LocalRecord.fromJson(Map<String, dynamic> json) => LocalRecord(
        subjectId: json['subjectId'] ?? '',
        title: json['title'] ?? '',
        coverUrl: json['coverUrl'],
        subjectType: json['subjectType'] ?? 1,
        updatedAt: DateTime.tryParse(json['updatedAt'] ?? '') ?? DateTime.now(),
        positionSeconds: json['positionSeconds'] ?? 0,
        durationSeconds: json['durationSeconds'] ?? 0,
        isFavorite: json['isFavorite'] ?? false,
        isBookmarked: json['isBookmarked'] ?? false,
        downloadPath: json['downloadPath'],
        audioDownloadPath: json['audioDownloadPath'],
        categories: (json['categories'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
      );
}
