import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/moviebox_models.dart';
import '../../data/services/moviebox_api_service.dart';
import '../../data/services/local_storage_service.dart';
import '../detail/detail_screen.dart';
import 'section_customizer_sheet.dart';
import '../me/bouncy_category_sheet.dart';
import '../buzzbox/buzzbox_tab.dart';
import '../buzzbox/short_player_screen.dart';

class DynamicSubTab {
  final String title;
  final List<MediaItem> items;
  final String? opId;

  DynamicSubTab({
    required this.title,
    required this.items,
    this.opId,
  });
}

enum _QueryType {
  rankingList,
  searchKeyword,
  subjectFilter,
}

class _ActiveCategoryQuery {
  final _QueryType type;
  final String? rankingListId;
  final String? searchKeyword;
  final String? channelId;
  final String? genre;
  final String? country;
  final String? year;
  final String? classify;
  final String? sort;

  const _ActiveCategoryQuery.rankingList(this.rankingListId)
      : type = _QueryType.rankingList,
        searchKeyword = null,
        channelId = null,
        genre = null,
        country = null,
        year = null,
        classify = null,
        sort = null;

  const _ActiveCategoryQuery.search(this.searchKeyword)
      : type = _QueryType.searchKeyword,
        rankingListId = null,
        channelId = null,
        genre = null,
        country = null,
        year = null,
        classify = null,
        sort = null;

  const _ActiveCategoryQuery.filter({
    this.channelId,
    this.genre,
    this.country,
    this.year,
    this.classify,
    this.sort,
  })  : type = _QueryType.subjectFilter,
        rankingListId = null,
        searchKeyword = null;
}

class DynamicFeedSection {
  final String title;
  List<MediaItem> items;
  final VoidCallback? onAll;
  final bool isPostList;
  final List<DynamicSubTab>? subTabs;
  int activeSubTabIndex;
  final String? genreTopId;
  final String? searchKeyword;
  final String? channelId;
  final String? genre;
  final String? country;
  final String? classify;
  final String? sort;

  DynamicFeedSection({
    required this.title,
    required this.items,
    this.onAll,
    this.isPostList = false,
    this.subTabs,
    this.activeSubTabIndex = 0,
    this.genreTopId,
    this.searchKeyword,
    this.channelId,
    this.genre,
    this.country,
    this.classify,
    this.sort,
  });
}

class _SectionDescriptor {
  final String title;
  final Future<List<MediaItem>> Function() loader;
  final VoidCallback? onAll;
  final bool isHeroCandidate;
  final String? searchKeyword;

  _SectionDescriptor({
    required this.title,
    required this.loader,
    this.onAll,
    this.isHeroCandidate = false,
    this.searchKeyword,
  });
}

class HomeScreen extends StatefulWidget {
  static const List<String> categoryTabs = [
    'Home',
    'Trending',
    'Movie',
    'TV',
    'MidNight🔞',
    '😂BuzzBox',
    'Anime',
    'ShortTV',
  ];

  static List<String> getCategoryTabs(LocalStorageService storage) {
    final list = <String>['Home', 'Trending', 'Movie', 'TV'];
    if (!storage.is18PlusDisabled) {
      list.add('MidNight🔞');
    }
    if (storage.isBuzzBoxEnabled) {
      list.add('😂BuzzBox');
    }
    list.addAll(['Anime', 'ShortTV']);
    return list;
  }

  final MovieBoxApiService apiService;
  final LocalStorageService storage;
  final ValueChanged<int>? onCategoryChanged;

  const HomeScreen({
    super.key,
    required this.apiService,
    required this.storage,
    this.onCategoryChanged,
  });

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class _CategoryTabState {
  final int index;
  bool hasLoadedOnce = false;
  bool isLoading = false;
  int loadToken = 0;

  // Dynamic Rails & Hero Data
  List<DynamicFeedSection> sections = [];
  List<MediaItem> heroBanners = [];

  // Bottom Continuous Infinite-Scroll Feed
  List<MediaItem> bottomInfiniteFeed = [];
  int bottomPage = 1;
  bool isLoadingMoreBottom = false;
  bool hasMoreBottom = true;

  // Filter & Pill State
  String selectedPill = 'All';
  String selectedGenre = 'All';
  String selectedCountry = 'All';
  String selectedYear = 'All';
  String selectedLanguage = 'All';
  late String selectedSort;

  List<MediaItem> pagedItems = [];
  int currentPage = 1;
  bool isLoadingMore = false;
  bool hasMorePagedItems = true;
  _ActiveCategoryQuery? activeQuery;

  final ScrollController scrollController = ScrollController();
  final ScrollController gridScrollController = ScrollController();
  final Map<String, double> savedSectionOffsets = {};
  double savedRailsOffset = 0.0;

  _CategoryTabState({required this.index}) {
    selectedSort = (index >= 4) ? 'Popular' : 'ForYou';
  }

  bool get isRailsMode {
    if (index <= 1) return selectedPill == 'All';
    final defaultSort = (index >= 4) ? 'Popular' : 'ForYou';
    return selectedPill == 'All' &&
        selectedGenre == 'All' &&
        selectedCountry == 'All' &&
        selectedYear == 'All' &&
        selectedLanguage == 'All' &&
        selectedSort == defaultSort;
  }

  bool get hasActiveFilters => !isRailsMode && index > 1;

  void resetFilters() {
    selectedPill = 'All';
    selectedGenre = 'All';
    selectedCountry = 'All';
    selectedYear = 'All';
    selectedLanguage = 'All';
    selectedSort = (index >= 4) ? 'Popular' : 'ForYou';
    activeQuery = null;
    hasMorePagedItems = true;
  }

  void invalidate() {
    hasLoadedOnce = false;
    isLoading = false;
    sections = [];
    heroBanners = [];
    bottomInfiniteFeed = [];
    bottomPage = 1;
    isLoadingMoreBottom = false;
    hasMoreBottom = true;
    pagedItems = [];
    currentPage = 1;
    isLoadingMore = false;
    hasMorePagedItems = true;
    resetFilters();
    if (gridScrollController.hasClients) {
      gridScrollController.jumpTo(0);
    }
  }

  void dispose() {
    scrollController.dispose();
    gridScrollController.dispose();
  }
}

class HomeScreenState extends State<HomeScreen> {
  int _selectedCategoryIndex = 0; // Visible category index
  int get selectedCategoryIndex => _selectedCategoryIndex;

  late final List<_CategoryTabState> _tabs = List.generate(8, (i) => _CategoryTabState(index: i));
  late final PageController _pageController;

  List<_CategoryTabState> get _visibleTabs {
    final list = <_CategoryTabState>[_tabs[0], _tabs[1], _tabs[2], _tabs[3]];
    if (!widget.storage.is18PlusDisabled) {
      list.add(_tabs[4]);
    }
    if (widget.storage.isBuzzBoxEnabled) {
      list.add(_tabs[7]);
    }
    list.addAll([_tabs[5], _tabs[6]]);
    return list;
  }

  String _getTabTitle(_CategoryTabState tab) {
    switch (tab.index) {
      case 0:
        return 'Home';
      case 1:
        return 'Trending';
      case 2:
        return 'Movie';
      case 3:
        return 'TV';
      case 4:
        return 'MidNight🔞';
      case 5:
        return 'Anime';
      case 6:
        return 'ShortTV';
      case 7:
        return '😂BuzzBox';
      default:
        return 'Explore';
    }
  }

  // Global rail caches per catalog session
  final Map<String, List<MediaItem>> _homeCustomRailCache = {};
  final Map<String, List<MediaItem>> _homeRailCache = {};
  final Map<String, List<MediaItem>> _movieRailCache = {};
  final Map<String, List<MediaItem>> _tvRailCache = {};
  final Map<String, List<MediaItem>> _midnightRailCache = {};
  final Map<String, List<MediaItem>> _animeRailCache = {};
  final Map<String, List<MediaItem>> _shortTvRailCache = {};
  final Map<int, List<DynamicFeedSection>> _mobileTabCache = {};
  final Map<int, List<MediaItem>> _mobileHeroCache = {};

  FeedEdition? _lastFeedEdition;

