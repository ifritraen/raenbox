import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/moviebox_models.dart';
import '../../data/services/local_storage_service.dart';
import '../../data/services/moviebox_api_service.dart';
import '../detail/detail_screen.dart';
import '../me/bouncy_category_sheet.dart';

class SearchScreen extends StatefulWidget {
  final MovieBoxApiService apiService;

  const SearchScreen({super.key, required this.apiService});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  bool _isLoading = false;
  List<MediaItem> _results = [];
  LocalStorageService? _storage;

  // Dynamic trending searches state
  List<String> _hotSearches = [];
  bool _isLoadingTrending = false;

  // Real-time autocomplete suggestions state
  List<String> _suggestions = [];
  bool _isFetchingSuggestions = false;
  bool _hasSubmitted = false;

  static const List<String> _defaultTrending = [
    'Deadpool',
    'Avatar',
    'Avengers',
    'Mirzapur',
    'Prison Break',
    'Anime',
    'Squid Game',
  ];

  @override
  void initState() {
    super.initState();
    _initStorage();
    _loadTrendingSearches();
  }

  Future<void> _initStorage() async {
    final s = await LocalStorageService.getInstance();
    if (mounted) {
      setState(() => _storage = s);
      _loadTrendingSearches();
    }
  }

  Future<void> _loadTrendingSearches({bool forceRefresh = false}) async {
    if (_isLoadingTrending) return;
    setState(() => _isLoadingTrending = true);

    try {
      final trending = await widget.apiService.fetchTrendingSearches(
        region: _storage?.activeRegion,
        classify: _storage?.activeCatalog.classify,
      );
      if (mounted) {
        setState(() {
          if (trending.isNotEmpty) {
            _hotSearches = trending;
          } else if (_hotSearches.isEmpty) {
            _hotSearches = List.from(_defaultTrending);
          }
          _isLoadingTrending = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          if (_hotSearches.isEmpty) {
            _hotSearches = List.from(_defaultTrending);
          }
          _isLoadingTrending = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    final clean = query.trim();

    if (clean.isEmpty) {
      setState(() {
        _results = [];
        _suggestions = [];
        _isLoading = false;
        _hasSubmitted = false;
        _isFetchingSuggestions = false;
      });
      return;
    }

    setState(() {
      _hasSubmitted = false;
      _isFetchingSuggestions = true;
    });

    _debounce = Timer(const Duration(milliseconds: 200), () {
      _fetchSuggestions(clean);
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    if (!mounted || _controller.text.trim() != query) return;

    try {
      final items = await widget.apiService.fetchSearchSuggestions(query);
      if (mounted && _controller.text.trim() == query && !_hasSubmitted) {
        setState(() {
          _suggestions = items;
          _isFetchingSuggestions = false;
        });
      }
    } catch (_) {
      if (mounted && !_hasSubmitted) {
        setState(() => _isFetchingSuggestions = false);
      }
    }
  }

  Future<void> _performSearch(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _hasSubmitted = true;
      _isLoading = true;
      _suggestions = [];
    });

    _storage?.addSearchQuery(clean);

    try {
      final items = await widget.apiService.search(clean);
      if (mounted) {
        setState(() {
          _results = items;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: AppTheme.bgPrimary,
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: Container(
          height: 42,
          margin: const EdgeInsets.only(right: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.bgSecondary,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppTheme.borderSubtle),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, color: AppTheme.textSecondary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Search movies, series, anime...',
                    hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 14),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onChanged: _onSearchChanged,
                  onSubmitted: _performSearch,
                ),
              ),
              if (_controller.text.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _controller.clear();
                    _onSearchChanged('');
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.close, color: AppTheme.textSecondary, size: 18),
                  ),
                ),
            ],
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: AppTheme.accentGreen));
    }

    if (_hasSubmitted) {
      if (_results.isNotEmpty) {
        return _buildSearchResults();
      } else {
        return _buildEmptyResultsView();
      }
    }

    final query = _controller.text.trim();
    if (query.isNotEmpty) {
      return _buildAutocompleteSuggestions(query);
    }

    return _buildSearchHome();
  }

