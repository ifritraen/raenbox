class BuzzBoxTabItem {
  final String tabId;
  final String name;
  final String type;

  BuzzBoxTabItem({
    required this.tabId,
    required this.name,
    required this.type,
  });

  factory BuzzBoxTabItem.fromJson(Map<String, dynamic> json) {
    return BuzzBoxTabItem(
      tabId: json['tabId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      type: json['type']?.toString() ?? 'post',
    );
  }
}

class BuzzBoxUser {
  final String userId;
  final String nickname;
  final String? avatar;

  BuzzBoxUser({
    required this.userId,
    required this.nickname,
    this.avatar,
  });

  factory BuzzBoxUser.fromJson(Map<String, dynamic> json) {
    return BuzzBoxUser(
      userId: (json['userId'] ?? json['uid'] ?? '').toString(),
      nickname: (json['nickname'] ?? json['username'] ?? 'User').toString(),
      avatar: json['avatar']?.toString(),
    );
  }
}

class BuzzBoxGroup {
  final String groupId;
  final String name;
  final String? avatar;
  final String? cover;
  final String? description;
  final int userCount;
  final int postCount;
  final bool hasJoin;
  final List<String> tags;

  BuzzBoxGroup({
    required this.groupId,
    required this.name,
    this.avatar,
    this.cover,
    this.description,
    this.userCount = 0,
    this.postCount = 0,
    this.hasJoin = false,
    this.tags = const [],
  });

  factory BuzzBoxGroup.fromJson(Map<String, dynamic> json) {
    String? coverImg;
    final rawCover = json['cover'];
    if (rawCover is Map) {
      coverImg = rawCover['url']?.toString();
    } else if (rawCover is String) {
      coverImg = rawCover;
    }

    final rawTags = json['tags'] as List<dynamic>? ?? [];
    final tagList = rawTags.map((t) => t.toString()).toList();

    return BuzzBoxGroup(
      groupId: (json['groupId'] ?? json['id'] ?? '').toString(),
      name: (json['name'] ?? json['title'] ?? 'Group').toString(),
      avatar: json['avatar']?.toString(),
      cover: coverImg ?? json['avatar']?.toString(),
      description: json['description']?.toString(),
      userCount: (json['userCount'] as num?)?.toInt() ?? 0,
      postCount: (json['postCount'] as num?)?.toInt() ?? 0,
      hasJoin: json['hasJoin'] == true,
      tags: tagList,
    );
  }
}

class BuzzBoxPost {
  final String postId;
  final String userId;
  final String content;
  final String? groupId;
  final String? subjectId;
  final String? createdAt;
  final BuzzBoxUser? user;
  final BuzzBoxGroup? group;
  final int likeCount;
  final int commentCount;
  final int shareCount;
  final bool hasLike;
  final String? mediaType; // 'VIDEO', 'IMAGE', 'GIF'
  final String? videoUrl;
  final int? videoDuration;
  final int? videoWidth;
  final int? videoHeight;
  final String? imageUrl;
  final int? imageWidth;
  final int? imageHeight;
  final String? coverUrl;

  BuzzBoxPost({
    required this.postId,
    required this.userId,
    required this.content,
    this.groupId,
    this.subjectId,
    this.createdAt,
    this.user,
    this.group,
    this.likeCount = 0,
    this.commentCount = 0,
    this.shareCount = 0,
    this.hasLike = false,
    this.mediaType,
    this.videoUrl,
    this.videoDuration,
    this.videoWidth,
    this.videoHeight,
    this.imageUrl,
    this.imageWidth,
    this.imageHeight,
    this.coverUrl,
  });

  bool get isVideo => (mediaType?.toUpperCase() == 'VIDEO' || (videoUrl != null && videoUrl!.isNotEmpty));
  bool get isImage => !isVideo && (imageUrl != null && imageUrl!.isNotEmpty);

  double get aspectRatio {
    if (videoWidth != null && videoHeight != null && videoWidth! > 0 && videoHeight! > 0) {
      return videoWidth! / videoHeight!;
    }
    if (imageWidth != null && imageHeight != null && imageWidth! > 0 && imageHeight! > 0) {
      return imageWidth! / imageHeight!;
    }
    return isVideo ? 16 / 9 : 1.0;
  }

  factory BuzzBoxPost.fromJson(Map<String, dynamic> json) {
    final postUser = json['user'] is Map<String, dynamic>
        ? BuzzBoxUser.fromJson(json['user'] as Map<String, dynamic>)
        : (json['creator'] is Map<String, dynamic>
            ? BuzzBoxUser.fromJson(json['creator'] as Map<String, dynamic>)
            : null);

    final postGroup = json['group'] is Map<String, dynamic>
        ? BuzzBoxGroup.fromJson(json['group'] as Map<String, dynamic>)
        : null;

    final stat = json['stat'] is Map<String, dynamic> ? json['stat'] as Map<String, dynamic> : null;

    String? mType;
    String? vUrl;
    int? vDuration;
    int? vWidth;
    int? vHeight;
    String? iUrl;
    int? iWidth;
    int? iHeight;
    String? cUrl;

    final media = json['media'] is Map<String, dynamic> ? json['media'] as Map<String, dynamic> : null;
    if (media != null) {
      mType = media['mediaType']?.toString();

      // Extract cover and firstFrame from media object
      final mCover = media['cover'];
      if (mCover is Map) {
        cUrl = mCover['url']?.toString();
        iWidth = (mCover['width'] as num?)?.toInt();
        iHeight = (mCover['height'] as num?)?.toInt();
      }
      final mFrame = media['firstFrame'];
      if (mFrame is Map && (cUrl == null || cUrl.isEmpty)) {
        cUrl = mFrame['url']?.toString();
        iWidth ??= (mFrame['width'] as num?)?.toInt();
        iHeight ??= (mFrame['height'] as num?)?.toInt();
      }

      final videos = media['video'] as List<dynamic>? ?? [];
      if (videos.isNotEmpty && videos[0] is Map) {
        final v = videos[0] as Map<String, dynamic>;
        vUrl = v['url']?.toString();
        vDuration = (v['duration'] as num?)?.toInt();
        vWidth = (v['width'] as num?)?.toInt();
        vHeight = (v['height'] as num?)?.toInt();
      } else if (media['url'] != null) {
        vUrl = media['url']?.toString();
      }

      final images = media['image'] as List<dynamic>? ?? [];
      if (images.isNotEmpty && images[0] is Map) {
        final im = images[0] as Map<String, dynamic>;
        iUrl = im['url']?.toString();
        iWidth ??= (im['width'] as num?)?.toInt();
        iHeight ??= (im['height'] as num?)?.toInt();
      }
    }

    // Direct image cover fallback from root
    final rawCover = json['cover'] ?? json['image'];
    if (rawCover is Map) {
      final u = rawCover['url']?.toString();
      cUrl ??= u;
      iUrl ??= u;
      iWidth ??= (rawCover['width'] as num?)?.toInt();
      iHeight ??= (rawCover['height'] as num?)?.toInt();
    } else if (rawCover is String && rawCover.isNotEmpty) {
      cUrl ??= rawCover;
      iUrl ??= rawCover;
    }

    if (vUrl == null || vUrl.isEmpty) {
      vUrl = json['videoUrl']?.toString() ?? json['playUrl']?.toString();
    }

    cUrl ??= iUrl;
    iUrl ??= cUrl;

    final id = (json['postId'] ?? json['id'] ?? '').toString();

    return BuzzBoxPost(
      postId: id,
      userId: (json['userId'] ?? postUser?.userId ?? '').toString(),
      content: (json['content'] ?? json['title'] ?? '').toString(),
      groupId: json['groupId']?.toString(),
      subjectId: json['subjectId']?.toString(),
      createdAt: json['createdAt']?.toString(),
      user: postUser,
      group: postGroup,
      likeCount: (stat?['likeCount'] as num?)?.toInt() ?? (json['likeCount'] as num?)?.toInt() ?? 0,
      commentCount: (stat?['commentCount'] as num?)?.toInt() ?? (json['commentCount'] as num?)?.toInt() ?? 0,
      shareCount: (stat?['shareCount'] as num?)?.toInt() ?? (json['shareCount'] as num?)?.toInt() ?? 0,
      hasLike: json['hasLike'] == true,
      mediaType: mType ?? (vUrl != null ? 'VIDEO' : 'IMAGE'),
      videoUrl: vUrl,
      videoDuration: vDuration,
      videoWidth: vWidth,
      videoHeight: vHeight,
      imageUrl: iUrl ?? cUrl,
      imageWidth: iWidth,
      imageHeight: iHeight,
      coverUrl: cUrl ?? iUrl,
    );
  }
}