  void setCategoryIndex(int index) {
    final visible = _visibleTabs;
    if (index < 0 || index >= visible.length) return;
    if (_selectedCategoryIndex != index) {
      setState(() {
        _selectedCategoryIndex = index;
      });
      if (_pageController.hasClients && _pageController.page?.round() != index) {
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
      final tab = visible[index];
      if (!tab.hasLoadedOnce && !tab.isLoading) {
        _loadTabState(tab);
      }
      widget.onCategoryChanged?.call(index);
    }
  }

  void switchCategory(int rawIndex, {String? movieCategory, String? tvCategory, String? language}) {
    final visible = _visibleTabs;
    final targetTab = _tabs[rawIndex];
    int visibleIndex = visible.indexOf(targetTab);
    if (visibleIndex == -1) visibleIndex = 0;

    setState(() {
      _selectedCategoryIndex = visibleIndex;
      if (movieCategory != null) targetTab.selectedPill = movieCategory;
      if (tvCategory != null) targetTab.selectedPill = tvCategory;
      if (language != null) targetTab.selectedLanguage = language;
    });
    if (_pageController.hasClients && _pageController.page?.round() != visibleIndex) {
      _pageController.animateToPage(
        visibleIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
    _loadTabState(targetTab);
    widget.onCategoryChanged?.call(visibleIndex);
  }

  List<String> _getPillsForCategory(int categoryIndex) {
    final catalog = widget.storage.activeCatalog;
    switch (categoryIndex) {
      case 2: // Movie
        final list = <String>['All'];
        if (catalog.code != 'GLOBAL') {
          list.add('${catalog.flag} ${catalog.name.split(" (").first}');
        }
        list.addAll([
          'Trending in Cinema',
          'Top Movies',
          'New Release',
          'Bollywood Love',
          'Action',
          'Comedies',
          'Adventure',
          'Horror',
          'Thrills & Crimes',
          'Super Hero',
          'Sci-Fi Future'
        ]);
        return list;
      case 3: // TV
        final list = <String>['All'];
        if (catalog.code != 'GLOBAL') {
          list.add('${catalog.flag} ${catalog.name.split(" (").first}');
        }
        list.addAll([
          'Top Series',
          'Western TV',
          'Best Asian Dramas',
          'Indian Dramas',
          'K-Drama',
          'C-Drama',
          'Turkish Drama',
          'Pakistani TV',
          'Crime & Mystery',
          'Sci-Fi & Fantasy',
          'Comedy Shows'
        ]);
        return list;
      case 4: // MidNight🔞
        return [
          'All',
          'Vivamax',
          'Tbonx',
          'Cinepop',
          'Late-night Shorts',
          'Hentai Anime',
          'Indian 18+',
          'Japanese 18+',
          'Korea 18+',
          'Chinese 18+',
          'UllU Drama',
          'UllU Movie',
          '18+ Dramas',
          'Porn Top Videos',
        ];
      case 5: // Anime
        return [
          'All',
          'Top Anime Series',
          'Must-Watch Anime',
          'Action & Shonen',
          'Fantasy & Isekai',
          'Romance & Life',
          'Sci-Fi & Cyberpunk',
          'Comedy Anime',
          'Anime Movies'
        ];
      case 6: // ShortTV
        return [
          'All',
          'Hot Short TV',
          'CEO Romance',
          'Werewolf',
          'Revenge',
          'Short Drama'
        ];
      default:
        return const [];
    }
  }

  final List<String> _movieGenres = [
    'All', 'Action', 'Horror', 'Romance', 'Comedy', 'Adventure', 'Fantasy', 'Crime', 'Sci-Fi', 'Thriller', 'Animation'
  ];

  final List<String> _tvGenres = [
    'All', 'Drama', 'Comedy', 'Crime', 'Action', 'Adventure', 'Animation', 'Mystery', 'Sci-Fi', 'Reality', 'Romance'
  ];

  final List<String> _animeGenres = [
    'All', 'Action', 'Adventure', 'Fantasy', 'Sci-Fi', 'Romance', 'Comedy'
  ];

  final List<String> _midnightGenres = [
    'All', 'Romance', 'Drama', 'Thriller'
  ];

  final List<String> _shortTvGenres = [
    'All', 'Reality', 'Romance', 'Drama'
  ];

  final List<String> _years = [
    'All', '2026', '2025', '2024', '2023', '2022', '2021', '2020', '2010s', '2000s', '1990s', '1980s'
  ];

  final List<String> _sortOptions = ['ForYou', 'Popular', 'Latest', 'HighRating'];

  List<String> get _countries {
    final list = <String>['All'];
    final activeCountry = widget.storage.activeRegionCountryName;
    if (activeCountry.isNotEmpty && activeCountry != 'Global' && !list.contains(activeCountry)) {
      list.add(activeCountry);
    }
    const common = [
      'Bangladesh', 'India', 'Philippines', 'Indonesia', 'Nigeria',
      'United States', 'Korea', 'China', 'Japan', 'United Kingdom', 'France', 'Germany',
    ];
    for (final c in common) {
      if (!list.contains(c)) list.add(c);
    }
    return list;
  }

  List<String> get _languages {
    final list = <String>['All'];
    final activeClassify = widget.storage.activeCatalog.classify;
    if (activeClassify != null && !list.contains(activeClassify)) {
      list.add(activeClassify);
    }
    for (final c in LocalStorageService.supportedCatalogs) {
      if (c.classify != null && !list.contains(c.classify!)) {
        list.add(c.classify!);
      }
    }
    return list;
  }

  String? _lastRegion;
  String? _lastCustomSectionsKey;
  bool? _lastIs18PlusDisabled;
  bool? _lastIsBuzzBoxEnabled;

  @override
  void initState() {
    super.initState();
    _lastRegion = widget.storage.activeRegion;
    _lastCustomSectionsKey = widget.storage.getHomeCustomSections().map((s) => s.title).join(',');
    _lastIs18PlusDisabled = widget.storage.is18PlusDisabled;
    _lastIsBuzzBoxEnabled = widget.storage.isBuzzBoxEnabled;
    _pageController = PageController(initialPage: _selectedCategoryIndex);
    for (final tab in _tabs) {
      tab.scrollController.addListener(() => _onTabScroll(tab));
      tab.gridScrollController.addListener(() => _onGridScroll(tab));
    }
    widget.storage.addListener(_onStorageChange);
    // Cold start: Only load the first tab (Trending)
    _loadTabState(_tabs[0]);
  }

  void _onStorageChange() {
    if (!mounted) return;
    final currentRegion = widget.storage.activeRegion;
    final currentCustomSections = widget.storage.getHomeCustomSections().map((s) => s.title).join(',');
    final current18PlusDisabled = widget.storage.is18PlusDisabled;
    final currentBuzzBoxEnabled = widget.storage.isBuzzBoxEnabled;
    final currentEdition = widget.storage.feedEdition;

    final regionChanged = _lastRegion != null && _lastRegion != currentRegion;
    final sectionsChanged = _lastCustomSectionsKey != null && _lastCustomSectionsKey != currentCustomSections;
    final adultChanged = _lastIs18PlusDisabled != null && _lastIs18PlusDisabled != current18PlusDisabled;
    final buzzBoxChanged = _lastIsBuzzBoxEnabled != null && _lastIsBuzzBoxEnabled != currentBuzzBoxEnabled;
    final editionChanged = _lastFeedEdition != null && _lastFeedEdition != currentEdition;

    _lastRegion = currentRegion;
    _lastCustomSectionsKey = currentCustomSections;
    _lastIs18PlusDisabled = current18PlusDisabled;
    _lastIsBuzzBoxEnabled = currentBuzzBoxEnabled;
    _lastFeedEdition = currentEdition;

    if (adultChanged || buzzBoxChanged) {
      final visible = _visibleTabs;
      if (_selectedCategoryIndex >= visible.length) {
        _selectedCategoryIndex = visible.length - 1;
      }
      _tabs[0].invalidate();
      _homeCustomRailCache.clear();
      _mobileTabCache.clear();
      _mobileHeroCache.clear();
      setState(() {});
    }

    if (regionChanged || editionChanged) {
      setState(() {
        _homeRailCache.clear();
        _movieRailCache.clear();
        _tvRailCache.clear();
        _midnightRailCache.clear();
        _animeRailCache.clear();
        _shortTvRailCache.clear();
        _mobileTabCache.clear();
        _mobileHeroCache.clear();
        for (final tab in _tabs) {
          tab.invalidate();
        }
      });
      final visible = _visibleTabs;
      if (_selectedCategoryIndex < visible.length) {
        _loadTabState(visible[_selectedCategoryIndex]);
      }
    } else if (sectionsChanged || adultChanged) {
      _homeRailCache.clear();
      _mobileTabCache.remove(0);
      _mobileTabCache.remove(1);
      _tabs[0].invalidate();
      if (_selectedCategoryIndex == 0) {
        _loadTabState(_tabs[0]);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    widget.storage.removeListener(_onStorageChange);
    for (final tab in _tabs) {
      tab.dispose();
    }
    super.dispose();
  }

  void _onTabScroll(_CategoryTabState tab) {
    if (!tab.scrollController.hasClients) return;
    if (tab.scrollController.position.pixels >=
        tab.scrollController.position.maxScrollExtent - 450) {
      if (tab.isRailsMode && !tab.isLoading && !tab.isLoadingMoreBottom && tab.hasMoreBottom) {
        _loadMoreBottomFeed(tab);
      }
    }
  }

  void _onGridScroll(_CategoryTabState tab) {
    if (!tab.gridScrollController.hasClients) return;
    if (tab.gridScrollController.position.pixels >=
        tab.gridScrollController.position.maxScrollExtent - 450) {
      if (!tab.isRailsMode && !tab.isLoading && !tab.isLoadingMore && tab.hasMorePagedItems) {
        _loadMorePagedItems(tab);
      }
    }
  }

  void _resetAllFilters(_CategoryTabState tab) {
    if (tab.gridScrollController.hasClients) {
      tab.savedSectionOffsets[tab.selectedPill] = tab.gridScrollController.offset;
    }
    setState(() {
      tab.resetFilters();
    });
    // tab is now in Rails mode. The rails feed is kept in Offstage with exact scroll position preserved!
    if (tab.scrollController.hasClients && tab.savedRailsOffset > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (tab.scrollController.hasClients) {
          tab.scrollController.jumpTo(
            tab.savedRailsOffset.clamp(0.0, tab.scrollController.position.maxScrollExtent),
          );
        }
      });
    }
  }

  /// Handles back press inside HomeScreen:
  /// 1. If currently in a section / filtered grid, resets filters to return to that category's rails feed.
  /// 2. If in rails feed but on a non-Trending category tab, switches back to Trending (tab 0).
  /// 3. Returns true if handled, false if already at the root Trending rails feed.
  bool handleBackPressed() {
    final currentTab = _tabs[_selectedCategoryIndex];
    if (!currentTab.isRailsMode) {
      _resetAllFilters(currentTab);
      return true;
    }
    if (_selectedCategoryIndex != 0) {
      setCategoryIndex(0);
      return true;
    }
    return false;
  }

  /// Instantly resets to the Trending root rails view
  void resetToTrendingRoot() {
    final currentTab = _tabs[_selectedCategoryIndex];
    if (!currentTab.isRailsMode) {
      _resetAllFilters(currentTab);
    }
    if (_selectedCategoryIndex != 0) {
      setCategoryIndex(0);
    }
  }

  void _applyPillFilter(_CategoryTabState tab, String pill) {
    if (tab.scrollController.hasClients) {
      tab.savedRailsOffset = tab.scrollController.offset;
    }
    if (tab.gridScrollController.hasClients) {
      tab.savedSectionOffsets[tab.selectedPill] = tab.gridScrollController.offset;
    }
    setState(() {
      tab.selectedPill = pill;
    });
    _loadTabState(tab);
  }

  void _applyGenreFilter(_CategoryTabState tab, String genre) {
    if (tab.scrollController.hasClients) {
      tab.savedRailsOffset = tab.scrollController.offset;
    }
    setState(() {
      tab.selectedGenre = genre;
    });
    _loadTabState(tab);
  }

  void _applyCountryFilter(_CategoryTabState tab, String country) {
    if (tab.scrollController.hasClients) {
      tab.savedRailsOffset = tab.scrollController.offset;
    }
    setState(() {
      tab.selectedCountry = country;
    });
    _loadTabState(tab);
  }

  void _applyLanguageFilter(_CategoryTabState tab, String lang) {
    if (tab.scrollController.hasClients) {
      tab.savedRailsOffset = tab.scrollController.offset;
    }
    setState(() {
      tab.selectedLanguage = lang;
    });
    _loadTabState(tab);
  }

  Future<void> _loadTabState(_CategoryTabState tab, {bool isRefresh = false}) async {
    final currentToken = ++tab.loadToken;
    if (tab.index == 7) {
      if (mounted && currentToken == tab.loadToken) {
        setState(() {
          tab.hasLoadedOnce = true;
          tab.isLoading = false;
        });
      }
      return;
    }

    if (!isRefresh && !tab.hasLoadedOnce) {
      setState(() {
        tab.isLoading = true;
      });
    }

    if (tab.isRailsMode) {
      tab.bottomPage = 1;
      if (tab.index == 0) {
        await _loadDynamicRails(tab, currentToken);
      } else {
        await Future.wait([
          _loadDynamicRails(tab, currentToken),
          _initBottomFeed(tab, currentToken),
        ]);
      }
    } else {
      tab.currentPage = 1;
      await _loadPagedCategory(tab, currentToken);
    }

    if (mounted && currentToken == tab.loadToken) {
      setState(() {
        tab.hasLoadedOnce = true;
        tab.isLoading = false;
      });
      // Restore section grid scroll position if previously visited
      if (!tab.isRailsMode && tab.savedSectionOffsets.containsKey(tab.selectedPill)) {
        final savedOffset = tab.savedSectionOffsets[tab.selectedPill] ?? 0.0;
        if (savedOffset > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (tab.gridScrollController.hasClients) {
              tab.gridScrollController.jumpTo(
                savedOffset.clamp(0.0, tab.gridScrollController.position.maxScrollExtent),
              );
            }
          });
        }
      }
    }
  }

  Future<void> _refreshTab(_CategoryTabState tab) async {
    _mobileTabCache.remove(tab.index);
    _mobileHeroCache.remove(tab.index);
    if (tab.index == 0) _homeCustomRailCache.clear();
    if (tab.index == 1) _homeRailCache.clear();
    if (tab.index == 2) _movieRailCache.clear();
    if (tab.index == 3) _tvRailCache.clear();
    if (tab.index == 4) _midnightRailCache.clear();
    if (tab.index == 5) _animeRailCache.clear();
    if (tab.index == 6) _shortTvRailCache.clear();
    await _loadTabState(tab, isRefresh: true);
  }

  // Safe API wrappers
  Future<List<MediaItem>> _safeBrowse({
    required String channelId,
    String classify = 'All',
    String country = 'All',
    String year = 'All',
    String genre = 'All',
    String sort = 'ForYou',
    int perPage = 10,
    int page = 1,
  }) async {
    try {
      return await widget.apiService.fetchBrowseList(
        channelId: channelId,
        classify: classify,
        country: country,
        year: year,
        genre: genre,
        sort: sort,
        perPage: perPage,
        page: page,
      );
    } catch (_) {
      return [];
    }
  }

  Future<List<MediaItem>> _safeSearch(String query, {int perPage = 10, int page = 1}) async {
    try {
      return await widget.apiService.search(query, perPage: perPage, page: page);
    } catch (_) {
      return [];
    }
  }

  // -------------------------------------------------------------
  // Operating Rail Hydration Helper: Expands 2-3 item playlists to full 15-20 items
  // -------------------------------------------------------------
  Future<DynamicFeedSection?> _hydrateOpSection({
    required Map<String, dynamic> op,
    required _CategoryTabState tab,
    required Map<String, List<MediaItem>> cache,
  }) async {
    final title = op['title']?.toString() ?? '';
    final genreTopId = op['genreTopId']?.toString() ?? '';
    final opType = op['type']?.toString() ?? '';
    final subjects = op['subjects'] as List<dynamic>? ?? [];

    List<MediaItem> items = [];
    for (final s in subjects) {
      if (s is Map<String, dynamic>) {
        final subj = s['subject'] is Map<String, dynamic>
            ? s['subject'] as Map<String, dynamic>
            : s;
        items.add(MediaItem.fromJson(subj));
      }
    }

    // If section is a PLAY_LIST or has <= 3 items, hydrate from full ranking list
    if ((opType == 'PLAY_LIST' || items.length <= 3) && genreTopId.isNotEmpty) {
      try {
        final ranked = await widget.apiService.fetchRankingList(genreTopId);
        if (ranked.isNotEmpty) {
          items = ranked;
        }
      } catch (_) {}
    }

    // If still small (< 10 items, e.g. New Bangla Movies has 6 items), enrich with regional catalog filter
    if (items.length < 10) {
      final tLower = title.toLowerCase();
      try {
        if (tLower.contains('bangla') || tLower.contains('bengali')) {
          final extra = await widget.apiService.fetchWebSubjectFilter(
            channelId: '2',
            classify: 'Bengali dub',
            country: 'Bangladesh',
            perPage: 15,
          );
          final existingIds = items.map((m) => m.subjectId).toSet();
          for (final ex in extra) {
            if (existingIds.add(ex.subjectId)) {
              items.add(ex);
            }
          }
        }
      } catch (_) {}
    }

    if (items.isEmpty) return null;

    cache[title] = items;
    return DynamicFeedSection(
      title: title,
      items: items,
      onAll: () => _applyPillFilter(tab, title),
      genreTopId: genreTopId.isNotEmpty ? genreTopId : null,
    );
  }

  Future<Map<String, List<MediaItem>>> _getHomeOperatingRails() async {
    if (_homeRailCache.isNotEmpty) return _homeRailCache;
    try {
      final homeData = await widget.apiService.fetchHomeOperating();
      if (homeData.isNotEmpty && homeData['operatingList'] is List) {
        final opList = homeData['operatingList'] as List<dynamic>;
        final List<Map<String, dynamic>> rawSections = [];
        final Set<String> seen = {};

        for (final op in opList) {
          if (op is! Map<String, dynamic>) continue;
          final title = op['title']?.toString() ?? '';
          final opType = op['type']?.toString();
          if (opType == 'BANNER' ||
              opType == 'SPORT_LIVE' ||
              title.toLowerCase().contains('sport') ||
              title.toLowerCase().contains('football') ||
              title.toLowerCase().contains('live')) {
            continue;
          }
          if (op['subjects'] is List && (op['subjects'] as List).isNotEmpty) {
            final norm = title.trim().toLowerCase();
            if (norm.isNotEmpty && seen.add(norm)) {
              rawSections.add(op);
            }
          }
        }

        await Future.wait(rawSections.map((op) async {
          await _hydrateOpSection(
            op: op,
            tab: _tabs[1],
            cache: _homeRailCache,
          );
        }));
      }
    } catch (_) {}
    return _homeRailCache;
  }

  Future<List<MediaItem>> _loadCustomSectionItems(CustomSectionConfig cfg) async {
    if (_homeCustomRailCache.containsKey(cfg.id) && _homeCustomRailCache[cfg.id]!.isNotEmpty) {
      return _homeCustomRailCache[cfg.id]!;
    }
    try {
      List<MediaItem> items = [];
      if (cfg.keyword != null && cfg.keyword!.isNotEmpty) {
        items = await widget.apiService.search(cfg.keyword!, perPage: 12);
      } else {
        String channelId = '1';
        if (cfg.type == 'tv') channelId = '2';
        if (cfg.type == 'anime') channelId = '1006';
        items = await widget.apiService.fetchWebSubjectFilter(
          channelId: channelId,
          genre: (cfg.genre != null && cfg.genre != 'All') ? cfg.genre! : 'All',
          country: (cfg.country != null && cfg.country != 'All') ? cfg.country! : 'All',
          year: (cfg.year != null && cfg.year != 'All') ? cfg.year! : 'All',
          sort: cfg.sort,
          perPage: 12,
        );
      }
      if (items.isNotEmpty) {
        _homeCustomRailCache[cfg.id] = items;
      }
      return items;
    } catch (_) {
      return [];
    }
  }

  void _applyOrderingAndFiltering(_CategoryTabState tab, List<DynamicFeedSection> sections) {
    final savedOrder = widget.storage.getTabSectionOrder(tab.index);
    final hiddenIds = widget.storage.getTabHiddenSections(tab.index);
    if (savedOrder.isNotEmpty) {
      sections.sort((a, b) {
        final aIdx = savedOrder.indexOf(a.title);
        final bIdx = savedOrder.indexOf(b.title);
        if (aIdx == -1 && bIdx == -1) return 0;
        if (aIdx == -1) return 1;
        if (bIdx == -1) return -1;
        return aIdx.compareTo(bIdx);
      });
    }
    sections.removeWhere((s) => hiddenIds.contains(s.title));
    if (widget.storage.is18PlusDisabled) {
      sections.removeWhere((s) {
        final t = s.title.toLowerCase();
        return t.contains('18+') ||
            t.contains('midnight') ||
            t.contains('vivamax') ||
            t.contains('tbonx') ||
            t.contains('cinepop') ||
            t.contains('hentai') ||
            t.contains('ullu') ||
            t.contains('🔞');
      });
    }
  }

  // -------------------------------------------------------------
  // Mobile Operating Rails Loader: 100% Authentic Native Backend
  // -------------------------------------------------------------
  Future<void> _loadMobileTabOperating(_CategoryTabState tab, int currentToken) async {
    if (_mobileTabCache.containsKey(tab.index) && _mobileTabCache[tab.index]!.isNotEmpty) {
      final cachedSections = _mobileTabCache[tab.index]!;
      final cachedHeroes = _mobileHeroCache[tab.index] ?? [];
      if (mounted && currentToken == tab.loadToken) {
        setState(() {
          tab.sections = cachedSections;
          if (cachedHeroes.isNotEmpty) tab.heroBanners = cachedHeroes;
          tab.isLoading = false;
        });
      }
      return;
    }

    if (tab.index == 0) {
      final sections = <DynamicFeedSection>[];
      final watchHistory = widget.storage.getWatchHistory();
      if (watchHistory.isNotEmpty) {
        final historyItems = watchHistory.take(15).map((rec) => MediaItem(
          subjectId: rec.subjectId,
          title: rec.title,
          coverUrl: rec.coverUrl,
          subjectType: rec.subjectType,
        )).toList();
        sections.add(DynamicFeedSection(
          title: '▶ Continue Watching',
          items: historyItems,
        ));
      }

      final customSections = widget.storage.getHomeCustomSections();
      for (final cs in customSections) {
        final cItems = await _loadCustomSectionItems(cs);
        if (cItems.isNotEmpty) {
          sections.add(DynamicFeedSection(
            title: cs.title,
            items: cItems,
            onAll: () => _applyPillFilter(tab, cs.title),
            searchKeyword: (cs.keyword != null && cs.keyword!.isNotEmpty) ? cs.keyword : null,
            channelId: cs.type == 'tv' ? '2' : (cs.type == 'anime' ? '1006' : '1'),
            genre: (cs.genre != null && cs.genre != 'All') ? cs.genre : null,
            country: (cs.country != null && cs.country != 'All') ? cs.country : null,
            sort: cs.sort,
          ));
        }
      }

      _applyOrderingAndFiltering(tab, sections);

      _mobileTabCache[0] = sections;
      _mobileHeroCache[0] = [];

      if (mounted && currentToken == tab.loadToken) {
        setState(() {
          tab.sections = sections;
          tab.heroBanners = [];
          tab.isLoading = false;
        });
      }
      return;
    }

    int mobileTabId = 0;
    switch (tab.index) {
      case 1:
        mobileTabId = 0; // Trending
        break;
      case 2:
        mobileTabId = 2; // Movie
        break;
      case 3:
        mobileTabId = 5; // TV Series
        break;
      case 4:
        mobileTabId = 9; // MidNight (18+)
        break;
      case 5:
        mobileTabId = 8; // Anime
        break;
      case 6:
        mobileTabId = 7; // ShortTV
        break;
    }

    try {
      final data = await widget.apiService.fetchMobileTabOperating(mobileTabId);
      final items = data['items'] as List<dynamic>? ?? [];
      final sections = <DynamicFeedSection>[];
      List<MediaItem> heroCandidate = [];

      for (final it in items) {
        if (it is! Map<String, dynamic>) continue;
        final type = it['type']?.toString();
        final title = it['title']?.toString() ?? '';

        // Ignore category pills filter bar
        if (type == 'FILTER') continue;

        // Featured Hero Carousel Banner
        if (type == 'BANNER' && it['banner'] is Map) {
          final bannerObj = it['banner'] as Map<String, dynamic>;
          final bList = (bannerObj['banners'] ?? bannerObj['items']) as List<dynamic>? ?? [];
          for (final b in bList) {
            if (b is! Map<String, dynamic>) continue;
            final subj = b['subject'] is Map<String, dynamic>
                ? b['subject'] as Map<String, dynamic>
                : null;

            String? img;
            final rawImg = b['image'] ?? b['cover'] ?? b['coverImage'] ?? b['imageUrl'] ?? b['url'] ?? subj?['cover'] ?? subj?['image'];
            if (rawImg is Map) {
              img = rawImg['url']?.toString();
            } else if (rawImg is String && rawImg.isNotEmpty) {
              img = rawImg;
            }

            final subId = (b['subjectId'] ?? b['id'] ?? subj?['subjectId'] ?? subj?['id'] ?? '').toString();
            final bTitle = (b['title'] ?? b['name'] ?? subj?['title'] ?? subj?['name'] ?? '').toString();

            if (subId.isNotEmpty) {
              heroCandidate.add(MediaItem(
                subjectId: subId,
                title: bTitle.isNotEmpty ? bTitle : 'Featured',
                coverUrl: img,
                subjectType: (subj?['subjectType'] as num?)?.toInt() ?? 1,
                imdbRating: subj?['imdbRatingValue']?.toString() ?? subj?['imdbRating']?.toString(),
                genre: subj?['genre']?.toString(),
                releaseDate: subj?['releaseDate']?.toString(),
              ));
            }
          }
          continue;
        }

        // 1. RANKING_LIST_MULTI_TAB (Sub-tab ranked collections)
        if (type == 'RANKING_LIST_MULTI_TAB' && it['rankingListData'] is Map) {
          final rData = it['rankingListData'] as Map<String, dynamic>;
          final rItems = rData['items'] as List<dynamic>? ?? [];
          final List<DynamicSubTab> subTabs = [];
          for (final rSub in rItems) {
            if (rSub is! Map<String, dynamic>) continue;
            final subTitle = (rSub['title'] ?? '').toString();
            final subSubjsRaw = rSub['subjects'] as List<dynamic>? ?? [];
            final List<MediaItem> subItems = [];
            for (final s in subSubjsRaw) {
              if (s is Map<String, dynamic>) {
                var subj = s;
                if (s['subject'] is Map<String, dynamic>) {
                  subj = Map<String, dynamic>.from(s['subject'] as Map<String, dynamic>);
                  for (final k in ['cover', 'coverImage', 'image', 'coverUrl', 'imageUrl']) {
                    if (subj[k] == null && s[k] != null) subj[k] = s[k];
                  }
                }
                final item = MediaItem.fromJson(subj);
                if (item.subjectId.isNotEmpty && item.subjectId != '0') {
                  subItems.add(item);
                }
              }
            }
            if (subItems.isNotEmpty && subTitle.isNotEmpty) {
              subTabs.add(DynamicSubTab(
                title: subTitle,
                items: subItems,
                opId: rSub['opId']?.toString(),
              ));
            }
          }
          if (subTabs.isNotEmpty && title.isNotEmpty) {
            sections.add(DynamicFeedSection(
              title: title,
              items: subTabs.first.items,
              subTabs: subTabs,
              activeSubTabIndex: 0,
              onAll: () => _applyPillFilter(tab, title),
              genreTopId: subTabs.first.opId,
            ));
            continue;
          }
        }

        // 2. POST_LIST (Shorts video rails)
        if (type == 'POST_LIST' && it['postData'] is List) {
          final pList = it['postData'] as List<dynamic>;
          final List<MediaItem> postItems = [];
          for (final p in pList) {
            if (p is Map<String, dynamic>) {
              final item = MediaItem.fromJson(p);
              if (item.title.isNotEmpty || item.coverUrl != null) {
                postItems.add(item);
              }
            }
          }
          if (postItems.isNotEmpty && title.isNotEmpty) {
            sections.add(DynamicFeedSection(
              title: title,
              items: postItems,
              isPostList: true,
              onAll: () => _applyPillFilter(tab, title),
              searchKeyword: title,
            ));
            continue;
          }
        }

        // 3. CUSTOM (Thematic curated collections)
        if (type == 'CUSTOM' && it['customData'] is Map) {
          final cData = it['customData'] as Map<String, dynamic>;
          final cItems = cData['items'] as List<dynamic>? ?? [];
          final List<MediaItem> customItems = [];
          for (final c in cItems) {
            if (c is Map<String, dynamic>) {
              var subj = c;
              if (c['subject'] is Map<String, dynamic>) {
                subj = Map<String, dynamic>.from(c['subject'] as Map<String, dynamic>);
                for (final k in ['cover', 'coverImage', 'image', 'coverUrl', 'imageUrl', 'content']) {
                  if (subj[k] == null && c[k] != null) subj[k] = c[k];
                }
              }
              final item = MediaItem.fromJson(subj);
              if (item.subjectId.isNotEmpty && item.subjectId != '0') {
                customItems.add(item);
              }
            }
          }
          if (customItems.isNotEmpty && title.isNotEmpty) {
            sections.add(DynamicFeedSection(
              title: title,
              items: customItems,
              onAll: () => _applyPillFilter(tab, title),
              searchKeyword: title,
            ));
            continue;
          }
        }

        // 4. Standard SUBJECTS_MOVIE, PLAY_LIST, APPOINTMENT_LIST
        final List<MediaItem> sectionItems = [];
        final rawSubjects = it['subjects'] as List<dynamic>? ?? [];
        for (final s in rawSubjects) {
          if (s is Map<String, dynamic>) {
            var subj = s;
            if (s['subject'] is Map<String, dynamic>) {
              subj = Map<String, dynamic>.from(s['subject'] as Map<String, dynamic>);
              for (final k in ['cover', 'coverImage', 'image', 'coverUrl', 'imageUrl']) {
                if (subj[k] == null && s[k] != null) {
                  subj[k] = s[k];
                }
              }
            }
            final item = MediaItem.fromJson(subj);
            if (item.subjectId.isNotEmpty) {
              sectionItems.add(item);
            }
          }
        }

        // Hydrate if playlist has only preview cards (<= 3 items)
        final genreTopId = it['opId']?.toString() ?? it['genreTopId']?.toString() ?? '';
        if (sectionItems.length <= 3 &&
            genreTopId.isNotEmpty &&
            type == 'PLAY_LIST') {
          try {
            final ranked = await widget.apiService.fetchRankingList(genreTopId);
            if (ranked.isNotEmpty) {
              final existingIds = sectionItems.map((m) => m.subjectId).toSet();
              for (final r in ranked) {
                if (existingIds.add(r.subjectId)) {
                  sectionItems.add(r);
                }
              }
            }
          } catch (_) {}
        }

        if (sectionItems.isNotEmpty && title.isNotEmpty) {
          sections.add(DynamicFeedSection(
            title: title,
            items: sectionItems,
            onAll: () => _applyPillFilter(tab, title),
            genreTopId: genreTopId.isNotEmpty ? genreTopId : null,
          ));
        }
      }

      // Apply ordering, hidden sections and 18+ filters
      _applyOrderingAndFiltering(tab, sections);

      _mobileTabCache[tab.index] = sections;
      if (heroCandidate.isEmpty && sections.isNotEmpty) {
        heroCandidate = sections.first.items
            .where((i) => i.coverUrl != null && i.coverUrl!.isNotEmpty)
            .take(6)
            .toList();
      }
      if (heroCandidate.isNotEmpty) {
        _mobileHeroCache[tab.index] = heroCandidate;
      }

      if (mounted && currentToken == tab.loadToken) {
        setState(() {
          tab.sections = sections;
          if (heroCandidate.isNotEmpty) tab.heroBanners = heroCandidate;
          tab.isLoading = false;
        });
      }
    } catch (_) {
      if (mounted && currentToken == tab.loadToken) {
        setState(() {
          tab.isLoading = false;
        });
      }
    }
  }

  // -------------------------------------------------------------
  // Dynamic Rails Engine: Data-driven descriptors per active tab & catalog
  // -------------------------------------------------------------
  Future<void> _loadDynamicRails(_CategoryTabState tab, int currentToken) async {
    if (widget.storage.feedEdition == FeedEdition.mobile) {
      await _loadMobileTabOperating(tab, currentToken);
      return;
    }

    final catalog = widget.storage.activeCatalog;
    final List<_SectionDescriptor> descriptors = [];

    switch (tab.index) {
      case 0: // Home Tab (Personalized Feed: Continue Watching + User Custom Rails)
        final sections = <DynamicFeedSection>[];

        // 1. Watch History / Continue Watching
        final watchHistory = widget.storage.getWatchHistory();
        if (watchHistory.isNotEmpty) {
          final historyItems = watchHistory.take(15).map((rec) => MediaItem(
            subjectId: rec.subjectId,
            title: rec.title,
            coverUrl: rec.coverUrl,
            subjectType: rec.subjectType,
          )).toList();
          sections.add(DynamicFeedSection(
            title: '▶ Continue Watching',
            items: historyItems,
          ));
        }

        // 2. User Custom Sections
        final customSections = widget.storage.getHomeCustomSections();
        for (final cs in customSections) {
          final cItems = await _loadCustomSectionItems(cs);
          if (cItems.isNotEmpty) {
            sections.add(DynamicFeedSection(
              title: cs.title,
              items: cItems,
              onAll: () => _applyPillFilter(tab, cs.title),
              searchKeyword: (cs.keyword != null && cs.keyword!.isNotEmpty) ? cs.keyword : null,
              channelId: cs.type == 'tv' ? '2' : (cs.type == 'anime' ? '1006' : '1'),
              genre: (cs.genre != null && cs.genre != 'All') ? cs.genre : null,
              country: (cs.country != null && cs.country != 'All') ? cs.country : null,
              sort: cs.sort,
            ));
          }
        }

        // 3. Apply User Ordering & Hide Filtering
        _applyOrderingAndFiltering(tab, sections);

        if (mounted && currentToken == tab.loadToken) {
          setState(() {
            tab.sections = sections;
            tab.heroBanners = [];
            tab.isLoading = false;
          });
        }
        return;

      case 1: // Trending Tab (Real Web Operating Rails)
        final homeData = await widget.apiService.fetchHomeOperating();
        if (homeData.isNotEmpty && homeData['operatingList'] is List) {
          final opList = homeData['operatingList'] as List<dynamic>;
          final sections = <DynamicFeedSection>[];
          List<MediaItem> heroCandidate = [];

          final List<Map<String, dynamic>> rawSections = [];
          final Set<String> seenTitles = {};

          for (final op in opList) {
            if (op is! Map<String, dynamic>) continue;
            final opType = op['type']?.toString();
            final title = op['title']?.toString() ?? '';

            // STRICT FILTER: Zero sports or live sections
            if (opType == 'SPORT_LIVE' ||
                title.toLowerCase().contains('sport') ||
                title.toLowerCase().contains('football') ||
                title.toLowerCase().contains('live')) {
              continue;
            }

            // 1. Featured Carousel Banner
            if (opType == 'BANNER' && op['banner'] is Map) {
              final bannerObj = op['banner'] as Map<String, dynamic>;
              final bannerItems = bannerObj['items'] as List<dynamic>? ?? [];
              for (final b in bannerItems) {
                if (b is! Map<String, dynamic>) continue;
                final img = b['image'] is Map ? b['image']['url']?.toString() : null;
                final subId = b['subjectId']?.toString() ?? '';
                final bTitle = b['title']?.toString() ?? '';
                final subj = b['subject'] is Map<String, dynamic>
                    ? b['subject'] as Map<String, dynamic>
                    : null;
                if (subId.isNotEmpty && img != null) {
                  heroCandidate.add(MediaItem(
                    subjectId: subId,
                    title: bTitle,
                    coverUrl: img,
                    subjectType: (subj?['subjectType'] as num?)?.toInt() ?? 1,
                    imdbRating: subj?['imdbRatingValue']?.toString(),
                    genre: subj?['genre']?.toString(),
                    releaseDate: subj?['releaseDate']?.toString(),
                  ));
                }
              }
              continue;
            }

            // 2. Curated Home Rails & Playlists (Deduplicated & Hydrated)
            if (op['subjects'] is List && (op['subjects'] as List).isNotEmpty) {
              final norm = title.trim().toLowerCase();
              if (norm.isEmpty || seenTitles.contains(norm)) continue;
              seenTitles.add(norm);
              rawSections.add(op);
            }
          }

          final hydrated = await Future.wait(rawSections.map((op) => _hydrateOpSection(
                op: op,
                tab: tab,
                cache: _homeRailCache,
              )));

          sections.addAll(hydrated.whereType<DynamicFeedSection>());

          _applyOrderingAndFiltering(tab, sections);

          if (mounted && currentToken == tab.loadToken) {
            setState(() {
              tab.sections = sections;
              if (heroCandidate.isNotEmpty) tab.heroBanners = heroCandidate;
              tab.isLoading = false;
            });
          }
          return;
        }

        // Fallback: 1. Rankings / Trending
        descriptors.add(_SectionDescriptor(
          title: '🔥 Trending Now',
          isHeroCandidate: true,
          loader: () => widget.apiService.fetchRankings(
            categoryType: catalog.rankingCategory ?? '4516404531735022304',
            page: 1,
            perPage: 12,
          ).catchError((_) => _safeBrowse(channelId: '1', sort: 'ForYou')),
        ));

        // 2. Catalog-specific Regional Feature
        if (catalog.classify != null) {
          descriptors.add(_SectionDescriptor(
            title: '${catalog.flag} ${catalog.name} Collection',
            isHeroCandidate: true,
            loader: () async {
              final res = await Future.wait([
                _safeBrowse(channelId: '1', classify: catalog.classify!, sort: 'ForYou'),
                if (catalog.searchKeyword != null) _safeSearch(catalog.searchKeyword!, perPage: 10) else Future.value(<MediaItem>[]),
                if (catalog.defaultCountry != null) _safeBrowse(channelId: '1', country: catalog.defaultCountry!, sort: 'ForYou') else Future.value(<MediaItem>[]),
              ]);
              final merged = <MediaItem>[];
              final seen = <String>{};
              for (final list in res) {
                for (final item in list) {
                  if (seen.add(item.subjectId)) merged.add(item);
                }
              }
              return merged;
            },
            onAll: () {
              setCategoryIndex(2);
              _applyLanguageFilter(_tabs[2], catalog.classify!);
            },
          ));
        } else if (catalog.defaultCountry != null) {
          descriptors.add(_SectionDescriptor(
            title: '${catalog.flag} ${catalog.name} Movies',
            isHeroCandidate: true,
            loader: () => _safeBrowse(channelId: '1', country: catalog.defaultCountry!, sort: 'ForYou'),
            onAll: () {
              setCategoryIndex(2);
              _applyCountryFilter(_tabs[2], catalog.defaultCountry!);
            },
          ));
        }

        // 3. Hollywood Hits
        descriptors.add(_SectionDescriptor(
          title: '🎬 Hollywood Hits',
          loader: () => _safeBrowse(channelId: '1', country: 'United States', sort: 'ForYou'),
          onAll: () {
            setCategoryIndex(2);
            _applyCountryFilter(_tabs[2], 'United States');
          },
        ));

        // 4. Global TV Series
        descriptors.add(_SectionDescriptor(
          title: '📺 Top TV Series',
          loader: () => _safeBrowse(channelId: '2', sort: 'ForYou'),
          onAll: () => setCategoryIndex(3),
        ));

        // 5. Asian Dramas / K-Drama
        descriptors.add(_SectionDescriptor(
          title: '🇰🇷 Best Asian Drama / K-Drama',
          loader: () => _safeBrowse(channelId: '2', country: 'Korea', sort: 'Popular'),
          onAll: () {
            setCategoryIndex(3);
            _applyCountryFilter(_tabs[3], 'Korea');
          },
        ));

        // 6. C-Drama Spotlight
        descriptors.add(_SectionDescriptor(
          title: '🏮 C-Drama Spotlight',
          loader: () => _safeBrowse(channelId: '2', country: 'China', sort: 'Popular'),
          onAll: () {
            setCategoryIndex(3);
            _applyCountryFilter(_tabs[3], 'China');
          },
        ));

        // 7. Anime & Animation
        descriptors.add(_SectionDescriptor(
          title: '⚔️ Anime & Animation',
          loader: () => _safeBrowse(channelId: '1006', sort: 'Popular'),
          onAll: () => setCategoryIndex(5),
        ));
        break;

      case 2: // Movie Tab (Real Web Operating Rails)
        final movieData = await widget.apiService.fetchMovieOperating();
        if (movieData.isNotEmpty && movieData['operatingList'] is List) {
          final opList = movieData['operatingList'] as List<dynamic>;
          final sections = <DynamicFeedSection>[];
          List<MediaItem> heroCandidate = [];

          final List<Map<String, dynamic>> rawSections = [];
          final Set<String> seenTitles = {};

          for (final op in opList) {
            if (op is! Map<String, dynamic>) continue;
            final opType = op['type']?.toString();
            final title = op['title']?.toString() ?? '';

            // 1. Featured Carousel Banner
            if (opType == 'BANNER' && op['banner'] is Map) {
              final bannerObj = op['banner'] as Map<String, dynamic>;
              final bannerItems = bannerObj['items'] as List<dynamic>? ?? [];
              for (final b in bannerItems) {
                if (b is! Map<String, dynamic>) continue;
                final img = b['image'] is Map ? b['image']['url']?.toString() : null;
                final subId = b['subjectId']?.toString() ?? '';
                final bTitle = b['title']?.toString() ?? '';
                final subj = b['subject'] is Map<String, dynamic>
                    ? b['subject'] as Map<String, dynamic>
                    : null;
                if (subId.isNotEmpty && img != null) {
                  heroCandidate.add(MediaItem(
                    subjectId: subId,
                    title: bTitle,
                    coverUrl: img,
                    subjectType: (subj?['subjectType'] as num?)?.toInt() ?? 1,
                    imdbRating: subj?['imdbRatingValue']?.toString(),
                    genre: subj?['genre']?.toString(),
                    releaseDate: subj?['releaseDate']?.toString(),
                  ));
                }
              }
              continue;
            }

            // 2. Curated Movie Rails (Deduplicated & Hydrated)
            if (op['subjects'] is List && (op['subjects'] as List).isNotEmpty) {
              final norm = title.trim().toLowerCase();
              if (norm.isEmpty || seenTitles.contains(norm)) continue;
              seenTitles.add(norm);
              rawSections.add(op);
            }
          }

          final hydrated = await Future.wait(rawSections.map((op) => _hydrateOpSection(
                op: op,
                tab: tab,
                cache: _movieRailCache,
              )));

          sections.addAll(hydrated.whereType<DynamicFeedSection>());

          _applyOrderingAndFiltering(tab, sections);

          if (mounted && currentToken == tab.loadToken) {
            setState(() {
              tab.sections = sections;
              if (heroCandidate.isNotEmpty) tab.heroBanners = heroCandidate;
              tab.isLoading = false;
            });
          }
          return;
        }
        break;

      case 3: // TV Tab (Real Web Operating + Web BFF Rails)
        final homeRails = await _getHomeOperatingRails();
        final sections = <DynamicFeedSection>[];
        List<MediaItem> heroCandidate = [];

        // 1. Regional Catalog Series (if applicable)
        if (catalog.defaultCountry != null) {
          final localItems = await widget.apiService.fetchWebSubjectFilter(
            channelId: '2',
            country: catalog.defaultCountry!,
            sort: 'ForYou',
            perPage: 15,
          );
          if (localItems.isNotEmpty) {
            final title = '${catalog.flag} Top ${catalog.name.split(" (").first} Series';
            _tvRailCache[title] = localItems;
            sections.add(DynamicFeedSection(
              title: title,
              items: localItems,
              onAll: () => _applyCountryFilter(tab, catalog.defaultCountry!),
            ));
            if (heroCandidate.isEmpty) heroCandidate = localItems;
          }
        }

        // 2. Curated Web TV Rails from Web Tab 0
        for (final entry in homeRails.entries) {
          final tLower = entry.key.toLowerCase();
          if (tLower.contains('short') ||
              tLower.contains('anime') ||
              tLower.contains('cinema') ||
              tLower.contains('bollywood') ||
              tLower.contains('hollywood') ||
              tLower.contains('coming soon') ||
              tLower.contains('trending now') ||
              tLower.contains('top20')) {
            continue;
          }
          if (tLower.contains('series') ||
              tLower.contains('tv') ||
              tLower.contains('drama') ||
              tLower.contains('k-drama') ||
              tLower.contains('c-drama')) {
            _tvRailCache[entry.key] = entry.value;
            sections.add(DynamicFeedSection(
              title: entry.key,
              items: entry.value,
              onAll: () => _applyPillFilter(tab, entry.key),
            ));
            if (heroCandidate.isEmpty) heroCandidate = entry.value;
          }
        }

        // 3. Additional Web BFF Genre Rails
        final tvGenreQueries = [
          ('🕵️ Crime & Mystery Thrillers', 'Crime'),
          ('🚀 Sci-Fi & Fantasy Series', 'Sci-Fi'),
          ('😂 Comedy Shows', 'Comedy'),
        ];
        for (final item in tvGenreQueries) {
          final gTitle = item.$1;
          final gGenre = item.$2;
          final gItems = await widget.apiService.fetchWebSubjectFilter(
            channelId: '2',
            genre: gGenre,
            sort: 'Popular',
            perPage: 15,
          );
          if (gItems.isNotEmpty) {
            _tvRailCache[gTitle] = gItems;
            sections.add(DynamicFeedSection(
              title: gTitle,
              items: gItems,
              onAll: () => _applyGenreFilter(tab, gGenre),
            ));
          }
        }

        _applyOrderingAndFiltering(tab, sections);

        if (sections.isNotEmpty && mounted && currentToken == tab.loadToken) {
          setState(() {
            tab.sections = sections;
            if (heroCandidate.isNotEmpty) tab.heroBanners = heroCandidate.take(5).toList();
            tab.isLoading = false;
          });
          return;
        }
        break;

      case 4: // MidNight🔞 Tab (Real Web Operating Rails)
        final midnightData = await widget.apiService.fetchMidnightOperating();
        if (midnightData.isNotEmpty && midnightData['operatingList'] is List) {
          final opList = midnightData['operatingList'] as List<dynamic>;
          final sections = <DynamicFeedSection>[];
          List<MediaItem> heroCandidate = [];

          for (final op in opList) {
            if (op is! Map<String, dynamic>) continue;
            final opType = op['type']?.toString();
            final title = op['title']?.toString() ?? '';

            // 1. Featured Carousel Banner
            if (opType == 'BANNER' && op['banner'] is Map) {
              final bannerObj = op['banner'] as Map<String, dynamic>;
              final bannerItems = bannerObj['items'] as List<dynamic>? ?? [];
              for (final b in bannerItems) {
                if (b is! Map<String, dynamic>) continue;
                final img = b['image'] is Map ? b['image']['url']?.toString() : null;
                final subId = b['subjectId']?.toString() ?? '';
                final bTitle = b['title']?.toString() ?? '';
                final subj = b['subject'] is Map<String, dynamic>
                    ? b['subject'] as Map<String, dynamic>
                    : null;
                if (subId.isNotEmpty && img != null) {
                  heroCandidate.add(MediaItem(
                    subjectId: subId,
                    title: bTitle,
                    coverUrl: img,
                    subjectType: (subj?['subjectType'] as num?)?.toInt() ?? 1,
                    imdbRating: subj?['imdbRatingValue']?.toString(),
                    genre: subj?['genre']?.toString(),
                    releaseDate: subj?['releaseDate']?.toString(),
                  ));
                }
              }
            }

            // 2. Curated Adult Rails (Vivamax, UllU, Hentai, etc.)
            else if (op['subjects'] is List) {
              final subjects = op['subjects'] as List<dynamic>;
              final items = <MediaItem>[];
              for (final s in subjects) {
                if (s is Map<String, dynamic>) {
                  final subj = s['subject'] is Map<String, dynamic>
                      ? s['subject'] as Map<String, dynamic>
                      : s;
                  items.add(MediaItem.fromJson(subj));
                }
              }
              if (items.isNotEmpty) {
                final gTopId = op['genreTopId']?.toString() ?? op['opId']?.toString();
                _midnightRailCache[title] = items;
                sections.add(DynamicFeedSection(
                  title: title,
                  items: items,
                  onAll: () => _applyPillFilter(tab, title),
                  genreTopId: (gTopId != null && gTopId.isNotEmpty) ? gTopId : null,
                ));
              }
            }
          }

          _applyOrderingAndFiltering(tab, sections);

          if (mounted && currentToken == tab.loadToken) {
            setState(() {
              tab.sections = sections;
              tab.heroBanners = heroCandidate;
              tab.isLoading = false;
            });
          }
          return;
        }
        break;

      case 5: // Anime Tab (Real Web Operating + Web BFF Rails)
        final homeRails = await _getHomeOperatingRails();
        final sections = <DynamicFeedSection>[];
        List<MediaItem> heroCandidate = [];

        // 1. Curated Web Anime Rails from Web Tab 0
        for (final entry in homeRails.entries) {
          final tLower = entry.key.toLowerCase();
          if (tLower.contains('anime') || tLower.contains('animation')) {
            _animeRailCache[entry.key] = entry.value;
            sections.add(DynamicFeedSection(
              title: entry.key,
              items: entry.value,
              onAll: () => _applyPillFilter(tab, entry.key),
            ));
            if (heroCandidate.isEmpty) heroCandidate = entry.value;
          }
        }

        // 2. Web BFF Genre Rails for Anime
        final animeGenreQueries = [
          ('⚔️ Action & Shonen Anime', 'Action'),
          ('🔮 Fantasy & Isekai World', 'Fantasy'),
          ('🌸 Romance & Life', 'Romance'),
          ('🚀 Sci-Fi & Cyberpunk', 'Sci-Fi'),
          ('😂 Comedy Anime', 'Comedy'),
        ];
        for (final item in animeGenreQueries) {
          final aTitle = item.$1;
          final aGenre = item.$2;
          final aItems = await widget.apiService.fetchWebSubjectFilter(
            channelId: '1006',
            genre: aGenre,
            sort: 'Popular',
            perPage: 15,
          );
          if (aItems.isNotEmpty) {
            _animeRailCache[aTitle] = aItems;
            sections.add(DynamicFeedSection(
              title: aTitle,
              items: aItems,
              onAll: () => _applyPillFilter(tab, aTitle),
            ));
            if (heroCandidate.isEmpty) heroCandidate = aItems;
          }
        }

        // 3. Top Anime Movies
        final animeMovies = await widget.apiService.fetchWebSubjectFilter(
          channelId: '1',
          genre: 'Animation',
          sort: 'HighRating',
          perPage: 15,
        );
        if (animeMovies.isNotEmpty) {
          _animeRailCache['🎬 Top Anime Movies'] = animeMovies;
          sections.add(DynamicFeedSection(
            title: '🎬 Top Anime Movies',
            items: animeMovies,
            onAll: () => _applyPillFilter(tab, 'Anime Movies'),
          ));
        }

        _applyOrderingAndFiltering(tab, sections);

        if (sections.isNotEmpty && mounted && currentToken == tab.loadToken) {
          setState(() {
            tab.sections = sections;
            if (heroCandidate.isNotEmpty) tab.heroBanners = heroCandidate.take(5).toList();
            tab.isLoading = false;
          });
          return;
        }

        // Fallback: 1. Trending Anime
        descriptors.add(_SectionDescriptor(
          title: '🔥 Trending Anime',
          isHeroCandidate: true,
          loader: () => _safeBrowse(channelId: '1006', sort: 'Popular'),
        ));

        descriptors.add(_SectionDescriptor(
          title: '⚔️ Action & Shonen Anime',
          loader: () => _safeBrowse(channelId: '1006', genre: 'Action', sort: 'Popular'),
          onAll: () => _applyPillFilter(tab, 'Action'),
        ));

        descriptors.add(_SectionDescriptor(
          title: '🔮 Fantasy & Isekai World',
          loader: () => _safeBrowse(channelId: '1006', genre: 'Fantasy', sort: 'Popular'),
          onAll: () => _applyPillFilter(tab, 'Fantasy'),
        ));

        descriptors.add(_SectionDescriptor(
          title: '🌸 Romance & Slice of Life',
          loader: () => _safeBrowse(channelId: '1006', genre: 'Romance', sort: 'Popular'),
          onAll: () => _applyPillFilter(tab, 'Romance'),
        ));

        descriptors.add(_SectionDescriptor(
          title: '🚀 Sci-Fi & Cyberpunk',
          loader: () => _safeBrowse(channelId: '1006', genre: 'Sci-Fi', sort: 'Popular'),
          onAll: () => _applyPillFilter(tab, 'Sci-Fi'),
        ));

        descriptors.add(_SectionDescriptor(
          title: '😂 Comedy Anime',
          loader: () => _safeBrowse(channelId: '1006', genre: 'Comedy', sort: 'Popular'),
          onAll: () => _applyPillFilter(tab, 'Comedy'),
        ));

        descriptors.add(_SectionDescriptor(
          title: '🎬 Top Anime Movies',
          loader: () => _safeBrowse(channelId: '1', genre: 'Animation', sort: 'HighRating'),
          onAll: () => _applyPillFilter(tab, 'Movies'),
        ));
        break;

      case 6: // ShortTV Tab (Real Web Operating + Mini-Drama Rails)
        final homeRails = await _getHomeOperatingRails();
        final sections = <DynamicFeedSection>[];
        List<MediaItem> heroCandidate = [];

        // 1. Authentic Web Hot Short TV Rail
        for (final entry in homeRails.entries) {
          final tLower = entry.key.toLowerCase();
          if (tLower.contains('short') && !tLower.contains('sport') && entry.value.isNotEmpty) {
            _shortTvRailCache[entry.key] = entry.value;
            sections.add(DynamicFeedSection(
              title: entry.key,
              items: entry.value,
              onAll: () => _applyPillFilter(tab, entry.key),
            ));
            if (heroCandidate.isEmpty) heroCandidate = entry.value;
          }
        }

        // 2. Curated Mini-drama Subgenres
        final shortQueries = [
          ('👑 CEO & Billionaire Romance', 'CEO'),
          ('🐺 Werewolf & Supernatural', 'Werewolf'),
          ('⚡ Revenge & Drama Series', 'Revenge'),
          ('📱 Short Drama Showcase', 'Short Drama'),
        ];
        for (final item in shortQueries) {
          final sTitle = item.$1;
          final sKeyword = item.$2;
          final sItems = await _safeSearch(sKeyword, perPage: 12);
          if (sItems.isNotEmpty) {
            _shortTvRailCache[sTitle] = sItems;
            sections.add(DynamicFeedSection(
              title: sTitle,
              items: sItems,
              onAll: () => _applyPillFilter(tab, sTitle),
              searchKeyword: sKeyword,
            ));
            if (heroCandidate.isEmpty) heroCandidate = sItems;
          }
        }

        _applyOrderingAndFiltering(tab, sections);

        if (sections.isNotEmpty && mounted && currentToken == tab.loadToken) {
          setState(() {
            tab.sections = sections;
            if (heroCandidate.isNotEmpty) tab.heroBanners = heroCandidate.take(5).toList();
            tab.isLoading = false;
          });
          return;
        }

        // Fallback: 1. Trending Mini Dramas
        descriptors.add(_SectionDescriptor(
          title: '🔥 Trending Mini Dramas',
          isHeroCandidate: true,
          loader: () => _safeBrowse(channelId: '2', genre: 'Reality', sort: 'Popular'),
        ));

        descriptors.add(_SectionDescriptor(
          title: '👑 CEO & Billionaire Romance',
          loader: () => _safeSearch('CEO', perPage: 10),
          onAll: () => _applyPillFilter(tab, 'CEO Romance'),
          searchKeyword: 'CEO',
        ));

        descriptors.add(_SectionDescriptor(
          title: '🐺 Werewolf & Supernatural',
          loader: () => _safeSearch('Werewolf', perPage: 10),
          onAll: () => _applyPillFilter(tab, 'Werewolf'),
          searchKeyword: 'Werewolf',
        ));

        descriptors.add(_SectionDescriptor(
          title: '⚡ Revenge & Drama Series',
          loader: () => _safeSearch('Revenge', perPage: 10),
          onAll: () => _applyPillFilter(tab, 'Revenge'),
          searchKeyword: 'Revenge',
        ));

        descriptors.add(_SectionDescriptor(
          title: '📱 Short Drama Showcase',
          loader: () => _safeSearch('Short Drama', perPage: 10),
          onAll: () => _applyPillFilter(tab, 'Urban Love'),
          searchKeyword: 'Short Drama',
        ));
        break;
    }

    final results = await Future.wait(descriptors.map((d) => d.loader()));
    if (!mounted || currentToken != tab.loadToken) return;

    final sections = <DynamicFeedSection>[];
    List<MediaItem> heroCandidate = [];

    for (int i = 0; i < descriptors.length; i++) {
      final items = results[i];
      if (items.isNotEmpty) {
        sections.add(DynamicFeedSection(
          title: descriptors[i].title,
          items: items,
          onAll: descriptors[i].onAll,
          searchKeyword: descriptors[i].searchKeyword,
        ));
        if (heroCandidate.isEmpty && descriptors[i].isHeroCandidate) {
          heroCandidate = items;
        }
      }
    }

    _applyOrderingAndFiltering(tab, sections);

    setState(() {
      tab.sections = sections;
      tab.heroBanners = heroCandidate.isNotEmpty ? heroCandidate.take(3).toList() : [];
      tab.isLoading = false;
    });
  }

  // -------------------------------------------------------------
  // Bottom Continuous Infinite Feed Loader
  // -------------------------------------------------------------
  static const List<String> _midnightBottomRankingIds = [
    '8170622407217234072', // Vivamax
    '8448366367312612120', // 18+ Dramas
    '7364316894532720656', // Japanese 18+
    '7462810956096595192', // UllU Drama
    '4105487575106966448', // Korea 18+
    '4534646032008989032', // Indian 18+
    '3436880071141867768', // Porn Top Videos
  ];

  Future<List<MediaItem>> _fetchBottomFeedChunk(_CategoryTabState tab, int page) async {
    switch (tab.index) {
      case 1: // Trending: Alternating Movies & Series with ForYou
        final chId = (page % 2 == 1) ? '1' : '2';
        return await widget.apiService.fetchWebSubjectFilter(
          channelId: chId,
          sort: 'ForYou',
          page: (page + 1) ~/ 2,
          perPage: 18,
        );

      case 2: // Movie: Clean paginated movies
        return await widget.apiService.fetchWebSubjectFilter(
          channelId: '1',
          sort: 'ForYou',
          page: page,
          perPage: 18,
        );

      case 3: // TV: Clean paginated series
        return await widget.apiService.fetchWebSubjectFilter(
          channelId: '2',
          sort: 'ForYou',
          page: page,
          perPage: 18,
        );

      case 4: // MidNight: Cycle through the rich adult ranking lists
        final listIndex = (page - 1) % _midnightBottomRankingIds.length;
        final rankingId = _midnightBottomRankingIds[listIndex];
        final rankPage = ((page - 1) ~/ _midnightBottomRankingIds.length) + 1;
        return await widget.apiService.fetchRankingList(
          rankingId,
          page: rankPage,
          perPage: 18,
        );

      case 5: // Anime: Clean paginated anime
        return await widget.apiService.fetchWebSubjectFilter(
          channelId: '1006',
          sort: 'Popular',
          page: page,
          perPage: 18,
        );

      case 6: // ShortTV: Curated mini-drama search pagination
        final shortKeywords = ['Short Drama', 'CEO', 'Werewolf', 'Revenge'];
        final kw = shortKeywords[(page - 1) % shortKeywords.length];
        final kwPage = ((page - 1) ~/ shortKeywords.length) + 1;
        return await _safeSearch(kw, page: kwPage, perPage: 18);

      default:
        return await widget.apiService.fetchWebSubjectFilter(
          channelId: '1',
          sort: 'Popular',
          page: page,
          perPage: 18,
        );
    }
  }

  Future<void> _initBottomFeed(_CategoryTabState tab, int currentToken) async {
    tab.bottomPage = 1;
    tab.hasMoreBottom = true;

    final existingIds = <String>{
      ...tab.heroBanners.map((e) => e.subjectId),
      ...tab.sections.expand((s) => s.items).map((e) => e.subjectId),
    };

    List<MediaItem> items = [];
    int attempts = 0;
    while (items.length < 12 && attempts < 3) {
      attempts++;
      final chunk = await _fetchBottomFeedChunk(tab, tab.bottomPage);
      if (chunk.isEmpty) {
        tab.hasMoreBottom = false;
        break;
      }
      for (final item in chunk) {
        if (item.subjectId.isNotEmpty && existingIds.add(item.subjectId)) {
          items.add(item);
        }
      }
      if (items.length < 12) {
        tab.bottomPage++;
      }
    }

    if (mounted && currentToken == tab.loadToken) {
      setState(() => tab.bottomInfiniteFeed = items);
    }
  }

  Future<void> _loadMoreBottomFeed(_CategoryTabState tab) async {
    if (tab.isLoadingMoreBottom || !tab.hasMoreBottom) return;
    setState(() => tab.isLoadingMoreBottom = true);

    final existingIds = <String>{
      ...tab.heroBanners.map((e) => e.subjectId),
      ...tab.sections.expand((s) => s.items).map((e) => e.subjectId),
      ...tab.bottomInfiniteFeed.map((e) => e.subjectId),
    };

    List<MediaItem> uniqueItems = [];
    int attempts = 0;

    while (uniqueItems.length < 12 && attempts < 3) {
      attempts++;
      tab.bottomPage++;
      final chunk = await _fetchBottomFeedChunk(tab, tab.bottomPage);
      if (chunk.isEmpty) {
        tab.hasMoreBottom = false;
        break;
      }
      for (final item in chunk) {
        if (item.subjectId.isNotEmpty && existingIds.add(item.subjectId)) {
          uniqueItems.add(item);
        }
      }
    }

    if (mounted) {
      setState(() {
        if (uniqueItems.isNotEmpty) {
          tab.bottomInfiniteFeed.addAll(uniqueItems);
        }
        tab.isLoadingMoreBottom = false;
      });
    }
  }

  // -------------------------------------------------------------
  // Filtered Paged Grid Loader (When category pill or filters active)
  // -------------------------------------------------------------
  Future<List<MediaItem>> _fetchItemsForQuery(
    _ActiveCategoryQuery query, {
    required int page,
    int perPage = 18,
  }) async {
    switch (query.type) {
      case _QueryType.rankingList:
        if (query.rankingListId == null || query.rankingListId!.isEmpty) return [];
        return await widget.apiService.fetchRankingList(
          query.rankingListId!,
          page: page,
          perPage: perPage,
        );
      case _QueryType.searchKeyword:
        if (query.searchKeyword == null || query.searchKeyword!.isEmpty) return [];
        return await _safeSearch(
          query.searchKeyword!,
          page: page,
          perPage: perPage,
        );
      case _QueryType.subjectFilter:
        return await widget.apiService.fetchBrowseList(
          channelId: query.channelId ?? '1',
          classify: query.classify ?? 'All',
          country: query.country ?? 'All',
          year: query.year ?? 'All',
          genre: query.genre ?? 'All',
          sort: query.sort ?? 'ForYou',
          page: page,
          perPage: perPage,
        );
    }
  }

  _ActiveCategoryQuery _resolveTabQuery(_CategoryTabState tab) {
    final catalog = widget.storage.activeCatalog;
    String channelId = '1';
    String genre = tab.selectedGenre;
    String country = tab.selectedCountry;
    String year = tab.selectedYear;
    String classify = tab.selectedLanguage != 'All' ? tab.selectedLanguage : 'All';
    String sort = tab.selectedSort;

    switch (tab.index) {
      case 0: // Home Tab
        for (final cs in widget.storage.getHomeCustomSections()) {
          if (cs.title.toLowerCase().contains(tab.selectedPill.toLowerCase()) ||
              tab.selectedPill.toLowerCase().contains(cs.title.toLowerCase())) {
            if (cs.keyword != null && cs.keyword!.isNotEmpty) {
              return _ActiveCategoryQuery.search(cs.keyword!);
            } else {
              String ch = '1';
              if (cs.type == 'tv') ch = '2';
              if (cs.type == 'anime') ch = '1006';
              return _ActiveCategoryQuery.filter(
                channelId: ch,
                genre: (cs.genre != null && cs.genre != 'All') ? cs.genre! : 'All',
                country: (cs.country != null && cs.country != 'All') ? cs.country! : 'All',
                year: (cs.year != null && cs.year != 'All') ? cs.year! : 'All',
                sort: cs.sort,
              );
            }
          }
        }
        return _ActiveCategoryQuery.search(tab.selectedPill);

      case 1: // Trending Tab
        final pLower = tab.selectedPill.toLowerCase();
        if (pLower.contains('bangla') || pLower.contains('bengali')) {
          return const _ActiveCategoryQuery.filter(channelId: '2', country: 'Bangladesh', classify: 'Bengali dub');
        } else if (pLower.contains('bollywood') || pLower.contains('hindi')) {
          return const _ActiveCategoryQuery.filter(channelId: '1', country: 'India', classify: 'Hindi dub');
        } else if (pLower.contains('south indian') || pLower.contains('tamil') || pLower.contains('telugu')) {
          return const _ActiveCategoryQuery.filter(channelId: '1', country: 'India');
        } else if (pLower.contains('hollywood')) {
          return const _ActiveCategoryQuery.filter(channelId: '1', country: 'United States');
        } else if (pLower.contains('k-drama') || pLower.contains('korea')) {
          return const _ActiveCategoryQuery.filter(channelId: '2', country: 'Korea');
        } else if (pLower.contains('c-drama') || pLower.contains('china')) {
          return const _ActiveCategoryQuery.filter(channelId: '2', country: 'China');
        } else if (pLower.contains('anime')) {
          return const _ActiveCategoryQuery.filter(channelId: '1006');
        } else if (pLower.contains('short')) {
          return const _ActiveCategoryQuery.search('Short Drama');
        }
        return _ActiveCategoryQuery.search(tab.selectedPill);

      case 2: // Movie Tab
        channelId = '1';
        if (tab.selectedPill != 'All') {
          if (tab.selectedPill.contains(catalog.flag) || tab.selectedPill.contains(catalog.name.split(" (").first)) {
            if (catalog.classify != null) classify = catalog.classify!;
            if (catalog.defaultCountry != null) country = catalog.defaultCountry!;
          } else if (tab.selectedPill == 'Trending in Cinema') {
            sort = 'ForYou';
          } else if (tab.selectedPill == 'Top Movies') {
            sort = 'Popular';
          } else if (tab.selectedPill == 'New Release' || tab.selectedPill == 'Latest') {
            sort = 'Latest';
          } else if (_movieGenres.contains(tab.selectedPill)) {
            genre = tab.selectedPill;
          } else if (tab.selectedPill == 'Bollywood Love') {
            country = 'India';
            genre = 'Romance';
          } else if (tab.selectedPill == 'Comedies') {
            genre = 'Comedy';
          } else if (tab.selectedPill == 'Thrills & Crimes') {
            genre = 'Thriller';
          } else if (tab.selectedPill == 'Super Hero') {
            return const _ActiveCategoryQuery.search('Superhero');
          } else if (tab.selectedPill == 'Sci-Fi Future') {
            genre = 'Sci-Fi';
          }
        }
        return _ActiveCategoryQuery.filter(
          channelId: channelId,
          genre: genre,
          country: country,
          year: year,
          classify: classify,
          sort: sort,
        );

      case 3: // TV Tab
        channelId = '2';
        if (tab.selectedPill != 'All') {
          if (tab.selectedPill.contains(catalog.flag) || tab.selectedPill.contains(catalog.name.split(" (").first)) {
            if (catalog.defaultCountry != null) country = catalog.defaultCountry!;
            if (catalog.classify != null) classify = catalog.classify!;
          } else if (tab.selectedPill == 'K-Drama' || tab.selectedPill == 'Best Asian Dramas') {
            country = 'Korea';
          } else if (tab.selectedPill == 'C-Drama') {
            country = 'China';
          } else if (tab.selectedPill == 'Turkish Drama') {
            country = 'Turkey';
          } else if (tab.selectedPill == 'Pakistani TV') {
            country = 'Pakistan';
          } else if (tab.selectedPill == 'Western TV' || tab.selectedPill == 'US Dramas') {
            country = 'United States';
          } else if (tab.selectedPill == 'Indian Dramas') {
            country = 'India';
          } else if (tab.selectedPill == 'Crime & Mystery') {
            genre = 'Crime';
          } else if (tab.selectedPill == 'Sci-Fi & Fantasy') {
            genre = 'Sci-Fi';
          } else if (tab.selectedPill == 'Comedy Shows') {
            genre = 'Comedy';
          } else if (tab.selectedPill == 'Top Series') {
            sort = 'Popular';
          }
        }
        return _ActiveCategoryQuery.filter(
          channelId: channelId,
          genre: genre,
          country: country,
          year: year,
          classify: classify,
          sort: sort,
        );

      case 4: // MidNight🔞 Tab
        final p = tab.selectedPill;
        if (p == 'Vivamax' || p.toLowerCase().contains('vivamax')) {
          return const _ActiveCategoryQuery.rankingList('8170622407217234072');
        } else if (p == 'UllU Drama' || p.toLowerCase().contains('ullu drama')) {
          return const _ActiveCategoryQuery.rankingList('7462810956096595192');
        } else if (p == 'UllU Movie' || p.toLowerCase().contains('ullu movie')) {
          return const _ActiveCategoryQuery.rankingList('3613148068369032104');
        } else if (p == '18+ Dramas' || p.toLowerCase().contains('18+ drama')) {
          return const _ActiveCategoryQuery.rankingList('8448366367312612120');
        } else if (p == 'Porn Top Videos' || p.toLowerCase().contains('porn top')) {
          return const _ActiveCategoryQuery.rankingList('3436880071141867768');
        } else if (p == 'Late-night Shorts' || p.toLowerCase().contains('late-night')) {
          return const _ActiveCategoryQuery.rankingList('4283712533380449360');
        } else if (p == 'Hentai Anime' || p.toLowerCase().contains('hentai')) {
          return const _ActiveCategoryQuery.rankingList('1846783103277105520');
        } else if (p == 'Indian 18+' || p.toLowerCase().contains('indian 18+')) {
          return const _ActiveCategoryQuery.rankingList('4534646032008989032');
        } else if (p == 'Japanese 18+' || p.toLowerCase().contains('japanese 18+')) {
          return const _ActiveCategoryQuery.rankingList('7364316894532720656');
        } else if (p == 'Korea 18+' || p.toLowerCase().contains('korea 18+')) {
          return const _ActiveCategoryQuery.rankingList('4105487575106966448');
        } else if (p == 'Chinese 18+' || p.toLowerCase().contains('chinese 18+')) {
          return const _ActiveCategoryQuery.rankingList('3628141198977782704');
        } else if (p == 'Tbonx' || p.toLowerCase().contains('tbonx')) {
          return const _ActiveCategoryQuery.rankingList('4543422163096946912');
        } else if (p == 'Cinepop' || p.toLowerCase().contains('cinepop')) {
          return const _ActiveCategoryQuery.rankingList('8805880198798493664');
        }
        if (p != 'All') {
          return _ActiveCategoryQuery.search(p);
        }
        return const _ActiveCategoryQuery.rankingList('8170622407217234072');

      case 5: // Anime Tab
        channelId = '1006';
        if (tab.selectedPill == 'Anime Movies') {
          channelId = '1';
          genre = 'Animation';
          sort = 'HighRating';
        } else if (tab.selectedPill == 'Action & Shonen') {
          genre = 'Action';
        } else if (tab.selectedPill == 'Fantasy & Isekai') {
          genre = 'Fantasy';
        } else if (tab.selectedPill == 'Romance & Life') {
          genre = 'Romance';
        } else if (tab.selectedPill == 'Sci-Fi & Cyberpunk') {
          genre = 'Sci-Fi';
        } else if (tab.selectedPill == 'Comedy Anime') {
          genre = 'Comedy';
        } else if (tab.selectedPill == 'Top Anime Series') {
          sort = 'Popular';
        } else if (tab.selectedPill == 'Must-Watch Anime') {
          sort = 'HighRating';
        }
        return _ActiveCategoryQuery.filter(
          channelId: channelId,
          genre: genre,
          country: country,
          year: year,
          classify: classify,
          sort: sort,
        );

      case 6: // ShortTV Tab
        String keyword = tab.selectedPill;
        if (tab.selectedPill == 'CEO Romance') keyword = 'CEO';
        if (tab.selectedPill == 'Werewolf') keyword = 'Werewolf';
        if (tab.selectedPill == 'Revenge') keyword = 'Revenge';
        if (tab.selectedPill == 'Short Drama' || tab.selectedPill == 'Hot Short TV' || tab.selectedPill == 'All') {
          keyword = 'Short Drama';
        }
        return _ActiveCategoryQuery.search(keyword);

      default:
        return _ActiveCategoryQuery.search(tab.selectedPill);
    }
  }

  Future<void> _loadPagedCategory(_CategoryTabState tab, int currentToken) async {
    tab.hasMorePagedItems = true;
    _ActiveCategoryQuery? query;

    // 1. Check if user tapped a rail ("All") that exists in tab.sections
    if (tab.selectedPill != 'All') {
      DynamicFeedSection? matchedSection;
      for (final s in tab.sections) {
        if (s.title.toLowerCase().trim() == tab.selectedPill.toLowerCase().trim() ||
            s.title.toLowerCase().contains(tab.selectedPill.toLowerCase())) {
          matchedSection = s;
          break;
        }
      }

      if (matchedSection != null) {
        if (matchedSection.genreTopId != null && matchedSection.genreTopId!.isNotEmpty) {
          query = _ActiveCategoryQuery.rankingList(matchedSection.genreTopId!);
        } else if (matchedSection.searchKeyword != null && matchedSection.searchKeyword!.isNotEmpty) {
          query = _ActiveCategoryQuery.search(matchedSection.searchKeyword!);
        } else if (matchedSection.channelId != null || matchedSection.genre != null || matchedSection.country != null) {
          query = _ActiveCategoryQuery.filter(
            channelId: matchedSection.channelId ?? (tab.index == 3 ? '2' : (tab.index == 5 ? '1006' : '1')),
            genre: matchedSection.genre ?? 'All',
            country: matchedSection.country ?? 'All',
            classify: matchedSection.classify ?? 'All',
            sort: matchedSection.sort ?? (tab.index >= 4 ? 'Popular' : 'ForYou'),
          );
        }
      }
    }

    // 2. If no section query matched, resolve based on tab index and selectedPill / dropdown filters
    query ??= _resolveTabQuery(tab);
    tab.activeQuery = query;

    // 3. Fast in-memory resolution for instant display if rail items exist
    List<MediaItem> initialItems = [];
    if (tab.selectedPill != 'All') {
      for (final s in tab.sections) {
        if (s.title.toLowerCase().trim() == tab.selectedPill.toLowerCase().trim() ||
            s.title.toLowerCase().contains(tab.selectedPill.toLowerCase())) {
          if (s.items.isNotEmpty) {
            initialItems = List.from(s.items);
            break;
          }
        }
      }
    }

    if (initialItems.isNotEmpty) {
      if (mounted && currentToken == tab.loadToken) {
        setState(() {
          tab.pagedItems = initialItems;
          tab.isLoading = false;
        });
      }
      // If the rail only had preview items (e.g. <= 6), proactively fetch page 1 to fill out the grid
      if (initialItems.length < 15) {
        try {
          final fetched = await _fetchItemsForQuery(query, page: 1, perPage: 18);
          if (mounted && currentToken == tab.loadToken && fetched.isNotEmpty) {
            final existing = tab.pagedItems.map((e) => e.subjectId).toSet();
            final unique = fetched.where((e) => e.subjectId.isNotEmpty && existing.add(e.subjectId)).toList();
            if (unique.isNotEmpty) {
              setState(() {
                tab.pagedItems.addAll(unique);
              });
            }
          }
        } catch (_) {}
      }
      return;
    }

    // 4. Otherwise fetch Page 1 fresh
    try {
      final items = await _fetchItemsForQuery(query, page: 1, perPage: 18);
      if (mounted && currentToken == tab.loadToken) {
        setState(() {
          tab.pagedItems = items;
          tab.isLoading = false;
          if (items.isEmpty) tab.hasMorePagedItems = false;
        });
      }
    } catch (_) {
      if (mounted && currentToken == tab.loadToken) {
        setState(() {
          tab.isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMorePagedItems(_CategoryTabState tab) async {
    if (tab.isLoadingMore || !tab.hasMorePagedItems) return;
    setState(() => tab.isLoadingMore = true);
    tab.currentPage++;

    final query = tab.activeQuery ?? _resolveTabQuery(tab);
    tab.activeQuery = query;

    try {
      final nextItems = await _fetchItemsForQuery(query, page: tab.currentPage, perPage: 18);
      if (mounted) {
        final existingIds = tab.pagedItems.map((e) => e.subjectId).toSet();
        final uniqueItems = nextItems.where((e) => e.subjectId.isNotEmpty && existingIds.add(e.subjectId)).toList();

        if (nextItems.isEmpty || (nextItems.isNotEmpty && uniqueItems.isEmpty && tab.currentPage > 2)) {
          tab.hasMorePagedItems = false;
        }

        setState(() {
          if (uniqueItems.isNotEmpty) {
            tab.pagedItems.addAll(uniqueItems);
          }
          tab.isLoadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => tab.isLoadingMore = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleTabs;
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: SafeArea(
        bottom: false,
        child: PageView(
          controller: _pageController,
          onPageChanged: (index) {
            if (_selectedCategoryIndex != index) {
              setState(() {
                _selectedCategoryIndex = index;
              });
              if (index < visible.length) {
                final tab = visible[index];
                if (!tab.hasLoadedOnce && !tab.isLoading) {
                  _loadTabState(tab);
                }
              }
              widget.onCategoryChanged?.call(index);
            }
          },
          children: visible.map((tab) => _KeepAliveTabView(child: _buildTabView(tab))).toList(),
        ),
      ),
    );
  }

  Widget _buildTabView(_CategoryTabState tab) {
    if (tab.index == 7) {
      return BuzzBoxTab(
        apiService: widget.apiService,
        storage: widget.storage,
      );
    }

    if (!tab.hasLoadedOnce && tab.isLoading) {
      return Center(child: CircularProgressIndicator(color: AppTheme.accentGreen));
    }

    if (!tab.hasLoadedOnce && !tab.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!tab.hasLoadedOnce && !tab.isLoading) {
          _loadTabState(tab);
        }
      });
      return Center(child: CircularProgressIndicator(color: AppTheme.accentGreen));
    }

    return Column(
      children: [
        if (tab.index <= 1 && !tab.isRailsMode)
          _buildPillHeader(tab),
        if (tab.index > 1) _buildCategoryPills(tab),
        if (tab.index > 1) _buildFilterToolbars(tab),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Permanent Rails Feed (Kept alive in Offstage when in grid mode to preserve exact scroll offset and horizontal rail states)
              Offstage(
                offstage: !tab.isRailsMode,
                child: RefreshIndicator(
                  color: AppTheme.accentGreen,
                  backgroundColor: AppTheme.bgSecondary,
                  onRefresh: () => _refreshTab(tab),
                  child: _buildDynamicFeedView(tab),
                ),
              ),

              // 2. Section "All" / Filter Grid View (Rendered on top when !tab.isRailsMode)
              if (!tab.isRailsMode)
                RefreshIndicator(
                  color: AppTheme.accentGreen,
                  backgroundColor: AppTheme.bgSecondary,
                  onRefresh: () => _refreshTab(tab),
                  child: _buildPagedGridView(tab),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPillHeader(_CategoryTabState tab) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppTheme.bgPrimary,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => _resetAllFilters(tab),
          ),
          Expanded(
            child: Text(
              tab.selectedPill,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () => _resetAllFilters(tab),
            child: Text('Back to Home', style: TextStyle(color: AppTheme.accentGreen)),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Unified Category Quick Pills
  // -------------------------------------------------------------
  Widget _buildCategoryPills(_CategoryTabState tab) {
    final pills = _getPillsForCategory(tab.index);
    if (pills.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(vertical: 4),
      color: AppTheme.bgPrimary,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: pills.length,
        itemBuilder: (context, index) {
          final item = pills[index];
          final isSel = tab.selectedPill == item;
          return GestureDetector(
            onTap: () {
              setState(() => tab.selectedPill = item);
              _loadTabState(tab);
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: isSel ? AppTheme.accentGreen : AppTheme.bgSecondary,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSel ? AppTheme.accentGreen : AppTheme.borderSubtle,
                ),
              ),
              child: Center(
                child: Text(
                  item,
                  style: TextStyle(
                    color: isSel ? Colors.black : Colors.white,
                    fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------
  // Filter Toolbars (Genre, Country, Year, Dub, Sort)
  // -------------------------------------------------------------
  Widget _buildFilterToolbars(_CategoryTabState tab) {
    List<String> currentGenres = _movieGenres;
    if (tab.index == 3) {
      currentGenres = _tvGenres;
    } else if (tab.index == 4) {
      currentGenres = _midnightGenres;
    } else if (tab.index == 5) {
      currentGenres = _animeGenres;
    } else if (tab.index == 6) {
      currentGenres = _shortTvGenres;
    }

    final defaultSort = (tab.index >= 4) ? 'Popular' : 'ForYou';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      color: AppTheme.bgPrimary,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildDropdownChip(
              label: tab.selectedGenre == 'All' ? 'Genre' : tab.selectedGenre,
              isActive: tab.selectedGenre != 'All',
              onTap: () => _showFilterDialog(
                title: 'Select Genre',
                options: currentGenres,
                selected: tab.selectedGenre,
                onSelected: (val) {
                  setState(() => tab.selectedGenre = val);
                  _loadTabState(tab);
                },
              ),
            ),
            const SizedBox(width: 8),
            _buildDropdownChip(
              label: tab.selectedCountry == 'All' ? 'Country' : tab.selectedCountry,
              isActive: tab.selectedCountry != 'All',
              onTap: () => _showFilterDialog(
                title: 'Select Country',
                options: _countries,
                selected: tab.selectedCountry,
                onSelected: (val) {
                  setState(() => tab.selectedCountry = val);
                  _loadTabState(tab);
                },
              ),
            ),
            const SizedBox(width: 8),
            _buildDropdownChip(
              label: tab.selectedYear == 'All' ? 'Year' : tab.selectedYear,
              isActive: tab.selectedYear != 'All',
              onTap: () => _showFilterDialog(
                title: 'Select Year',
                options: _years,
                selected: tab.selectedYear,
                onSelected: (val) {
                  setState(() => tab.selectedYear = val);
                  _loadTabState(tab);
                },
              ),
            ),
            const SizedBox(width: 8),
            _buildDropdownChip(
              label: tab.selectedLanguage == 'All' ? 'Language / Dub' : tab.selectedLanguage,
              isActive: tab.selectedLanguage != 'All',
              onTap: () => _showFilterDialog(
                title: 'Select Language / Dubbing',
                options: _languages,
                selected: tab.selectedLanguage,
                onSelected: (val) {
                  setState(() => tab.selectedLanguage = val);
                  _loadTabState(tab);
                },
              ),
            ),
            const SizedBox(width: 8),
            _buildDropdownChip(
              label: 'Sort: ${tab.selectedSort}',
              isActive: tab.selectedSort != defaultSort,
              onTap: () => _showFilterDialog(
                title: 'Sort By',
                options: _sortOptions,
                selected: tab.selectedSort,
                onSelected: (val) {
                  setState(() => tab.selectedSort = val);
                  _loadTabState(tab);
                },
              ),
            ),
            if (tab.hasActiveFilters) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _resetAllFilters(tab),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh, color: Colors.redAccent, size: 14),
                      SizedBox(width: 4),
                      Text('Reset', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownChip({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.accentGreen.withValues(alpha: 0.2) : AppTheme.bgSecondary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? AppTheme.accentGreen : AppTheme.borderSubtle,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isActive ? AppTheme.accentGreen : Colors.white70,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              color: isActive ? AppTheme.accentGreen : Colors.white54,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  void _showFilterDialog({
    required String title,
    required List<String> options,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, idx) {
                    final opt = options[idx];
                    final isSel = opt == selected;
                    return ListTile(
                      title: Text(
                        opt,
                        style: TextStyle(
                          color: isSel ? AppTheme.accentGreen : Colors.white70,
                          fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      trailing: isSel ? Icon(Icons.check, color: AppTheme.accentGreen) : null,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        onSelected(opt);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // -------------------------------------------------------------
  // Dynamic Feed View: Single unified renderer for all rails tabs
  // -------------------------------------------------------------
  Widget _buildDynamicFeedView(_CategoryTabState tab) {
    return ListView(
      key: PageStorageKey('rails_feed_${tab.index}'),
      controller: tab.scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 110),
      children: [
        if (tab.heroBanners.isNotEmpty)
          HeroCarouselWidget(
            items: tab.heroBanners,
            apiService: widget.apiService,
            storage: widget.storage,
            isActive: _selectedCategoryIndex == tab.index,
          ),
        _buildCustomizeBar(tab),
        if (tab.index == 0 && tab.sections.isEmpty)
          _buildEmptyHomeFeed(tab),
        for (final section in tab.sections)
          _buildFeedSection(section),
        if (tab.index == 0)
          _buildCustomizeHomeFeedCard(tab),
        if (tab.index != 0 && tab.bottomInfiniteFeed.isNotEmpty)
          _buildBottomFeedSection(tab, '🔥 Explore More ${_getTabTitle(tab)}'),
      ],
    );
  }

  void _openSectionCustomizer(_CategoryTabState tab) {
    SectionCustomizerSheet.show(
      context: context,
      tabIndex: tab.index,
      tabName: _getTabTitle(tab),
      currentSections: tab.sections,
      storage: widget.storage,
      apiService: widget.apiService,
      onSectionsUpdated: () {
        setState(() {
          _homeCustomRailCache.clear();
          tab.invalidate();
        });
        _loadTabState(tab);
      },
    );
  }

  Widget _buildCustomizeBar(_CategoryTabState tab) {
    final tabName = _getTabTitle(tab);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
              Row(
                children: [
                  Container(
                    width: 3,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppTheme.accentGreen,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$tabName Feeds',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                  if (widget.storage.feedEdition == FeedEdition.mobile) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.accentGreen.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: AppTheme.accentGreen.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.phone_android,
                              size: 10, color: AppTheme.accentGreen),
                          const SizedBox(width: 3),
                          Text(
                            widget.storage.activeCatalog.flag,
                            style: const TextStyle(fontSize: 10),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            widget.storage.activeRegion,
                            style: TextStyle(
                              color: AppTheme.accentGreen,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
          GestureDetector(
            onTap: () => _openSectionCustomizer(tab),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune, color: AppTheme.accentGreen, size: 13),
                  const SizedBox(width: 5),
                  const Text(
                    'Customize',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyHomeFeed(_CategoryTabState tab) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.accentGreen.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.history_toggle_off, color: AppTheme.accentGreen, size: 36),
          ),
          const SizedBox(height: 16),
          const Text(
            'Your Home Feed',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Continue Watching will appear here as you stream movies & series. You can also customize this Home feed by adding rails from the Library.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: AppTheme.bgSecondary,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      builder: (_) => LibrarySectionPickerSheet(
                        storage: widget.storage,
                        onSectionSelected: (title, type, keyword, genre, country, sort) async {
                          final config = CustomSectionConfig(
                            id: 'lib_${DateTime.now().millisecondsSinceEpoch}',
                            title: title,
                            type: type,
                            keyword: keyword,
                            genre: genre,
                            country: country,
                            sort: sort,
                            isCustom: true,
                            librarySource: 'library_preset',
                          );
                          await widget.storage.addHomeCustomSection(config);
                          setState(() {
                            _homeCustomRailCache.clear();
                            tab.invalidate();
                          });
                          _loadTabState(tab);
                        },
                      ),
                    );
                  },
                  icon: const Icon(Icons.library_add, size: 16),
                  label: const Text('Add from Library', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentGreen,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setCategoryIndex(1),
                  icon: const Icon(Icons.local_fire_department, size: 16, color: Colors.orangeAccent),
                  label: const Text('Explore Trending', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.orangeAccent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCustomizeHomeFeedCard(_CategoryTabState tab) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderSubtle),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.bgCard,
            AppTheme.accentGreen.withValues(alpha: 0.08),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.accentGreen.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.dashboard_customize, color: AppTheme.accentGreen, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Personalize Your Home',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Add custom rails from presets or search & filter tools',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _openSectionCustomizer(tab),
                  icon: const Icon(Icons.tune, size: 16),
                  label: const Text('Customize Feed', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentGreen,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: AppTheme.bgSecondary,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      builder: (_) => LibrarySectionPickerSheet(
                        storage: widget.storage,
                        onSectionSelected: (title, type, keyword, genre, country, sort) async {
                          final config = CustomSectionConfig(
                            id: 'lib_${DateTime.now().millisecondsSinceEpoch}',
                            title: title,
                            type: type,
                            keyword: keyword,
                            genre: genre,
                            country: country,
                            sort: sort,
                            isCustom: true,
                            librarySource: 'library_preset',
                          );
                          await widget.storage.addHomeCustomSection(config);
                          setState(() {
                            _homeCustomRailCache.clear();
                            tab.invalidate();
                          });
                          _loadTabState(tab);
                        },
                      ),
                    );
                  },
                  icon: Icon(Icons.library_add, size: 16, color: AppTheme.accentCyan),
                  label: const Text('Add Rail', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppTheme.accentCyan),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Feed Section (Horizontal Scrollable Rail)
  // -------------------------------------------------------------
  Widget _buildFeedSection(DynamicFeedSection section) {
    final title = section.title;
    final items = section.items;
    final onAll = section.onAll;
    final isPost = section.isPostList;
    final hasSubTabs = section.subTabs != null && section.subTabs!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (onAll != null)
                GestureDetector(
                  onTap: onAll,
                  child: const Row(
                    children: [
                      Text(
                        'All',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(Icons.chevron_right, color: AppTheme.textSecondary, size: 16),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // Sub-Tab Filter Pills (for RANKING_LIST_MULTI_TAB)
        if (hasSubTabs)
          Container(
            height: 34,
            margin: const EdgeInsets.only(bottom: 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: section.subTabs!.length,
              itemBuilder: (context, subIdx) {
                final sub = section.subTabs![subIdx];
                final isSelected = subIdx == section.activeSubTabIndex;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      section.activeSubTabIndex = subIdx;
                      section.items = sub.items;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.accentGreen : AppTheme.bgSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? AppTheme.accentGreen : AppTheme.borderSubtle,
                      ),
                    ),
                    child: Text(
                      sub.title,
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white70,
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

        SizedBox(
          height: isPost ? 240 : 195,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return isPost
                  ? _buildPostHorizontalCard(item, allItems: items, initialIndex: index)
                  : _buildHorizontalCard(item, rankIndex: index + 1, allItems: items, initialIndex: index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPostHorizontalCard(MediaItem item, {List<MediaItem>? allItems, int initialIndex = 0}) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ShortVideoPlayerScreen(
              items: (allItems != null && allItems.isNotEmpty) ? allItems : [item],
              initialIndex: initialIndex,
              apiService: widget.apiService,
            ),
          ),
        );
      },
      child: Container(
        width: 125,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AspectRatio(
                    aspectRatio: 9 / 14,
                    child: (item.coverUrl != null && item.coverUrl!.startsWith('http'))
                        ? CachedNetworkImage(
                            imageUrl: item.coverUrl!,
                            fit: BoxFit.cover,
                            memCacheWidth: 250,
                            memCacheHeight: 400,
                            placeholder: (context, url) => Container(color: AppTheme.bgSurface),
                            errorWidget: (context, url, error) => Container(
                              color: AppTheme.bgSurface,
                              child: const Icon(Icons.movie, color: Colors.white30),
                            ),
                          )
                        : Container(color: AppTheme.bgSurface),
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.75),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow, color: Colors.white, size: 14),
                  ),
                ),
                if (item.authorName != null && item.authorName!.isNotEmpty)
                  Positioned(
                    bottom: 6,
                    left: 6,
                    right: 6,
                    child: Row(
                      children: [
                        if (item.authorAvatar != null && item.authorAvatar!.isNotEmpty)
                          CircleAvatar(
                            radius: 7,
                            backgroundImage: CachedNetworkImageProvider(item.authorAvatar!),
                          ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item.authorName!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHorizontalCard(MediaItem item, {required int rankIndex, List<MediaItem>? allItems, int initialIndex = 0}) {
    return GestureDetector(
      onTap: () {
        final isShortOrPost = item.isPost ||
            item.subjectType == 9 ||
            (item.genre != null && item.genre!.toLowerCase().contains('short')) ||
            (item.videoUrl != null && item.videoUrl!.isNotEmpty && (item.subjectId == '0' || item.subjectId.isEmpty)) ||
            (item.deepLink != null && (item.deepLink!.contains('/post/') || item.deepLink!.contains('detailVideo')));

        if (isShortOrPost) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ShortVideoPlayerScreen(
                items: (allItems != null && allItems.isNotEmpty) ? allItems : [item],
                initialIndex: initialIndex,
                apiService: widget.apiService,
              ),
            ),
          );
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DetailScreen(
                subjectId: item.subjectId,
                apiService: widget.apiService,
              ),
            ),
          );
        }
      },
      onLongPress: () {
        showBouncyCategorySheet(
          context: context,
          storage: widget.storage,
          mediaItem: item,
        );
      },
      child: Container(
        width: 110,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: (item.coverUrl != null && item.coverUrl!.startsWith('http'))
                        ? CachedNetworkImage(
                            imageUrl: item.coverUrl!,
                            fit: BoxFit.cover,
                            memCacheWidth: 200,
                            memCacheHeight: 300,
                            placeholder: (context, url) => Container(color: AppTheme.bgSurface),
                            errorWidget: (context, url, error) => Container(
                              color: AppTheme.bgSurface,
                              child: const Icon(Icons.movie, color: Colors.white30),
                            ),
                          )
                        : Container(color: AppTheme.bgSurface),
                  ),
                ),
                if (rankIndex <= 3)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppTheme.badgeGold,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '$rankIndex',
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                if (item.imdbRating != null && item.imdbRating!.isNotEmpty)
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, color: AppTheme.badgeGold, size: 10),
                          const SizedBox(width: 2),
                          Text(
                            item.imdbRating!,
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // Bottom Infinite-Scroll Grid Component (Appears below rails)
  // -------------------------------------------------------------
  Widget _buildBottomFeedSection(_CategoryTabState tab, String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accentGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Infinite Feed',
                  style: TextStyle(color: AppTheme.accentGreen, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: tab.bottomInfiniteFeed.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.60,
            crossAxisSpacing: 8,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, index) {
            final item = tab.bottomInfiniteFeed[index];
            return _buildGridCard(item);
          },
        ),
        if (tab.isLoadingMoreBottom)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: CircularProgressIndicator(color: AppTheme.accentGreen, strokeWidth: 2.5),
            ),
          ),
      ],
    );
  }

  // -------------------------------------------------------------
  // Paged Grid View (Used when filters or category pills are active)
  // -------------------------------------------------------------
  Widget _buildPagedGridView(_CategoryTabState tab) {
    if (tab.isLoading && tab.pagedItems.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: AppTheme.accentGreen),
      );
    }
    if (tab.pagedItems.isEmpty && !tab.isLoading) {
      return ListView(
        controller: tab.gridScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.movie_filter_outlined, color: AppTheme.textMuted, size: 54),
                  const SizedBox(height: 12),
                  const Text(
                    'No titles found for selected criteria',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => _resetAllFilters(tab),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentGreen,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: const Text('Reset Filters', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return CustomScrollView(
      controller: tab.gridScrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.60,
              crossAxisSpacing: 8,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = tab.pagedItems[index];
                return _buildGridCard(item);
              },
              childCount: tab.pagedItems.length,
            ),
          ),
        ),
        if (tab.isLoadingMore)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.accentGreen, strokeWidth: 2.5),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGridCard(MediaItem item) {
    return GestureDetector(
      onTap: () {
        final isShortOrPost = item.isPost ||
            item.subjectType == 9 ||
            (item.genre != null && item.genre!.toLowerCase().contains('short')) ||
            (item.videoUrl != null && item.videoUrl!.isNotEmpty && (item.subjectId == '0' || item.subjectId.isEmpty)) ||
            (item.deepLink != null && (item.deepLink!.contains('/post/') || item.deepLink!.contains('detailVideo')));

        if (isShortOrPost) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ShortVideoPlayerScreen(
                items: [item],
                initialIndex: 0,
                apiService: widget.apiService,
              ),
            ),
          );
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DetailScreen(
                subjectId: item.subjectId,
                apiService: widget.apiService,
              ),
            ),
          );
        }
      },
      onLongPress: () {
        showBouncyCategorySheet(
          context: context,
          storage: widget.storage,
          mediaItem: item,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox.expand(
                    child: (item.coverUrl != null && item.coverUrl!.startsWith('http'))
                        ? CachedNetworkImage(
                            imageUrl: item.coverUrl!,
                            fit: BoxFit.cover,
                            memCacheWidth: 220,
                            memCacheHeight: 330,
                            placeholder: (context, url) => Container(color: AppTheme.bgSurface),
                            errorWidget: (context, url, error) => Container(
                              color: AppTheme.bgSurface,
                              child: const Icon(Icons.movie, color: Colors.white30),
                            ),
                          )
                        : Container(color: AppTheme.bgSurface),
                  ),
                ),
                if (item.imdbRating != null && item.imdbRating!.isNotEmpty)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, color: AppTheme.badgeGold, size: 10),
                          const SizedBox(width: 2),
                          Text(
                            item.imdbRating!,
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (item.releaseDate != null)
            Text(
              item.releaseDate!.split('-').first,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
            ),
        ],
      ),
    );
  }
}

// =============================================================
// Hero Carousel Widget (Cinematic 16:9 Auto-Scrolling Carousel)
// =============================================================
class HeroCarouselWidget extends StatefulWidget {
  final List<MediaItem> items;
  final MovieBoxApiService apiService;
  final LocalStorageService storage;
  final bool isActive;

  const HeroCarouselWidget({
    super.key,
    required this.items,
    required this.apiService,
    required this.storage,
    this.isActive = true,
  });

  @override
  State<HeroCarouselWidget> createState() => _HeroCarouselWidgetState();
}

class _HeroCarouselWidgetState extends State<HeroCarouselWidget> with WidgetsBindingObserver {
  late final PageController _pageController;
  int _currentPage = 0;
  Timer? _timer;
  bool _isInteracting = false;
  bool _isAppPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController();
    if (widget.isActive) {
      _startTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppPaused = (state != AppLifecycleState.resumed);
    if (_isAppPaused) {
      _timer?.cancel();
    } else if (widget.isActive) {
      _startTimer();
    }
  }

  @override
  void didUpdateWidget(covariant HeroCarouselWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) {
      _currentPage = 0;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
      if (widget.isActive && !_isAppPaused) {
        _startTimer();
      }
    } else if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive && !_isAppPaused) {
        _startTimer();
      } else {
        _timer?.cancel();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    if (!widget.isActive || _isAppPaused || widget.items.length <= 1) return;
    _timer = Timer.periodic(const Duration(milliseconds: 4800), (_) {
      if (!mounted || !widget.isActive || _isAppPaused || _isInteracting || widget.items.isEmpty) return;
      if (_pageController.hasClients) {
        final next = (_currentPage + 1) % widget.items.length;
        _pageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.bgSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.borderSubtle),
                ),
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollStartNotification) {
                      _isInteracting = true;
                    } else if (notification is ScrollEndNotification) {
                      _isInteracting = false;
                      _startTimer();
                    }
                    return false;
                  },
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: widget.items.length,
                    onPageChanged: (idx) {
                      setState(() {
                        _currentPage = idx;
                      });
                    },
                    itemBuilder: (context, index) {
                      final item = widget.items[index];
                      return _buildSlide(item);
                    },
                  ),
                ),
              ),
            ),
          ),
          if (widget.items.length > 1) ...[
            const SizedBox(height: 8),
            _buildPageIndicators(),
          ],
        ],
      ),
    );
  }

  Widget _buildSlide(MediaItem item) {
    return GestureDetector(
      onTap: () {
        final isShortOrPost = item.isPost ||
            item.subjectType == 9 ||
            (item.genre != null && item.genre!.toLowerCase().contains('short')) ||
            (item.videoUrl != null && item.videoUrl!.isNotEmpty && (item.subjectId == '0' || item.subjectId.isEmpty)) ||
            (item.deepLink != null && (item.deepLink!.contains('/post/') || item.deepLink!.contains('detailVideo')));

        if (isShortOrPost) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ShortVideoPlayerScreen(
                items: widget.items,
                initialIndex: _currentPage,
                apiService: widget.apiService,
              ),
            ),
          );
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DetailScreen(
                subjectId: item.subjectId,
                apiService: widget.apiService,
              ),
            ),
          );
        }
      },
      onLongPress: () {
        showBouncyCategorySheet(
          context: context,
          storage: widget.storage,
          mediaItem: item,
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Full 16:9 Backdrop Image
          if (item.coverUrl != null && item.coverUrl!.startsWith('http'))
            CachedNetworkImage(
              imageUrl: item.coverUrl!,
              fit: BoxFit.cover,
              memCacheWidth: 720,
              memCacheHeight: 405,
              placeholder: (context, url) => Container(color: const Color(0xFF15191E)),
              errorWidget: (context, url, error) => Container(
                color: const Color(0xFF15191E),
                child: const Center(
                  child: Icon(Icons.movie_outlined, color: Colors.white24, size: 48),
                ),
              ),
            )
          else
            Container(color: const Color(0xFF15191E)),

          // 2. Cinematic Gradient Scrim (Vertical Bottom Fade)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.15),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.4),
                  Colors.black.withValues(alpha: 0.85),
                  Colors.black.withValues(alpha: 0.96),
                ],
                stops: const [0.0, 0.25, 0.55, 0.8, 1.0],
              ),
            ),
          ),

          // 3. Vignette Gradient (Left to Right) for High Text Contrast
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.black.withValues(alpha: 0.65),
                  Colors.black.withValues(alpha: 0.2),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.5, 0.85],
              ),
            ),
          ),