  Widget _buildAutocompleteSuggestions(String query) {
    return Column(
      children: [
        if (_isFetchingSuggestions)
          LinearProgressIndicator(
            minHeight: 2,
            backgroundColor: Colors.transparent,
            color: AppTheme.accentGreen,
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _suggestions.length + 1,
            separatorBuilder: (context, index) => Divider(
              color: AppTheme.borderSubtle,
              height: 1,
              indent: 52,
            ),
            itemBuilder: (context, index) {
              if (index == 0) {
                return ListTile(
                  dense: true,
                  leading: Icon(Icons.search, color: AppTheme.accentGreen, size: 22),
                  title: RichText(
                    text: TextSpan(
                      text: 'Search for ',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                      children: [
                        TextSpan(
                          text: '"$query"',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  onTap: () => _performSearch(query),
                );
              }

              final suggestion = _suggestions[index - 1];
              return ListTile(
                dense: true,
                leading: const Icon(Icons.search, color: AppTheme.textMuted, size: 20),
                title: Text(
                  suggestion,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.north_west, color: AppTheme.textMuted, size: 16),
                  tooltip: 'Insert into search',
                  onPressed: () {
                    _controller.text = suggestion;
                    _controller.selection = TextSelection.fromPosition(
                      TextPosition(offset: suggestion.length),
                    );
                    _onSearchChanged(suggestion);
                  },
                ),
                onTap: () {
                  _controller.text = suggestion;
                  _performSearch(suggestion);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchHome() {
    final history = _storage?.searchHistory ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (history.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Searches',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(50, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.delete_outline, color: AppTheme.textMuted, size: 16),
                label: const Text('Clear', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                onPressed: () => _storage?.clearSearchHistory(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: history.map((q) {
              return ActionChip(
                backgroundColor: AppTheme.bgSecondary,
                side: BorderSide(color: AppTheme.borderSubtle),
                label: Text(q, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                onPressed: () {
                  _controller.text = q;
                  _performSearch(q);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
        ],

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Text(
                  'Trending Searches',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(width: 6),
                if (_storage != null && _storage!.activeRegion != 'GLOBAL')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.bgSecondary,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppTheme.borderSubtle),
                    ),
                    child: Text(
                      _storage!.activeCatalog.flag,
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
              ],
            ),
            IconButton(
              icon: _isLoadingTrending
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentGreen),
                    )
                  : const Icon(Icons.refresh, color: AppTheme.textMuted, size: 20),
              tooltip: 'Refresh trending',
              onPressed: _isLoadingTrending ? null : () => _loadTrendingSearches(forceRefresh: true),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_isLoadingTrending && _hotSearches.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentGreen),
              ),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _hotSearches.map((q) {
              return ActionChip(
                backgroundColor: AppTheme.bgCard,
                side: BorderSide(color: AppTheme.borderAccent),
                avatar: const Icon(Icons.local_fire_department, color: AppTheme.orangeHot, size: 16),
                label: Text(q, style: const TextStyle(color: Colors.white, fontSize: 12)),
                onPressed: () {
                  _controller.text = q;
                  _performSearch(q);
                },
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildEmptyResultsView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded, color: AppTheme.textMuted, size: 64),
            const SizedBox(height: 16),
            Text(
              'No results for "${_controller.text.trim()}"',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Try checking for spelling errors or searching for a different keyword.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2 / 3.4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final item = _results[index];
        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DetailScreen(
                  subjectId: item.subjectId,
                  apiService: widget.apiService,
                ),
              ),
            );
          },
          onLongPress: () {
            if (_storage != null) {
              showBouncyCategorySheet(
                context: context,
                storage: _storage!,
                mediaItem: item,
              );
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: item.coverUrl != null
                          ? CachedNetworkImage(
                              imageUrl: item.coverUrl!,
                              fit: BoxFit.cover,
                              memCacheWidth: 220,
                              memCacheHeight: 330,
                              width: double.infinity,
                              placeholder: (context, url) => Container(color: AppTheme.bgCard),
                              errorWidget: (context, url, error) =>
                                  const Icon(Icons.movie, color: Colors.white54),
                            )
                          : Container(color: AppTheme.bgCard),
                    ),
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.isSeries ? 'TV' : 'Movie',
                          style: TextStyle(
                            color: AppTheme.accentCyan,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    if (item.imdbRating != null && item.imdbRating!.isNotEmpty)
                      Positioned(
                        bottom: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star, color: AppTheme.badgeGold, size: 10),
                              const SizedBox(width: 2),
                              Text(
                                item.imdbRating!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }
}
