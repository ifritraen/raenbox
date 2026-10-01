import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/buzzbox_models.dart';
import '../../data/services/moviebox_api_service.dart';
import '../../data/services/local_storage_service.dart';
import 'short_player_screen.dart';

class BuzzBoxTab extends StatefulWidget {
  final MovieBoxApiService apiService;
  final LocalStorageService storage;

  const BuzzBoxTab({
    super.key,
    required this.apiService,
    required this.storage,
  });

  @override
  State<BuzzBoxTab> createState() => _BuzzBoxTabState();
}

class _BuzzBoxTabState extends State<BuzzBoxTab> {
  List<BuzzBoxTabItem> _subTabs = [];
  int _activeSubTabIndex = 0;
  List<BuzzBoxGroup> _trendingGroups = [];

  // Feed State per TabId
  final Map<String, List<BuzzBoxPost>> _postsCache = {};
  final Map<String, int> _pages = {};
  final Map<String, bool> _hasMore = {};
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;

  // Viewport Focus-based Autoplay State
  String? _focusedPostId;
  bool _isFeedMuted = true;
  final Map<String, GlobalKey> _cardKeys = {};

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _initBuzzBox();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    _updateFocusedPost();
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 300) {
      if (!_isLoadingMore && !_isLoadingInitial) {
        _loadMore();
      }
    }
  }

  void _updateFocusedPost() {
    if (!mounted) return;
    final screenHeight = MediaQuery.of(context).size.height;
    final screenCenter = screenHeight * 0.45;
    String? closestId;
    double minDistance = double.infinity;

    for (final entry in _cardKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx != null) {
        final box = ctx.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          final pos = box.localToGlobal(Offset.zero);
          final itemCenter = pos.dy + (box.size.height / 2);
          final dist = (itemCenter - screenCenter).abs();
          if (pos.dy < screenHeight && (pos.dy + box.size.height) > 0) {
            if (dist < minDistance) {
              minDistance = dist;
              closestId = entry.key;
            }
          }
        }
      }
    }
    if (closestId != null && closestId != _focusedPostId) {
      setState(() {
        _focusedPostId = closestId;
      });
    }
  }

  Future<void> _initBuzzBox() async {
    setState(() => _isLoadingInitial = true);
    try {
      final results = await Future.wait([
        widget.apiService.fetchCommunityTabs(),
        widget.apiService.fetchCommunityTrendingEntrance(),
      ]);

      if (mounted) {
        setState(() {
          _subTabs = results[0] as List<BuzzBoxTabItem>;
          _trendingGroups = results[1] as List<BuzzBoxGroup>;
        });
      }

      if (_subTabs.isNotEmpty) {
        await _loadPostsForTab(_subTabs[_activeSubTabIndex].tabId, isRefresh: true);
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isLoadingInitial = false);
        WidgetsBinding.instance.addPostFrameCallback((_) => _updateFocusedPost());
      }
    }
  }

  String get _currentTabId {
    if (_subTabs.isEmpty || _activeSubTabIndex >= _subTabs.length) return 'explore';
    return _subTabs[_activeSubTabIndex].tabId;
  }

  Future<void> _loadPostsForTab(String tabId, {bool isRefresh = false}) async {
    final page = isRefresh ? 1 : (_pages[tabId] ?? 1);
    try {
      final posts = await widget.apiService.fetchBuzzBoxPosts(tabId, page: page, perPage: 12);
      if (mounted) {
        setState(() {
          if (isRefresh) {
            _postsCache[tabId] = posts;
            _pages[tabId] = 2;
            _hasMore[tabId] = posts.isNotEmpty;
            if (posts.isNotEmpty) {
              _focusedPostId = tabId == 'discover' ? 'disc_${posts.first.postId}' : posts.first.postId;
            }
          } else {
            final current = _postsCache[tabId] ?? [];
            final existingIds = current.map((p) => p.postId).toSet();
            final unique = posts.where((p) => existingIds.add(p.postId)).toList();
            _postsCache[tabId] = [...current, ...unique];
            _pages[tabId] = page + 1;
            _hasMore[tabId] = posts.length >= 8;
          }
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _updateFocusedPost());
      }
    } catch (_) {}
  }

  Future<void> _refreshCurrent() async {
    final tabId = _currentTabId;
    await _loadPostsForTab(tabId, isRefresh: true);
  }

  Future<void> _loadMore() async {
    final tabId = _currentTabId;
    if (_hasMore[tabId] == false || _isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    await _loadPostsForTab(tabId, isRefresh: false);
    if (mounted) {
      setState(() => _isLoadingMore = false);
    }
  }

  void _onSubTabSelected(int index) {
    if (_activeSubTabIndex == index) return;
    setState(() {
      _activeSubTabIndex = index;
      _focusedPostId = null;
    });

    final tabId = _subTabs[index].tabId;
    if (!_postsCache.containsKey(tabId) || _postsCache[tabId]!.isEmpty) {
      setState(() => _isLoadingInitial = true);
      _loadPostsForTab(tabId, isRefresh: true).then((_) {
        if (mounted) setState(() => _isLoadingInitial = false);
      });
    } else {
      final cached = _postsCache[tabId]!;
      if (cached.isNotEmpty) {
        _focusedPostId = tabId == 'discover' ? 'disc_${cached.first.postId}' : cached.first.postId;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateFocusedPost());
    }
  }

  void _openGroupDetails(BuzzBoxGroup group) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupDetailScreen(
          group: group,
          apiService: widget.apiService,
          storage: widget.storage,
        ),
      ),
    );
  }

  void _openPostDetail(BuzzBoxPost post) {
    if (post.isVideo) {
      final currentPosts = _postsCache[_currentTabId] ?? [post];
      final idx = currentPosts.indexWhere((p) => p.postId == post.postId);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ShortVideoPlayerScreen(
            posts: currentPosts,
            initialIndex: idx >= 0 ? idx : 0,
            apiService: widget.apiService,
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PostDetailScreen(post: post),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPosts = _postsCache[_currentTabId] ?? [];

    return RefreshIndicator(
      onRefresh: _refreshCurrent,
      color: AppTheme.accentGreen,
      backgroundColor: AppTheme.bgCard,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          _updateFocusedPost();
          return false;
        },
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // 1. Trending Groups Entrance Row
            if (_trendingGroups.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildTrendingGroupsSection(),
              ),

            // 2. Sub-Tabs Filter Row (For You, Discover, Images, Nearby)
            if (_subTabs.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildSubTabsHeader(),
              ),

            // 3. Main Content
            if (_isLoadingInitial)
              SliverToBoxAdapter(
                child: Container(
                  height: 300,
                  alignment: Alignment.center,
                  child: CircularProgressIndicator(color: AppTheme.accentGreen),
                ),
              )
            else if (currentPosts.isEmpty)
              SliverToBoxAdapter(
                child: Container(
                  height: 260,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.forum_outlined, size: 48, color: AppTheme.textMuted),
                      const SizedBox(height: 12),
                      Text(
                        'No community posts available',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _refreshCurrent,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Refresh'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentGreen,
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (_currentTabId == 'discover')
              // 2-Column Masonry Grid for Discover
              _buildDiscoverGrid(currentPosts)
            else
              // Full-Width Social Cards Feed for For You, Images, Nearby
              _buildSocialFeed(currentPosts),

            // Loading more indicator
            if (_isLoadingMore)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: CircularProgressIndicator(color: AppTheme.accentGreen, strokeWidth: 2.5),
                  ),
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // Channels / Groups Entrance Row
  // -------------------------------------------------------------
  Widget _buildTrendingGroupsSection() {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      height: 96,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: _trendingGroups.length,
        itemBuilder: (context, index) {
          final group = _trendingGroups[index];
          return GestureDetector(
            onTap: () => _openGroupDetails(group),
            child: Container(
              width: 72,
              margin: const EdgeInsets.only(right: 12),
              child: Column(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: AppTheme.bgSurface,
                        backgroundImage: group.avatar != null && group.avatar!.isNotEmpty
                            ? CachedNetworkImageProvider(group.avatar!)
                            : null,
                        child: group.avatar == null || group.avatar!.isEmpty
                            ? const Icon(Icons.group, color: Colors.white70, size: 26)
                            : null,
                      ),
                      if (group.userCount > 0)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppTheme.bgCard,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppTheme.borderSubtle),
                            ),
                            child: Text(
                              _formatCount(group.userCount),
                              style: TextStyle(
                                color: AppTheme.accentGreen,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    group.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------
  // Sub-Tabs Header (For You, Discover, Images, Nearby)
  // -------------------------------------------------------------
  Widget _buildSubTabsHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(_subTabs.length, (index) {
            final tab = _subTabs[index];
            final isSelected = _activeSubTabIndex == index;
            IconData iconData;
            switch (tab.tabId) {
              case 'discover':
                iconData = Icons.explore;
                break;
              case 'images':
                iconData = Icons.photo_library;
                break;
              case 'nearby':
                iconData = Icons.near_me;
                break;
              default:
                iconData = Icons.whatshot;
                break;
            }

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => _onSubTabSelected(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.accentGreen : AppTheme.bgSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? AppTheme.accentGreen : AppTheme.borderSubtle,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        iconData,
                        size: 15,
                        color: isSelected ? Colors.black : Colors.white70,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        tab.name,
                        style: TextStyle(
                          color: isSelected ? Colors.black : Colors.white70,
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // Discover 2-Column Staggered Grid
  // -------------------------------------------------------------
  Widget _buildDiscoverGrid(List<BuzzBoxPost> posts) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.65,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final post = posts[index];
            final keyId = 'disc_${post.postId}';
            return _DiscoverPostCard(
              key: _cardKeys.putIfAbsent(keyId, () => GlobalKey()),
              post: post,
              isFocused: _focusedPostId == keyId,
              isMuted: _isFeedMuted,
              onTap: () => _openPostDetail(post),
            );
          },
          childCount: posts.length,
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // Full-Width Social Feed (For You, Images, Nearby)
  // -------------------------------------------------------------
  Widget _buildSocialFeed(List<BuzzBoxPost> posts) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final post = posts[index];
          return _SocialPostCard(
            key: _cardKeys.putIfAbsent(post.postId, () => GlobalKey()),
            post: post,
            isFocused: _focusedPostId == post.postId,
            isMuted: _isFeedMuted,
            onToggleMute: () => setState(() => _isFeedMuted = !_isFeedMuted),
            onTap: () => _openPostDetail(post),
            onGroupTap: post.group != null ? () => _openGroupDetails(post.group!) : null,
          );
        },
        childCount: posts.length,
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return count.toString();
  }
}

// -------------------------------------------------------------
// Social Post Card (For You Feed with Focus Autoplay Video)
// -------------------------------------------------------------
class _SocialPostCard extends StatefulWidget {
  final BuzzBoxPost post;
  final bool isFocused;
  final bool isMuted;
  final VoidCallback onToggleMute;
  final VoidCallback onTap;
  final VoidCallback? onGroupTap;

  const _SocialPostCard({
    super.key,
    required this.post,
    required this.isFocused,
    required this.isMuted,
    required this.onToggleMute,
    required this.onTap,
    this.onGroupTap,
  });

  @override
  State<_SocialPostCard> createState() => _SocialPostCardState();
}

class _SocialPostCardState extends State<_SocialPostCard> {
  late bool _hasLike;
  late int _likeCount;
  VideoPlayerController? _videoController;
  bool _isInitializing = false;

  @override
  void initState() {
    super.initState();
    _hasLike = widget.post.hasLike;
    _likeCount = widget.post.likeCount;

    if (widget.isFocused && widget.post.isVideo) {
      _startPlayback();
    }
  }

  @override
  void didUpdateWidget(_SocialPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isMuted != oldWidget.isMuted && _videoController != null && _videoController!.value.isInitialized) {
      _videoController!.setVolume(widget.isMuted ? 0.0 : 1.0);
    }

    if (widget.isFocused != oldWidget.isFocused) {
      if (widget.isFocused) {
        _startPlayback();
      } else {
        _pauseAndReleasePlayback();
      }
    }
  }

  Future<void> _startPlayback() async {
    if (!widget.post.isVideo || widget.post.videoUrl == null || widget.post.videoUrl!.isEmpty) return;
    if (_videoController != null && _videoController!.value.isInitialized) {
      _videoController!.play();
      return;
    }
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      final uri = Uri.parse(widget.post.videoUrl!);
      final controller = VideoPlayerController.networkUrl(uri);
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(widget.isMuted ? 0.0 : 1.0);
      if (mounted && widget.isFocused) {
        _videoController = controller;
        await _videoController!.play();
        setState(() {});
      } else {
        controller.dispose();
      }
    } catch (_) {
    } finally {
      _isInitializing = false;
    }
  }

  void _pauseAndReleasePlayback() {
    if (_videoController != null) {
      _videoController!.pause();
      _videoController!.dispose();
      _videoController = null;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  void _toggleLike() {
    setState(() {
      _hasLike = !_hasLike;
      _likeCount += _hasLike ? 1 : -1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final user = post.user;
    final group = post.group;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Author & Group Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppTheme.bgSurface,
                  backgroundImage: user?.avatar != null && user!.avatar!.isNotEmpty
                      ? CachedNetworkImageProvider(user.avatar!)
                      : null,
                  child: user?.avatar == null || user!.avatar!.isEmpty
                      ? const Icon(Icons.person, color: Colors.white54, size: 18)
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.nickname.isNotEmpty == true ? user!.nickname : 'BuzzBox Creator',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (group != null)
                        GestureDetector(
                          onTap: widget.onGroupTap,
                          child: Text(
                            'in ${group.name}',
                            style: TextStyle(
                              color: AppTheme.accentGreen,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                if (group != null && !group.hasJoin)
                  TextButton(
                    onPressed: widget.onGroupTap,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      backgroundColor: AppTheme.accentGreen.withValues(alpha: 0.15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                      'Join',
                      style: TextStyle(
                        color: AppTheme.accentGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // 2. Post Content / Caption
          if (post.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Text(
                post.content,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.35,
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),

          // 3. Media Viewer (Autoplay Video or High-res Cover/Image)
          if (_videoController != null && _videoController!.value.isInitialized)
            GestureDetector(
              onTap: widget.onTap,
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 440),
                color: Colors.black,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio > 0
                          ? _videoController!.value.aspectRatio
                          : post.aspectRatio,
                      child: VideoPlayer(_videoController!),
                    ),
                    // Sound Mute/Unmute Toggle
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: GestureDetector(
                        onTap: widget.onToggleMute,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            widget.isMuted ? Icons.volume_off : Icons.volume_up,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                    // Tap to full screen indicator badge
                    Positioned(
                      bottom: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.fullscreen, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text('Tap for Full Screen', style: TextStyle(color: Colors.white, fontSize: 10)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (post.coverUrl != null && post.coverUrl!.isNotEmpty)
            GestureDetector(
              onTap: widget.onTap,
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 400),
                color: Colors.black,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AspectRatio(
                      aspectRatio: post.aspectRatio,
                      child: CachedNetworkImage(
                        imageUrl: post.coverUrl!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        placeholder: (context, url) => Container(
                          color: AppTheme.bgSurface,
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentGreen),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: AppTheme.bgSurface,
                          child: const Icon(Icons.broken_image, color: Colors.white30),
                        ),
                      ),
                    ),
                    if (post.isVideo)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.accentGreen, width: 1.5),
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                  ],
                ),
              ),
            ),

          // 4. Social Action Footer (Like, Comment, Share)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: _toggleLike,
                      child: Row(
                        children: [
                          Icon(
                            _hasLike ? Icons.favorite : Icons.favorite_border,
                            color: _hasLike ? Colors.redAccent : AppTheme.textMuted,
                            size: 20,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$_likeCount',
                            style: TextStyle(
                              color: _hasLike ? Colors.redAccent : AppTheme.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    GestureDetector(
                      onTap: widget.onTap,
                      child: Row(
                        children: [
                          Icon(Icons.chat_bubble_outline, color: AppTheme.textMuted, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            '${post.commentCount}',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Post link copied to clipboard')),
                    );
                  },
                  child: Icon(Icons.share_outlined, color: AppTheme.textMuted, size: 18),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// Discover Post Card (Pinterest-Style Masonry Card with Preview)
// -------------------------------------------------------------
class _DiscoverPostCard extends StatefulWidget {
  final BuzzBoxPost post;
  final bool isFocused;
  final bool isMuted;
  final VoidCallback onTap;

  const _DiscoverPostCard({
    super.key,
    required this.post,
    required this.isFocused,
    required this.isMuted,
    required this.onTap,
  });

  @override
  State<_DiscoverPostCard> createState() => _DiscoverPostCardState();
}

class _DiscoverPostCardState extends State<_DiscoverPostCard> {
  VideoPlayerController? _videoController;
  bool _isInitializing = false;

  @override
  void initState() {
    super.initState();
    if (widget.isFocused && widget.post.isVideo) {
      _startPlayback();
    }
  }

  @override
  void didUpdateWidget(_DiscoverPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFocused != oldWidget.isFocused) {
      if (widget.isFocused) {
        _startPlayback();
      } else {
        _pauseAndReleasePlayback();
      }
    }
  }

  Future<void> _startPlayback() async {
    if (!widget.post.isVideo || widget.post.videoUrl == null || widget.post.videoUrl!.isEmpty) return;
    if (_videoController != null && _videoController!.value.isInitialized) {
      _videoController!.play();
      return;
    }
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      final uri = Uri.parse(widget.post.videoUrl!);
      final controller = VideoPlayerController.networkUrl(uri);
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(widget.isMuted ? 0.0 : 1.0);
      if (mounted && widget.isFocused) {
        _videoController = controller;
        await _videoController!.play();
        setState(() {});
      } else {
        controller.dispose();
      }
    } catch (_) {
    } finally {
      _isInitializing = false;
    }
  }

  void _pauseAndReleasePlayback() {
    if (_videoController != null) {
      _videoController!.pause();
      _videoController!.dispose();
      _videoController = null;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.borderSubtle),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_videoController != null && _videoController!.value.isInitialized)
                    FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _videoController!.value.size.width,
                        height: _videoController!.value.size.height,
                        child: VideoPlayer(_videoController!),
                      ),
                    )
                  else if (post.coverUrl != null && post.coverUrl!.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: post.coverUrl!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: AppTheme.bgSurface,
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentGreen),
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: AppTheme.bgSurface,
                        child: const Icon(Icons.movie, color: Colors.white30),
                      ),
                    )
                  else
                    Container(color: AppTheme.bgSurface),
                  if (post.isVideo)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _videoController != null && _videoController!.value.isPlaying
                              ? Icons.graphic_eq_rounded
                              : Icons.play_arrow_rounded,
                          color: AppTheme.accentGreen,
                          size: 14,
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black87],
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 8,
                                backgroundImage: post.user?.avatar != null && post.user!.avatar!.isNotEmpty
                                    ? CachedNetworkImageProvider(post.user!.avatar!)
                                    : null,
                              ),
                              const SizedBox(width: 4),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 75),
                                child: Text(
                                  post.user?.nickname ?? 'Creator',
                                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              const Icon(Icons.favorite, color: Colors.redAccent, size: 11),
                              const SizedBox(width: 2),
                              Text(
                                '${post.likeCount}',
                                style: const TextStyle(color: Colors.white70, fontSize: 10),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (post.content.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Text(
                  post.content,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// Full-Screen Dedicated Group Detail Screen
// -------------------------------------------------------------
class GroupDetailScreen extends StatefulWidget {
  final BuzzBoxGroup group;
  final MovieBoxApiService apiService;
  final LocalStorageService storage;

  const GroupDetailScreen({
    super.key,
    required this.group,
    required this.apiService,
    required this.storage,
  });

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  late bool _hasJoin;
  late int _userCount;
  List<BuzzBoxPost> _groupPosts = [];
  bool _isLoading = true;

  // Viewport Focus Autoplay for Group Page
  String? _focusedPostId;
  final Map<String, GlobalKey> _cardKeys = {};
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _hasJoin = widget.group.hasJoin;
    _userCount = widget.group.userCount;
    _scrollController.addListener(_updateFocusedPost);
    _loadGroupData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _updateFocusedPost() {
    if (!mounted) return;
    final screenHeight = MediaQuery.of(context).size.height;
    final screenCenter = screenHeight * 0.45;
    String? closestId;
    double minDistance = double.infinity;

    for (final entry in _cardKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx != null) {
        final box = ctx.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          final pos = box.localToGlobal(Offset.zero);
          final itemCenter = pos.dy + (box.size.height / 2);
          final dist = (itemCenter - screenCenter).abs();
          if (pos.dy < screenHeight && (pos.dy + box.size.height) > 0) {
            if (dist < minDistance) {
              minDistance = dist;
              closestId = entry.key;
            }
          }
        }
      }
    }
    if (closestId != null && closestId != _focusedPostId) {
      setState(() {
        _focusedPostId = closestId;
      });
    }
  }

  Future<void> _loadGroupData() async {
    try {
      final posts = await widget.apiService.fetchGroupPosts(widget.group.groupId, page: 1);
      if (mounted) {
        setState(() {
          _groupPosts = posts;
          _isLoading = false;
          if (posts.isNotEmpty && _focusedPostId == null) {
            _focusedPostId = posts.first.postId;
          }
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _updateFocusedPost());
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toggleJoin() {
    setState(() {
      _hasJoin = !_hasJoin;
      _userCount += _hasJoin ? 1 : -1;
    });
  }

  void _openPostDetail(BuzzBoxPost post) {
    if (post.isVideo) {
      final idx = _groupPosts.indexWhere((p) => p.postId == post.postId);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ShortVideoPlayerScreen(
            posts: _groupPosts,
            initialIndex: idx >= 0 ? idx : 0,
            apiService: widget.apiService,
          ),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PostDetailScreen(post: post),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;

    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppTheme.bgPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          group.name,
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadGroupData,
        color: AppTheme.accentGreen,
        backgroundColor: AppTheme.bgCard,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            _updateFocusedPost();
            return false;
          },
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Group Banner & Header Profile
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: AppTheme.bgSurface,
                            backgroundImage: group.avatar != null && group.avatar!.isNotEmpty
                                ? CachedNetworkImageProvider(group.avatar!)
                                : null,
                            child: group.avatar == null || group.avatar!.isEmpty
                                ? const Icon(Icons.group, color: Colors.white70, size: 28)
                                : null,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  group.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$_userCount members • ${group.postCount} posts',
                                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed: _toggleJoin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _hasJoin ? AppTheme.bgSurface : AppTheme.accentGreen,
                              foregroundColor: _hasJoin ? Colors.white : Colors.black,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            ),
                            child: Text(_hasJoin ? 'Joined' : 'Join'),
                          ),
                        ],
                      ),
                      if (group.description?.isNotEmpty == true) ...[
                        const SizedBox(height: 12),
                        Text(
                          group.description!,
                          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
                        ),
                      ],
                      if (group.tags.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: group.tags.map((tag) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.bgSurface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.borderSubtle),
                              ),
                              child: Text(
                                '#$tag',
                                style: TextStyle(color: AppTheme.accentGreen, fontSize: 11),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Group Posts Stream with Focus Autoplay
              if (_isLoading)
                SliverToBoxAdapter(
                  child: Container(
                    height: 300,
                    alignment: Alignment.center,
                    child: CircularProgressIndicator(color: AppTheme.accentGreen),
                  ),
                )
              else if (_groupPosts.isEmpty)
                SliverToBoxAdapter(
                  child: Container(
                    height: 240,
                    alignment: Alignment.center,
                    child: const Text(
                      'No posts in this group yet',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final post = _groupPosts[index];
                      return _SocialPostCard(
                        key: _cardKeys.putIfAbsent(post.postId, () => GlobalKey()),
                        post: post,
                        isFocused: _focusedPostId == post.postId,
                        isMuted: true,
                        onToggleMute: () {},
                        onTap: () => _openPostDetail(post),
                      );
                    },
                    childCount: _groupPosts.length,
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 60)),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// Dedicated Full-Page Post Detail Screen (Replaces Bottom Sheet)
// -------------------------------------------------------------
class PostDetailScreen extends StatelessWidget {
  final BuzzBoxPost post;

  const PostDetailScreen({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    final user = post.user;
    final group = post.group;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            if (user?.avatar != null && user!.avatar!.isNotEmpty)
              CircleAvatar(
                radius: 14,
                backgroundImage: CachedNetworkImageProvider(user.avatar!),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                user?.nickname.isNotEmpty == true ? user!.nickname : 'BuzzBox Post',
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (post.coverUrl != null && post.coverUrl!.isNotEmpty)
                InteractiveViewer(
                  child: Center(
                    child: CachedNetworkImage(
                      imageUrl: post.coverUrl!,
                      fit: BoxFit.contain,
                      placeholder: (context, url) => Container(
                        height: 300,
                        alignment: Alignment.center,
                        child: CircularProgressIndicator(color: AppTheme.accentGreen),
                      ),
                      errorWidget: (context, url, error) => const SizedBox(
                        height: 200,
                        child: Center(child: Text('Image unavailable', style: TextStyle(color: Colors.white54))),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (group != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.bgCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.borderSubtle),
                        ),
                        child: Text(
                          'in ${group.name}',
                          style: TextStyle(color: AppTheme.accentGreen, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    if (post.content.isNotEmpty)
                      Text(
                        post.content,
                        style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.favorite, color: Colors.redAccent, size: 16),
                        const SizedBox(width: 4),
                        Text('${post.likeCount} likes', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        const SizedBox(width: 16),
                        const Icon(Icons.chat_bubble_outline, color: Colors.white54, size: 16),
                        const SizedBox(width: 4),
                        Text('${post.commentCount} comments', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

