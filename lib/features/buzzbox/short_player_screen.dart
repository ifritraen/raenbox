import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/moviebox_models.dart';
import '../../data/models/buzzbox_models.dart';
import '../../data/services/moviebox_api_service.dart';

class ShortVideoPlayerScreen extends StatefulWidget {
  final List<MediaItem>? items;
  final List<BuzzBoxPost>? posts;
  final int initialIndex;
  final MovieBoxApiService apiService;

  const ShortVideoPlayerScreen({
    super.key,
    this.items,
    this.posts,
    this.initialIndex = 0,
    required this.apiService,
  }) : assert(items != null || posts != null, 'Either items or posts must be provided');

  @override
  State<ShortVideoPlayerScreen> createState() => _ShortVideoPlayerScreenState();
}

class _ShortVideoPlayerScreenState extends State<ShortVideoPlayerScreen> {
  late PageController _pageController;
  late int _currentIndex;
  bool _isMuted = false;

  int get _itemCount => widget.items?.length ?? widget.posts?.length ?? 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, _itemCount > 0 ? _itemCount - 1 : 0);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
  }

  @override
  Widget build(BuildContext context) {
    if (_itemCount == 0) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: const Center(
          child: Text(
            'No short videos available',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: _itemCount,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
            },
            itemBuilder: (context, index) {
              final isCurrent = index == _currentIndex;
              final mediaItem = widget.items != null && index < widget.items!.length
                  ? widget.items![index]
                  : null;
              final post = widget.posts != null && index < widget.posts!.length
                  ? widget.posts![index]
                  : null;

              return _ShortVideoPage(
                mediaItem: mediaItem,
                post: post,
                isCurrent: isCurrent,
                isMuted: _isMuted,
                apiService: widget.apiService,
                onToggleMute: _toggleMute,
              );
            },
          ),

          // Top Header Overlay: Back Button & Sound Toggle
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 14,
            right: 14,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _toggleMute,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isMuted ? Icons.volume_off : Icons.volume_up,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortVideoPage extends StatefulWidget {
  final MediaItem? mediaItem;
  final BuzzBoxPost? post;
  final bool isCurrent;
  final bool isMuted;
  final MovieBoxApiService apiService;
  final VoidCallback onToggleMute;

  const _ShortVideoPage({
    required this.mediaItem,
    required this.post,
    required this.isCurrent,
    required this.isMuted,
    required this.apiService,
    required this.onToggleMute,
  });

  @override
  State<_ShortVideoPage> createState() => _ShortVideoPageState();
}

class _ShortVideoPageState extends State<_ShortVideoPage> with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _isLoading = true;
  bool _isLiked = false;
  int _likeCount = 0;
  bool _showHeartAnimation = false;
  late AnimationController _heartAnimController;
  late Animation<double> _heartScale;

  String? _resolvedVideoUrl;
  String? _authorName;
  String? _authorAvatar;
  String? _caption;
  String? _coverUrl;

  @override
  void initState() {
    super.initState();
    _initHeartAnimation();
    _extractMetadata();

    if (widget.isCurrent) {
      _initializeVideo();
    }
  }

  void _initHeartAnimation() {
    _heartAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _heartScale = Tween<double>(begin: 0.0, end: 1.3).animate(
      CurvedAnimation(parent: _heartAnimController, curve: Curves.elasticOut),
    );
  }

  void _extractMetadata() {
    if (widget.post != null) {
      final p = widget.post!;
      _resolvedVideoUrl = p.videoUrl;
      _authorName = p.user?.nickname.isNotEmpty == true ? p.user!.nickname : 'BuzzBox Creator';
      _authorAvatar = p.user?.avatar;
      _caption = p.content;
      _coverUrl = p.coverUrl;
      _isLiked = p.hasLike;
      _likeCount = p.likeCount;
    } else if (widget.mediaItem != null) {
      final m = widget.mediaItem!;
      _resolvedVideoUrl = m.videoUrl;
      _authorName = m.authorName ?? 'Short Creator';
      _authorAvatar = m.authorAvatar;
      _caption = m.title;
      _coverUrl = m.coverUrl;
      _likeCount = 1200 + (m.subjectId.hashCode % 8000).abs();
    }
  }

  @override
  void didUpdateWidget(covariant _ShortVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isMuted != oldWidget.isMuted && _controller != null && _controller!.value.isInitialized) {
      _controller!.setVolume(widget.isMuted ? 0.0 : 1.0);
    }

    if (widget.isCurrent && !oldWidget.isCurrent) {
      if (_controller != null && _controller!.value.isInitialized) {
        _controller!.play();
      } else {
        _initializeVideo();
      }
    } else if (!widget.isCurrent && oldWidget.isCurrent) {
      _controller?.pause();
    }
  }

  Future<void> _initializeVideo() async {
    setState(() => _isLoading = true);

    // If video URL is not present, fetch post detail
    if (_resolvedVideoUrl == null || _resolvedVideoUrl!.isEmpty) {
      final postId = widget.post?.postId ?? widget.mediaItem?.subjectId;
      if (postId != null && postId.isNotEmpty && postId != '0') {
        try {
          final detail = await widget.apiService.fetchPostDetail(postId);
          if (detail != null && detail.videoUrl != null && detail.videoUrl!.isNotEmpty) {
            _resolvedVideoUrl = detail.videoUrl;
            if (_caption == null || _caption!.isEmpty) _caption = detail.content;
            if (_authorName == null || _authorName!.isEmpty) _authorName = detail.user?.nickname;
            _authorAvatar ??= detail.user?.avatar;
          }
        } catch (_) {}
      }
    }

    if (_resolvedVideoUrl != null && _resolvedVideoUrl!.isNotEmpty) {
      try {
        final uri = Uri.parse(_resolvedVideoUrl!);
        _controller?.dispose();
        _controller = VideoPlayerController.networkUrl(uri);
        await _controller!.initialize();
        await _controller!.setLooping(true);
        await _controller!.setVolume(widget.isMuted ? 0.0 : 1.0);

        if (mounted && widget.isCurrent) {
          await _controller!.play();
          setState(() => _isLoading = false);
        } else if (mounted) {
          setState(() => _isLoading = false);
        }
      } catch (e) {
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _heartAnimController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  void _onDoubleTap(Offset position) {
    setState(() {
      _isLiked = true;
      _likeCount++;
      _showHeartAnimation = true;
    });
    _heartAnimController.forward(from: 0.0).then((_) {
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) setState(() => _showHeartAnimation = false);
        });
      }
    });
  }

  void _togglePlayPause() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
    });
  }

  void _toggleLike() {
    setState(() {
      _isLiked = !_isLiked;
      _likeCount += _isLiked ? 1 : -1;
    });
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return GestureDetector(
      onTap: _togglePlayPause,
      onDoubleTapDown: (details) => _onDoubleTap(details.localPosition),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Video Player or Poster Placeholder
          if (_controller != null && _controller!.value.isInitialized)
            Center(
              child: SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller!.value.size.width > 0 ? _controller!.value.size.width : size.width,
                    height: _controller!.value.size.height > 0 ? _controller!.value.size.height : size.height,
                    child: VideoPlayer(_controller!),
                  ),
                ),
              ),
            )
          else if (_coverUrl != null && _coverUrl!.isNotEmpty)
            CachedNetworkImage(
              imageUrl: _coverUrl!,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(color: Colors.black),
              errorWidget: (context, url, error) => Container(color: Colors.black),
            )
          else
            Container(color: Colors.black),

          // Dark Gradient Vignette for Readability
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.35),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.8),
                  ],
                  stops: const [0.0, 0.2, 0.65, 1.0],
                ),
              ),
            ),
          ),

          // Loading Indicator
          if (_isLoading)
            Center(
              child: CircularProgressIndicator(color: AppTheme.accentGreen),
            ),

          // Pause Overlay Icon
          if (_controller != null &&
              _controller!.value.isInitialized &&
              !_controller!.value.isPlaying &&
              !_isLoading)
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white70,
                  size: 56,
                ),
              ),
            ),

          // Double Tap Animated Spring Heart
          if (_showHeartAnimation)
            Center(
              child: ScaleTransition(
                scale: _heartScale,
                child: const Icon(
                  Icons.favorite,
                  color: Colors.redAccent,
                  size: 110,
                ),
              ),
            ),

          // Bottom Left: Author & Caption
          Positioned(
            left: 16,
            right: 80,
            bottom: MediaQuery.of(context).padding.bottom + 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: AppTheme.bgSurface,
                      backgroundImage: _authorAvatar != null && _authorAvatar!.isNotEmpty
                          ? CachedNetworkImageProvider(_authorAvatar!)
                          : null,
                      child: _authorAvatar == null
                          ? const Icon(Icons.person, color: Colors.white70, size: 18)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '@${_authorName ?? "creator"}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_caption != null && _caption!.isNotEmpty)
                  Text(
                    _caption!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.3,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.music_note, color: AppTheme.accentGreen, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'Original Audio • RaenBox Shorts',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Bottom Right Vertical Actions Rail (Like, Comment, Share)
          Positioned(
            right: 14,
            bottom: MediaQuery.of(context).padding.bottom + 28,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Like Button
                GestureDetector(
                  onTap: _toggleLike,
                  child: Column(
                    children: [
                      Icon(
                        _isLiked ? Icons.favorite : Icons.favorite_border,
                        color: _isLiked ? Colors.redAccent : Colors.white,
                        size: 34,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatCount(_likeCount),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Comment Button
                Column(
                  children: [
                    const Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatCount((_likeCount / 7).round()),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Share Button
                Column(
                  children: [
                    const Icon(
                      Icons.share_outlined,
                      color: Colors.white,
                      size: 30,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Share',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