          // 4. Badges (Top Left & Top Right)
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.accentGreen,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accentGreen.withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.local_fire_department, size: 12, color: Colors.black),
                  SizedBox(width: 3),
                  Text(
                    'FEATURED',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (item.imdbRating != null && item.imdbRating!.isNotEmpty)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.badgeGold.withValues(alpha: 0.6)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, color: AppTheme.badgeGold, size: 13),
                    const SizedBox(width: 3),
                    Text(
                      item.imdbRating!,
                      style: const TextStyle(
                        color: AppTheme.badgeGold,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 5. Title & Info Overlay at Bottom
          Positioned(
            left: 14,
            right: 14,
            bottom: 12,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          shadows: [
                            Shadow(
                              color: Colors.black,
                              offset: Offset(0, 1),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (item.genre != null && item.genre!.isNotEmpty) ...[
                            Flexible(
                              child: Text(
                                item.genre!.split(',').take(2).join(' • '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          if (item.releaseDate != null && item.releaseDate!.isNotEmpty) ...[
                            Text(
                              item.releaseDate!.split('-').first,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Play Action Button
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppTheme.accentGreen,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accentGreen.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_arrow_rounded, color: Colors.black, size: 16),
                      SizedBox(width: 2),
                      Text(
                        'Watch',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageIndicators() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.items.length, (index) {
        final isSelected = index == _currentPage;
        return GestureDetector(
          onTap: () {
            _pageController.animateToPage(
              index,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: isSelected ? 18 : 6,
            height: 4,
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.accentGreen : Colors.white.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }),
    );
  }
}

class _KeepAliveTabView extends StatefulWidget {
  final Widget child;

  const _KeepAliveTabView({required this.child});

  @override
  State<_KeepAliveTabView> createState() => _KeepAliveTabViewState();
}

class _KeepAliveTabViewState extends State<_KeepAliveTabView> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
