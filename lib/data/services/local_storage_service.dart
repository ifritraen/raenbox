import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_presets.dart';
import '../models/moviebox_models.dart';

enum FeedEdition {
  web,
  mobile,
}

class LocalStorageService extends ChangeNotifier {
  static LocalStorageService? _instance;
  static SharedPreferences? _prefs;

  static const String _keyHistory = 'mb_watch_history';
  static const String _keyFavorites = 'mb_favorites';
  static const String _keyBookmarks = 'mb_bookmarks';
  static const String _keyMyListCategories = 'mb_my_list_categories';
  static const String _keyDownloads = 'mb_downloads';
  static const String _keyRegion = 'mb_active_region';
  static const String _keyIsAutoRegion = 'mb_is_auto_region';
  static const String _keyToken = 'mb_bearer_token';
  static const String _keySearchHistory = 'mb_search_history';
  static const String _keyKeepScreenAwake = 'mb_keep_screen_awake';
  static const String _keyPlayerDoubleTapLayout = 'mb_player_double_tap_layout';
  static const String _keyPlayerSeekDurationX = 'mb_player_seek_duration_x';
  static const String _keyPlayerSeekDurationY = 'mb_player_seek_duration_y';
  static const String _keyPlayerLongPressSpeed = 'mb_player_long_press_speed';
  static const String _keyPlayerGesturesEnabled = 'mb_player_gestures_enabled';
  static const String _keyActiveAnime4kMode = 'mb_active_anime4k_mode';
  static const String _keyActiveAnime4kQuality = 'mb_active_anime4k_quality';
  static const String _keyActiveColorProfileId = 'mb_active_color_profile_id';
  static const String _keyCustomColorProfiles = 'mb_custom_color_profiles';
  static const String _prefixTabSectionOrder = 'mb_tab_section_order_';
  static const String _prefixTabHiddenSections = 'mb_tab_hidden_sections_';
  static const String _keyHomeCustomSections = 'mb_home_custom_sections';
  static const String _keyActiveThemePreset = 'mb_active_theme_preset';
  static const String _keyIsPureOled = 'mb_is_pure_oled';
  static const String _keyAutoExportEnabled = 'mb_auto_export_enabled';
  static const String _keyAutoExportIntervalHours = 'mb_auto_export_interval_hours';
  static const String _keyLastAutoExportTimestamp = 'mb_last_auto_export_timestamp';
  static const String _keyPlayerLongPressDragRate = 'mb_player_long_press_drag_rate';
  static const String _keyIs18PlusDisabled = 'mb_is_18_plus_disabled';
  static const String _keyFeedEdition = 'mb_feed_edition';
  static const String _keyBuzzBoxEnabled = 'mb_buzzbox_enabled';
  static const String _keyDownloadThreads = 'mb_download_threads';
  static const String _keyMaxConcurrentDownloads = 'mb_max_concurrent_downloads';

  static Future<LocalStorageService> getInstance() async {
    if (_instance == null) {
      _instance = LocalStorageService._();
      _prefs = await SharedPreferences.getInstance();
      final presetId = _prefs?.getString(_keyActiveThemePreset) ?? 'emerald_obsidian';
      final isPureOled = _prefs?.getBool(_keyIsPureOled) ?? false;
      AppTheme.setPreset(ThemePreset.getById(presetId), isPureOled: isPureOled);
    }
    return _instance!;
  }

  LocalStorageService._();

  // Authentic MovieBox Regional Profiles & Language Catalogs (Matching official backend profiles)
  static const List<CatalogLocale> supportedCatalogs = [
    CatalogLocale(
      code: 'GLOBAL',
      name: 'Global / USA',
      flag: '🌐',
      description: 'Worldwide, Hollywood & Western Hits',
    ),
    CatalogLocale(
      code: 'BD',
      name: 'বাংলা (Bangladesh)',
      flag: '🇧🇩',
      classify: 'Bengali dub',
      searchKeyword: 'Bengali',
      description: 'বাংলা সিনেমা & ডাবিং',
    ),
    CatalogLocale(
      code: 'IN',
      name: 'Hindi (India)',
      flag: '🇮🇳',
      classify: 'Hindi dub',
      defaultCountry: 'India',
      rankingCategory: '414907768299210008', // Bollywood
      description: 'Bollywood & Regional Hits',
    ),
    CatalogLocale(
      code: 'PH',
      name: 'Filipino (Philippines)',
      flag: '🇵🇭',
      classify: 'Tagalog dub',
      defaultCountry: 'Philippines',
      searchKeyword: 'Vivamax',
      description: 'Pinoy Cinema & Vivamax',
    ),
    CatalogLocale(
      code: 'NG',
      name: 'Nollywood (Nigeria / Africa)',
      flag: '🇳🇬',
      defaultCountry: 'Nigeria',
      description: 'Nollywood Movies, Series & Live Sports',
    ),
  ];

  static CatalogLocale getCatalog(String code) {
    final clean = code.toUpperCase();
    return supportedCatalogs.firstWhere(
      (c) => c.code == clean,
      orElse: () => supportedCatalogs.first,
    );
  }

  // Region / Geo Auto-Detection (Option A) & Manual Override (Option B)
  static String detectDeviceRegion() {
    try {
      final locale = Platform.localeName.toUpperCase();
      if (locale.contains('BD') || locale.contains('BN')) return 'BD';
      if (locale.contains('IN') || locale.contains('HI')) return 'IN';
      if (locale.contains('PH') || locale.contains('FIL') || locale.contains('TL')) return 'PH';
      if (locale.contains('NG') || locale.contains('YO') || locale.contains('IG') || locale.contains('HA')) return 'NG';

      // Timezone offset fallback
      final offset = DateTime.now().timeZoneOffset;
      if (offset.inHours == 6 && offset.inMinutes == 360) return 'BD';
      if (offset.inHours == 5 && offset.inMinutes == 330) return 'IN';
      if (offset.inHours == 8 && offset.inMinutes == 480) return 'PH';
      if (offset.inHours == 1 && offset.inMinutes == 60) return 'NG';
    } catch (_) {}
    return 'GLOBAL';
  }

  bool get isAutoRegion => _prefs?.getBool(_keyIsAutoRegion) ?? true;

  String get detectedRegion => detectDeviceRegion();

  String get activeRegion {
    if (isAutoRegion) {
      return detectedRegion;
    }
    return _prefs?.getString(_keyRegion) ?? detectedRegion;
  }

  CatalogLocale get activeCatalog => getCatalog(activeRegion);

  String get activeRegionCountryName => activeCatalog.name;

  Future<void> setAutoRegion(bool enabled) async {
    await _prefs?.setBool(_keyIsAutoRegion, enabled);
    notifyListeners();
  }

  Future<void> setActiveRegion(String region, {bool isManual = true}) async {
    if (isManual) {
      await _prefs?.setBool(_keyIsAutoRegion, false);
    }
    await _prefs?.setString(_keyRegion, region);
    notifyListeners();
  }

  // Feed Edition (Web Curated vs. Original Mobile App)
  FeedEdition get feedEdition {
    final val = _prefs?.getString(_keyFeedEdition);
    if (val == 'mobile') return FeedEdition.mobile;
    return FeedEdition.web;
  }

  Future<void> setFeedEdition(FeedEdition edition) async {
    await _prefs?.setString(
        _keyFeedEdition, edition == FeedEdition.mobile ? 'mobile' : 'web');
    notifyListeners();
  }

  // Cached Token
  String? get cachedToken => _prefs?.getString(_keyToken);

  Future<void> setCachedToken(String token) async {
    await _prefs?.setString(_keyToken, token);
  }

  // Search History
  List<String> get searchHistory => _prefs?.getStringList(_keySearchHistory) ?? [];

  Future<void> addSearchQuery(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;
    final list = searchHistory;
    list.remove(clean);
    list.insert(0, clean);
    if (list.length > 20) list.removeLast();
    await _prefs?.setStringList(_keySearchHistory, list);
    notifyListeners();
  }

  Future<void> clearSearchHistory() async {
    await _prefs?.remove(_keySearchHistory);
    notifyListeners();
  }

  // Wake Lock Setting
  bool get isKeepScreenAwake => _prefs?.getBool(_keyKeepScreenAwake) ?? true;

  Future<void> setKeepScreenAwake(bool enabled) async {
    await _prefs?.setBool(_keyKeepScreenAwake, enabled);
    notifyListeners();
  }

  // Watch History
  List<LocalRecord> getWatchHistory() {
    final raw = _prefs?.getStringList(_keyHistory) ?? [];
    return raw.map((e) => LocalRecord.fromJson(json.decode(e))).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> removeWatchHistory(String subjectId) async {
    final list = getWatchHistory();
    list.removeWhere((item) => item.subjectId == subjectId);
    final jsonList = list.map((e) => json.encode(e.toJson())).toList();
    await _prefs?.setStringList(_keyHistory, jsonList);
    notifyListeners();
  }

  Future<void> removeMultipleWatchHistory(Set<String> subjectIds) async {
    final list = getWatchHistory();
    list.removeWhere((item) => subjectIds.contains(item.subjectId));
    final jsonList = list.map((e) => json.encode(e.toJson())).toList();
    await _prefs?.setStringList(_keyHistory, jsonList);
    notifyListeners();
  }

  Future<void> clearWatchHistory() async {
    await _prefs?.remove(_keyHistory);
    notifyListeners();
  }

  Future<void> saveWatchProgress({
    required String subjectId,
    required String title,
    String? coverUrl,
    required int subjectType,
    required int positionSeconds,
    required int durationSeconds,
  }) async {
    final list = getWatchHistory();
    list.removeWhere((item) => item.subjectId == subjectId);
    list.insert(
      0,
      LocalRecord(
        subjectId: subjectId,
        title: title,
        coverUrl: coverUrl,
        subjectType: subjectType,
        updatedAt: DateTime.now(),
        positionSeconds: positionSeconds,
        durationSeconds: durationSeconds,
      ),
    );
    if (list.length > 50) list.removeLast();
    final jsonList = list.map((e) => json.encode(e.toJson())).toList();
    await _prefs?.setStringList(_keyHistory, jsonList);
    notifyListeners();
  }

  // Bookmarks (My List)
  List<LocalRecord> getBookmarks() {
    final raw = _prefs?.getStringList(_keyBookmarks) ?? [];
    return raw.map((e) => LocalRecord.fromJson(json.decode(e))).toList();
  }

  bool isBookmarked(String subjectId) {
    final list = getBookmarks();
    return list.any((e) => e.subjectId == subjectId);
  }

  Future<void> toggleBookmark({
    required String subjectId,
    required String title,
    String? coverUrl,
    required int subjectType,
  }) async {
    final list = getBookmarks();
    final index = list.indexWhere((e) => e.subjectId == subjectId);
    if (index >= 0) {
      list.removeAt(index);
    } else {
      list.insert(
        0,
        LocalRecord(
          subjectId: subjectId,
          title: title,
          coverUrl: coverUrl,
          subjectType: subjectType,
          updatedAt: DateTime.now(),
          isBookmarked: true,
        ),
      );
    }
    final jsonList = list.map((e) => json.encode(e.toJson())).toList();
    await _prefs?.setStringList(_keyBookmarks, jsonList);
    notifyListeners();
  }

  Future<void> removeBookmark(String subjectId) async {
    final list = getBookmarks();
    final index = list.indexWhere((e) => e.subjectId == subjectId);
    if (index >= 0) {
      list.removeAt(index);
      final jsonList = list.map((e) => json.encode(e.toJson())).toList();
      await _prefs?.setStringList(_keyBookmarks, jsonList);
      notifyListeners();
    }
  }

  // Custom Categories for My List
  List<String> getMyListCategories() {
    final raw = _prefs?.getStringList(_keyMyListCategories) ?? [];
    return List<String>.from(raw);
  }

  Future<void> addMyListCategory(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    final list = getMyListCategories();
    if (!list.contains(clean)) {
      list.add(clean);
      await _prefs?.setStringList(_keyMyListCategories, list);
      notifyListeners();
    }
  }

  Future<void> renameMyListCategory(String oldName, String newName) async {
    final cleanOld = oldName.trim();
    final cleanNew = newName.trim();
    if (cleanNew.isEmpty || cleanOld == cleanNew) return;
    final list = getMyListCategories();
    final idx = list.indexOf(cleanOld);
    if (idx != -1) {
      list[idx] = cleanNew;
      await _prefs?.setStringList(_keyMyListCategories, list);

      // Update all bookmarks referencing this category
      final bookmarks = getBookmarks();
      bool modified = false;
      for (final b in bookmarks) {
        final cIdx = b.categories.indexOf(cleanOld);
        if (cIdx != -1) {
          b.categories[cIdx] = cleanNew;
          modified = true;
        }
      }
      if (modified) {
        final jsonList = bookmarks.map((e) => json.encode(e.toJson())).toList();
        await _prefs?.setStringList(_keyBookmarks, jsonList);
      }
      notifyListeners();
    }
  }

  Future<void> deleteMyListCategory(String name) async {
    final clean = name.trim();
    final list = getMyListCategories();
    if (list.remove(clean)) {
      await _prefs?.setStringList(_keyMyListCategories, list);

      // Remove from all bookmarks
      final bookmarks = getBookmarks();
      bool modified = false;
      for (final b in bookmarks) {
        if (b.categories.remove(clean)) {
          modified = true;
        }
      }
      if (modified) {
        final jsonList = bookmarks.map((e) => json.encode(e.toJson())).toList();
        await _prefs?.setStringList(_keyBookmarks, jsonList);
      }
      notifyListeners();
    }
  }

  Future<void> toggleItemCategory(String subjectId, String category) async {
    final bookmarks = getBookmarks();
    final index = bookmarks.indexWhere((e) => e.subjectId == subjectId);
    if (index >= 0) {
      final record = bookmarks[index];
      if (record.categories.contains(category)) {
        record.categories.remove(category);
      } else {
        record.categories.add(category);
      }
      final jsonList = bookmarks.map((e) => json.encode(e.toJson())).toList();
      await _prefs?.setStringList(_keyBookmarks, jsonList);
      notifyListeners();
    }
  }

  Future<void> setItemCategories(String subjectId, List<String> categories) async {
    final bookmarks = getBookmarks();
    final index = bookmarks.indexWhere((e) => e.subjectId == subjectId);
    if (index >= 0) {
      bookmarks[index].categories = List<String>.from(categories);
      final jsonList = bookmarks.map((e) => json.encode(e.toJson())).toList();
      await _prefs?.setStringList(_keyBookmarks, jsonList);
      notifyListeners();
    }
  }

  // Favorites (Likes)
  List<LocalRecord> getFavorites() {
    final raw = _prefs?.getStringList(_keyFavorites) ?? [];
    return raw.map((e) => LocalRecord.fromJson(json.decode(e))).toList();
  }

  bool isFavorite(String subjectId) {
    final list = getFavorites();
    return list.any((e) => e.subjectId == subjectId);
  }

  Future<void> toggleFavorite({
    required String subjectId,
    required String title,
    String? coverUrl,
    required int subjectType,
  }) async {
    final list = getFavorites();
    final index = list.indexWhere((e) => e.subjectId == subjectId);
    if (index >= 0) {
      list.removeAt(index);
    } else {
      list.insert(
        0,
        LocalRecord(
          subjectId: subjectId,
          title: title,
          coverUrl: coverUrl,
          subjectType: subjectType,
          updatedAt: DateTime.now(),
          isFavorite: true,
        ),
      );
    }
    final jsonList = list.map((e) => json.encode(e.toJson())).toList();
    await _prefs?.setStringList(_keyFavorites, jsonList);
    notifyListeners();
  }

  // Downloads Registry
  List<LocalRecord> getDownloads() {
    final raw = _prefs?.getStringList(_keyDownloads) ?? [];
    return raw.map((e) => LocalRecord.fromJson(json.decode(e))).toList();
  }

  Future<void> saveDownloadRecord(LocalRecord record) async {
    final list = getDownloads();
    list.removeWhere((e) => e.subjectId == record.subjectId);
    list.insert(0, record);
    final jsonList = list.map((e) => json.encode(e.toJson())).toList();
    await _prefs?.setStringList(_keyDownloads, jsonList);
    notifyListeners();
  }

  Future<void> removeDownloadRecord(String subjectId) async {
    final list = getDownloads();
    list.removeWhere((e) => e.subjectId == subjectId);
    final jsonList = list.map((e) => json.encode(e.toJson())).toList();
    await _prefs?.setStringList(_keyDownloads, jsonList);
    notifyListeners();
  }

  // Player Settings & Gestures
  String get playerDoubleTapLayout =>
      _prefs?.getString(_keyPlayerDoubleTapLayout) ?? '2+1+2';

  Future<void> setPlayerDoubleTapLayout(String layout) async {
    await _prefs?.setString(_keyPlayerDoubleTapLayout, layout);
    notifyListeners();
  }

  int get playerSeekDurationX => _prefs?.getInt(_keyPlayerSeekDurationX) ?? 10;

  Future<void> setPlayerSeekDurationX(int seconds) async {
    await _prefs?.setInt(_keyPlayerSeekDurationX, seconds);
    notifyListeners();
  }

  int get playerSeekDurationY => _prefs?.getInt(_keyPlayerSeekDurationY) ?? 5;

  Future<void> setPlayerSeekDurationY(int seconds) async {
    await _prefs?.setInt(_keyPlayerSeekDurationY, seconds);
    notifyListeners();
  }

  double get playerLongPressSpeed =>
      _prefs?.getDouble(_keyPlayerLongPressSpeed) ?? 2.0;

  Future<void> setPlayerLongPressSpeed(double speed) async {
    await _prefs?.setDouble(_keyPlayerLongPressSpeed, speed);
    notifyListeners();
  }

  bool get playerGesturesEnabled =>
      _prefs?.getBool(_keyPlayerGesturesEnabled) ?? true;

  Future<void> setPlayerGesturesEnabled(bool enabled) async {
    await _prefs?.setBool(_keyPlayerGesturesEnabled, enabled);
    notifyListeners();
  }

  int get playerLongPressDragRate =>
      _prefs?.getInt(_keyPlayerLongPressDragRate) ?? 25;

  Future<void> setPlayerLongPressDragRate(int rate) async {
    await _prefs?.setInt(_keyPlayerLongPressDragRate, rate);
    notifyListeners();
  }

  bool get is18PlusDisabled => _prefs?.getBool(_keyIs18PlusDisabled) ?? true;

  Future<void> setIs18PlusDisabled(bool disabled) async {
    await _prefs?.setBool(_keyIs18PlusDisabled, disabled);
    notifyListeners();
  }

  bool get isBuzzBoxEnabled => _prefs?.getBool(_keyBuzzBoxEnabled) ?? false;

  Future<void> setBuzzBoxEnabled(bool enabled) async {
    await _prefs?.setBool(_keyBuzzBoxEnabled, enabled);
    notifyListeners();
  }

  // Multithreaded & Concurrent Download Settings
  int get downloadThreads => _prefs?.getInt(_keyDownloadThreads) ?? 4;

  Future<void> setDownloadThreads(int threads) async {
    await _prefs?.setInt(_keyDownloadThreads, threads.clamp(1, 8));
    notifyListeners();
  }

  int get maxConcurrentDownloads => _prefs?.getInt(_keyMaxConcurrentDownloads) ?? 2;

  Future<void> setMaxConcurrentDownloads(int max) async {
    await _prefs?.setInt(_keyMaxConcurrentDownloads, max.clamp(1, 5));
    notifyListeners();
  }

  // Anime4K & Color Profiles
  String get activeAnime4kMode =>
      _prefs?.getString(_keyActiveAnime4kMode) ?? 'off';

  Future<void> setActiveAnime4kMode(String mode) async {
    await _prefs?.setString(_keyActiveAnime4kMode, mode);
    notifyListeners();
  }

  String get activeAnime4kQuality =>
      _prefs?.getString(_keyActiveAnime4kQuality) ?? 'fast';

  Future<void> setActiveAnime4kQuality(String quality) async {
    await _prefs?.setString(_keyActiveAnime4kQuality, quality);
    notifyListeners();
  }

  String get activeColorProfileId =>
      _prefs?.getString(_keyActiveColorProfileId) ?? 'natural';

  Future<void> setActiveColorProfileId(String id) async {
    await _prefs?.setString(_keyActiveColorProfileId, id);
    notifyListeners();
  }

  List<Map<String, dynamic>> getCustomColorProfiles() {
    final raw = _prefs?.getString(_keyCustomColorProfiles);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = json.decode(raw);
      if (decoded is List) {
        return decoded
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      return [];
    } catch (_) {}
    return [];
  }

  List<Map<String, dynamic>> get customColorProfiles => getCustomColorProfiles();

  Future<void> saveCustomColorProfiles(
      List<Map<String, dynamic>> profiles) async {
    await _prefs?.setString(_keyCustomColorProfiles, json.encode(profiles));
    notifyListeners();
  }

  // Tab Section Orders & Visibility
  List<String> getTabSectionOrder(int tabIndex) {
    return _prefs?.getStringList('$_prefixTabSectionOrder$tabIndex') ?? [];
  }

  Future<void> setTabSectionOrder(int tabIndex, List<String> order) async {
    await _prefs?.setStringList('$_prefixTabSectionOrder$tabIndex', order);
    notifyListeners();
  }

  Set<String> getTabHiddenSections(int tabIndex) {
    final list = _prefs?.getStringList('$_prefixTabHiddenSections$tabIndex') ?? [];
    return list.toSet();
  }

  Future<void> setTabHiddenSections(int tabIndex, Set<String> hidden) async {
    await _prefs?.setStringList('$_prefixTabHiddenSections$tabIndex', hidden.toList());
    notifyListeners();
  }

  Future<void> resetTabSectionConfig(int tabIndex) async {
    await _prefs?.remove('$_prefixTabSectionOrder$tabIndex');
    await _prefs?.remove('$_prefixTabHiddenSections$tabIndex');
    notifyListeners();
  }

  // Home Custom Sections (Creator & Library)
  List<CustomSectionConfig> getHomeCustomSections() {
    final raw = _prefs?.getStringList(_keyHomeCustomSections) ?? [];
    return raw.map((str) {
      try {
        return CustomSectionConfig.fromJson(json.decode(str) as Map<String, dynamic>);
      } catch (_) {
        return null;
      }
    }).whereType<CustomSectionConfig>().toList();
  }

  Future<void> saveHomeCustomSections(List<CustomSectionConfig> sections) async {
    final raw = sections.map((s) => json.encode(s.toJson())).toList();
    await _prefs?.setStringList(_keyHomeCustomSections, raw);
    notifyListeners();
  }

  Future<void> addHomeCustomSection(CustomSectionConfig section) async {
    final list = getHomeCustomSections();
    list.removeWhere((s) => s.id == section.id);
    list.add(section);
    await saveHomeCustomSections(list);
  }

  Future<void> removeHomeCustomSection(String sectionId) async {
    final list = getHomeCustomSections();
    list.removeWhere((s) => s.id == sectionId);
    await saveHomeCustomSections(list);
  }

  // Theme Presets & Pure OLED
  String get activeThemePresetId =>
      _prefs?.getString(_keyActiveThemePreset) ?? 'emerald_obsidian';

  ThemePreset get activeThemePreset => ThemePreset.getById(activeThemePresetId);

  bool get isPureOled => _prefs?.getBool(_keyIsPureOled) ?? false;

  Future<void> setThemePreset(String presetId) async {
    await _prefs?.setString(_keyActiveThemePreset, presetId);
    AppTheme.setPreset(ThemePreset.getById(presetId), isPureOled: isPureOled);
    notifyListeners();
  }

  Future<void> setPureOled(bool enabled) async {
    await _prefs?.setBool(_keyIsPureOled, enabled);
    AppTheme.setPreset(activeThemePreset, isPureOled: enabled);
    notifyListeners();
  }

  // ==============================================================================
  // BACKUP, RESTORE & AUTO-EXPORT ENGINE
  // ==============================================================================

  static const List<int> autoExportIntervalMilestones = [6, 12, 24, 48, 72, 120, 168];

  static String formatIntervalLabel(int hours) {
    if (hours < 24) {
      return '$hours Hours';
    }
    final days = hours ~/ 24;
    return days == 1 ? '1 Day (24h)' : '$days Days';
  }

  bool get isAutoExportEnabled => _prefs?.getBool(_keyAutoExportEnabled) ?? false;

  int get autoExportIntervalHours => _prefs?.getInt(_keyAutoExportIntervalHours) ?? 24;

  int get lastAutoExportTimestamp => _prefs?.getInt(_keyLastAutoExportTimestamp) ?? 0;

  DateTime? get lastAutoExportDate =>
      lastAutoExportTimestamp > 0 ? DateTime.fromMillisecondsSinceEpoch(lastAutoExportTimestamp) : null;

  Future<void> setAutoExportEnabled(bool enabled) async {
    await _prefs?.setBool(_keyAutoExportEnabled, enabled);
    notifyListeners();
    if (enabled && lastAutoExportTimestamp == 0) {
      // Trigger immediate baseline backup
      try {
        await exportAllData(isAuto: true);
      } catch (e) {
        debugPrint('[RaenBox Auto-Backup] Initial export error: $e');
      }
    }
  }

  Future<void> setAutoExportIntervalHours(int hours) async {
    await _prefs?.setInt(_keyAutoExportIntervalHours, hours);
    notifyListeners();
    // Check if overdue under the new interval
    checkAndTriggerAutoExport();
  }

  /// Resolves the optimal directory for backups (Downloads on Android, fallback to Documents)
  Future<Directory> getBackupDirectory() async {
    if (Platform.isAndroid) {
      try {
        final downloadDir = Directory('/storage/emulated/0/Download/RaenBox/Backups');
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }
        return downloadDir;
      } catch (_) {}

      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final extBackup = Directory('${extDir.path}/Backups');
          if (!await extBackup.exists()) {
            await extBackup.create(recursive: true);
          }
          return extBackup;
        }
      } catch (_) {}
    }

    final docDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${docDir.path}/RaenBox/Backups');
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

  /// Keeps a rolling retention of the 5 newest backup files
  Future<void> _pruneRollingBackups(Directory dir) async {
    try {
      if (!await dir.exists()) return;
      final entities = await dir.list().toList();
      final jsonFiles = entities
          .whereType<File>()
          .where((f) => f.path.endsWith('.json') && f.path.contains('raenbox_'))
          .toList();

      jsonFiles.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      if (jsonFiles.length > 5) {
        for (int i = 5; i < jsonFiles.length; i++) {
          try {
            await jsonFiles[i].delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[RaenBox Backup] Pruning error: $e');
    }
  }

  /// Exports all application state to a structured JSON backup file
  Future<BackupExportResult> exportAllData({bool isAuto = false}) async {
    final bookmarks = getBookmarks();
    final history = getWatchHistory();
    final categories = getMyListCategories();
    final search = searchHistory;
    final customSections = getHomeCustomSections();
    final colorProfiles = getCustomColorProfiles();

    // Export Tab section ordering and hidden configurations for all 7 tabs
    final Map<String, dynamic> tabSectionOrders = {};
    final Map<String, dynamic> tabHiddenSections = {};
    for (int i = 0; i < 7; i++) {
      tabSectionOrders[i.toString()] = getTabSectionOrder(i);
      tabHiddenSections[i.toString()] = getTabHiddenSections(i).toList();
    }

    final Map<String, dynamic> settings = {
      'activeThemePreset': activeThemePresetId,
      'isPureOled': isPureOled,
      'keepScreenAwake': isKeepScreenAwake,
      'activeRegion': activeRegion,
      'isAutoRegion': isAutoRegion,
      'feedEdition': feedEdition.name,
      'playerDoubleTapLayout': playerDoubleTapLayout,
      'playerSeekDurationX': playerSeekDurationX,
      'playerSeekDurationY': playerSeekDurationY,
      'playerLongPressSpeed': playerLongPressSpeed,
      'playerLongPressDragRate': playerLongPressDragRate,
      'is18PlusDisabled': is18PlusDisabled,
      'isBuzzBoxEnabled': isBuzzBoxEnabled,
      'downloadThreads': downloadThreads,
      'maxConcurrentDownloads': maxConcurrentDownloads,
      'playerGesturesEnabled': playerGesturesEnabled,
      'activeAnime4kMode': activeAnime4kMode,
      'activeAnime4kQuality': activeAnime4kQuality,
      'activeColorProfileId': activeColorProfileId,
      'customColorProfiles': colorProfiles,
    };

    final now = DateTime.now();
    final payload = {
      'version': 1,
      'appName': 'RaenBox',
      'appId': 'com.raen.raenbox',
      'exportedAt': now.toIso8601String(),
      'isAutoBackup': isAuto,
      'data': {
        'bookmarks': bookmarks.map((b) => b.toJson()).toList(),
        'watchHistory': history.map((h) => h.toJson()).toList(),
        'myListCategories': categories,
        'searchHistory': search,
        'homeCustomSections': customSections.map((s) => s.toJson()).toList(),
        'tabSectionOrders': tabSectionOrders,
        'tabHiddenSections': tabHiddenSections,
        'settings': settings,
      },
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(payload);
    final backupDir = await getBackupDirectory();

    String pad(int n) => n.toString().padLeft(2, '0');
    final ts = '${now.year}${pad(now.month)}${pad(now.day)}_${pad(now.hour)}${pad(now.minute)}${pad(now.second)}';
    final prefix = isAuto ? 'raenbox_auto_backup_' : 'raenbox_backup_';
    final fileName = '$prefix$ts.json';
    final file = File('${backupDir.path}/$fileName');
    await file.writeAsString(jsonString);

    await _pruneRollingBackups(backupDir);

    await _prefs?.setInt(_keyLastAutoExportTimestamp, now.millisecondsSinceEpoch);

    return BackupExportResult(
      filePath: file.path,
      fileName: fileName,
      fileSizeBytes: await file.length(),
      bookmarkCount: bookmarks.length,
      historyCount: history.length,
      customSectionCount: customSections.length,
      colorProfileCount: colorProfiles.length,
      isAuto: isAuto,
    );
  }

  /// Imports and applies backup data from a file
  Future<void> importBackupFromFile(File file, {required bool mergeMode}) async {
    final content = await file.readAsString();
    await importBackupFromString(content, mergeMode: mergeMode);
  }

  /// Imports and applies backup data from a JSON string
  Future<void> importBackupFromString(String jsonString, {required bool mergeMode}) async {
    final dynamic decoded = json.decode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid backup file: root must be a JSON object');
    }
    await importBackupData(decoded, mergeMode: mergeMode);
  }

  /// Imports and applies backup data from a parsed map
  Future<void> importBackupData(Map<String, dynamic> jsonMap, {required bool mergeMode}) async {
    final data = jsonMap['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw const FormatException('Invalid backup file: missing "data" block');
    }

    if (mergeMode) {
      // --- MERGE & COMBINE MODE ---
      // 1. Bookmarks: Union by subjectId, merge categories
      if (data['bookmarks'] is List) {
        final backupBookmarks = (data['bookmarks'] as List)
            .map((e) => LocalRecord.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        final currentBookmarks = getBookmarks();
        final Map<String, LocalRecord> merged = {for (var b in currentBookmarks) b.subjectId: b};

        for (var b in backupBookmarks) {
          if (!merged.containsKey(b.subjectId)) {
            merged[b.subjectId] = b;
          } else {
            final existing = merged[b.subjectId]!;
            final combinedCats = {...existing.categories, ...b.categories}.toList();
            merged[b.subjectId] = existing.copyWith(categories: combinedCats);
          }
        }
        final jsonList = merged.values.map((r) => json.encode(r.toJson())).toList();
        await _prefs?.setStringList(_keyBookmarks, jsonList);
      }

      // 2. My List Categories: Union
      if (data['myListCategories'] is List) {
        final currentCats = getMyListCategories();
        final backupCats = (data['myListCategories'] as List).map((e) => e.toString()).toList();
        final mergedCats = {...currentCats, ...backupCats}.toList();
        await _prefs?.setStringList(_keyMyListCategories, mergedCats);
      }

      // 3. Watch History: Keep latest timestamp / highest progress
      if (data['watchHistory'] is List) {
        final backupHistory = (data['watchHistory'] as List)
            .map((e) => LocalRecord.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        final currentHistory = getWatchHistory();
        final Map<String, LocalRecord> mergedHistory = {for (var h in currentHistory) h.subjectId: h};

        for (var h in backupHistory) {
          if (!mergedHistory.containsKey(h.subjectId)) {
            mergedHistory[h.subjectId] = h;
          } else {
            final existing = mergedHistory[h.subjectId]!;
            if (h.updatedAt.isAfter(existing.updatedAt) || h.positionSeconds > existing.positionSeconds) {
              mergedHistory[h.subjectId] = h;
            }
          }
        }
        final sorted = mergedHistory.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        final jsonList = sorted.map((r) => json.encode(r.toJson())).toList();
        await _prefs?.setStringList(_keyHistory, jsonList);
      }

      // 4. Custom Sections: Append non-duplicates
      if (data['homeCustomSections'] is List) {
        final currentSections = getHomeCustomSections();
        final existingIds = currentSections.map((s) => s.id).toSet();
        final existingTitles = currentSections.map((s) => s.title.toLowerCase().trim()).toSet();
        final backupSections = (data['homeCustomSections'] as List)
            .map((e) => CustomSectionConfig.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();

        for (var sec in backupSections) {
          if (!existingIds.contains(sec.id) && !existingTitles.contains(sec.title.toLowerCase().trim())) {
            currentSections.add(sec);
          }
        }
        final jsonList = currentSections.map((s) => json.encode(s.toJson())).toList();
        await _prefs?.setStringList(_keyHomeCustomSections, jsonList);
      }

      // 5. Custom Color Profiles: Append non-duplicates
      if (data['settings'] is Map && (data['settings']['customColorProfiles'] is List)) {
        final currentProfiles = getCustomColorProfiles();
        final existingNames = currentProfiles.map((p) => p['name']?.toString().toLowerCase().trim()).toSet();
        final backupProfiles = (data['settings']['customColorProfiles'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        for (var cp in backupProfiles) {
          final name = cp['name']?.toString().toLowerCase().trim() ?? '';
          if (!existingNames.contains(name)) {
            currentProfiles.add(cp);
          }
        }
        await _prefs?.setString(_keyCustomColorProfiles, json.encode(currentProfiles));
      }

      // 6. Settings restore
      if (data['settings'] is Map) {
        await _applySettingsMap(Map<String, dynamic>.from(data['settings'] as Map));
      }
    } else {
      // --- CLEAN RESTORE MODE ---
      // 1. Bookmarks
      if (data['bookmarks'] is List) {
        final jsonList = (data['bookmarks'] as List).map((e) => json.encode(e)).toList();
        await _prefs?.setStringList(_keyBookmarks, jsonList);
      } else {
        await _prefs?.remove(_keyBookmarks);
      }

      // 2. Watch History
      if (data['watchHistory'] is List) {
        final jsonList = (data['watchHistory'] as List).map((e) => json.encode(e)).toList();
        await _prefs?.setStringList(_keyHistory, jsonList);
      } else {
        await _prefs?.remove(_keyHistory);
      }

      // 3. My List Categories
      if (data['myListCategories'] is List) {
        final cats = (data['myListCategories'] as List).map((e) => e.toString()).toList();
        await _prefs?.setStringList(_keyMyListCategories, cats);
      } else {
        await _prefs?.remove(_keyMyListCategories);
      }

      // 4. Search History
      if (data['searchHistory'] is List) {
        final sh = (data['searchHistory'] as List).map((e) => e.toString()).toList();
        await _prefs?.setStringList(_keySearchHistory, sh);
      }

      // 5. Home Custom Sections
      if (data['homeCustomSections'] is List) {
        final jsonList = (data['homeCustomSections'] as List).map((e) => json.encode(e)).toList();
        await _prefs?.setStringList(_keyHomeCustomSections, jsonList);
      } else {
        await _prefs?.remove(_keyHomeCustomSections);
      }

      // 6. Tab Section Orders & Hidden
      if (data['tabSectionOrders'] is Map) {
        for (var entry in (data['tabSectionOrders'] as Map).entries) {
          final tabIdx = int.tryParse(entry.key.toString());
          if (tabIdx != null && entry.value is List) {
            final list = (entry.value as List).map((e) => e.toString()).toList();
            await _prefs?.setStringList('$_prefixTabSectionOrder$tabIdx', list);
          }
        }
      }
      if (data['tabHiddenSections'] is Map) {
        for (var entry in (data['tabHiddenSections'] as Map).entries) {
          final tabIdx = int.tryParse(entry.key.toString());
          if (tabIdx != null && entry.value is List) {
            final list = (entry.value as List).map((e) => e.toString()).toList();
            await _prefs?.setStringList('$_prefixTabHiddenSections$tabIdx', list);
          }
        }
      }

      // 7. Settings
      if (data['settings'] is Map) {
        await _applySettingsMap(Map<String, dynamic>.from(data['settings'] as Map));
      }
    }

    notifyListeners();
  }

  Future<void> _applySettingsMap(Map<String, dynamic> s) async {
    if (s['activeThemePreset'] is String) {
      await _prefs?.setString(_keyActiveThemePreset, s['activeThemePreset']);
    }
    if (s['isPureOled'] is bool) {
      await _prefs?.setBool(_keyIsPureOled, s['isPureOled']);
    }
    final presetId = _prefs?.getString(_keyActiveThemePreset) ?? 'emerald_obsidian';
    final isPureOledVal = _prefs?.getBool(_keyIsPureOled) ?? false;
    AppTheme.setPreset(ThemePreset.getById(presetId), isPureOled: isPureOledVal);

    if (s['keepScreenAwake'] is bool) {
      await _prefs?.setBool(_keyKeepScreenAwake, s['keepScreenAwake']);
    }
    if (s['activeRegion'] is String) {
      await _prefs?.setString(_keyRegion, s['activeRegion']);
    }
    if (s['isAutoRegion'] is bool) {
      await _prefs?.setBool(_keyIsAutoRegion, s['isAutoRegion']);
    }
    if (s['feedEdition'] is String) {
      await _prefs?.setString(_keyFeedEdition, s['feedEdition']);
    }
    if (s['playerDoubleTapLayout'] is String) {
      await _prefs?.setString(_keyPlayerDoubleTapLayout, s['playerDoubleTapLayout']);
    }
    if (s['playerSeekDurationX'] is int) {
      await _prefs?.setInt(_keyPlayerSeekDurationX, s['playerSeekDurationX']);
    }
    if (s['playerSeekDurationY'] is int) {
      await _prefs?.setInt(_keyPlayerSeekDurationY, s['playerSeekDurationY']);
    }
    if (s['playerLongPressSpeed'] is num) {
      await _prefs?.setDouble(_keyPlayerLongPressSpeed, (s['playerLongPressSpeed'] as num).toDouble());
    }
    if (s['playerLongPressDragRate'] is int) {
      await _prefs?.setInt(_keyPlayerLongPressDragRate, s['playerLongPressDragRate']);
    }
    if (s['is18PlusDisabled'] is bool) {
      await _prefs?.setBool(_keyIs18PlusDisabled, s['is18PlusDisabled']);
    }
    if (s['isBuzzBoxEnabled'] is bool) {
      await _prefs?.setBool(_keyBuzzBoxEnabled, s['isBuzzBoxEnabled']);
    }
    if (s['downloadThreads'] is int) {
      await _prefs?.setInt(_keyDownloadThreads, s['downloadThreads']);
    }
    if (s['maxConcurrentDownloads'] is int) {
      await _prefs?.setInt(_keyMaxConcurrentDownloads, s['maxConcurrentDownloads']);
    }
    if (s['playerGesturesEnabled'] is bool) {
      await _prefs?.setBool(_keyPlayerGesturesEnabled, s['playerGesturesEnabled']);
    }
    if (s['activeAnime4kMode'] is String) {
      await _prefs?.setString(_keyActiveAnime4kMode, s['activeAnime4kMode']);
    }
    if (s['activeAnime4kQuality'] is String) {
      await _prefs?.setString(_keyActiveAnime4kQuality, s['activeAnime4kQuality']);
    }
    if (s['activeColorProfileId'] is String) {
      await _prefs?.setString(_keyActiveColorProfileId, s['activeColorProfileId']);
    }
    if (s['customColorProfiles'] is List) {
      await _prefs?.setString(_keyCustomColorProfiles, json.encode(s['customColorProfiles']));
    }
  }

  /// Scans and returns all available local backups
  Future<List<BackupFileInfo>> getAvailableBackups() async {
    final List<BackupFileInfo> result = [];
    try {
      final backupDir = await getBackupDirectory();
      if (!await backupDir.exists()) return result;

      final entities = await backupDir.list().toList();
      final jsonFiles = entities
          .whereType<File>()
          .where((f) => f.path.endsWith('.json') && f.path.contains('raenbox_'))
          .toList();

      jsonFiles.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      for (var file in jsonFiles) {
        final fileName = file.path.split(Platform.pathSeparator).last;
        final stat = await file.stat();
        final isAuto = fileName.contains('auto');

        int? bookmarks;
        int? history;
        int? customSections;
        String? version;

        try {
          final content = await file.readAsString();
          final map = json.decode(content) as Map<String, dynamic>;
          version = map['version']?.toString();
          final data = map['data'] as Map<String, dynamic>?;
          if (data != null) {
            bookmarks = (data['bookmarks'] as List?)?.length;
            history = (data['watchHistory'] as List?)?.length;
            customSections = (data['homeCustomSections'] as List?)?.length;
          }
        } catch (_) {}

        result.add(BackupFileInfo(
          path: file.path,
          fileName: fileName,
          modifiedDate: stat.modified,
          fileSizeBytes: stat.size,
          isAuto: isAuto,
          bookmarkCount: bookmarks,
          historyCount: history,
          customSectionCount: customSections,
          appVersion: version,
        ));
      }
    } catch (e) {
      debugPrint('[RaenBox Backup] Error listing backups: $e');
    }
    return result;
  }

  /// Deletes a backup file by absolute path
  Future<bool> deleteBackup(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('[RaenBox Backup] Error deleting backup: $e');
    }
    return false;
  }

  /// Checks if auto-export interval has elapsed and runs silent backup if overdue
  Future<void> checkAndTriggerAutoExport() async {
    if (!isAutoExportEnabled) return;
    final lastExport = lastAutoExportTimestamp;
    final intervalMs = autoExportIntervalHours * 3600 * 1000;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now - lastExport >= intervalMs) {
      try {
        debugPrint('[RaenBox Auto-Backup] Interval reached (${autoExportIntervalHours}h). Running auto-export...');
        await exportAllData(isAuto: true);
        debugPrint('[RaenBox Auto-Backup] Completed successfully.');
      } catch (e) {
        debugPrint('[RaenBox Auto-Backup] Failed: $e');
      }
    }
  }
}

class BackupFileInfo {
  final String path;
  final String fileName;
  final DateTime modifiedDate;
  final int fileSizeBytes;
  final bool isAuto;
  final int? bookmarkCount;
  final int? historyCount;
  final int? customSectionCount;
  final String? appVersion;

  const BackupFileInfo({
    required this.path,
    required this.fileName,
    required this.modifiedDate,
    required this.fileSizeBytes,
    required this.isAuto,
    this.bookmarkCount,
    this.historyCount,
    this.customSectionCount,
    this.appVersion,
  });

  String get formattedSize {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

class BackupExportResult {
  final String filePath;
  final String fileName;
  final int fileSizeBytes;
  final int bookmarkCount;
  final int historyCount;
  final int customSectionCount;
  final int colorProfileCount;
  final bool isAuto;

  const BackupExportResult({
    required this.filePath,
    required this.fileName,
    required this.fileSizeBytes,
    required this.bookmarkCount,
    required this.historyCount,
    required this.customSectionCount,
    required this.colorProfileCount,
    required this.isAuto,
  });

  String get formattedSize {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

class CustomSectionConfig {
  final String id;
  final String title;
  final String type; // 'all', 'movie', 'tv', 'anime'
  final String? keyword;
  final String? genre;
  final String? country;
  final String? year;
  final String sort; // 'ForYou', 'Popular', 'Latest', 'HighRating'
  final bool isCustom;
  final String? librarySource; // preset ID or category key if added from library

  const CustomSectionConfig({
    required this.id,
    required this.title,
    this.type = 'all',
    this.keyword,
    this.genre,
    this.country,
    this.year,
    this.sort = 'ForYou',
    this.isCustom = true,
    this.librarySource,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'type': type,
    if (keyword != null) 'keyword': keyword,
    if (genre != null) 'genre': genre,
    if (country != null) 'country': country,
    if (year != null) 'year': year,
    'sort': sort,
    'isCustom': isCustom,
    if (librarySource != null) 'librarySource': librarySource,
  };

  factory CustomSectionConfig.fromJson(Map<String, dynamic> json) {
    return CustomSectionConfig(
      id: json['id']?.toString() ?? 'section_${DateTime.now().millisecondsSinceEpoch}',
      title: json['title']?.toString() ?? 'Custom Section',
      type: json['type']?.toString() ?? 'all',
      keyword: json['keyword']?.toString(),
      genre: json['genre']?.toString(),
      country: json['country']?.toString(),
      year: json['year']?.toString(),
      sort: json['sort']?.toString() ?? 'ForYou',
      isCustom: json['isCustom'] != false,
      librarySource: json['librarySource']?.toString(),
    );
  }
}


class CatalogLocale {
  final String code;
  final String name;
  final String flag;
  final String? classify;
  final String? defaultCountry;
  final String? searchKeyword;
  final String? rankingCategory;
  final String description;

  const CatalogLocale({
    required this.code,
    required this.name,
    required this.flag,
    this.classify,
    this.defaultCountry,
    this.searchKeyword,
    this.rankingCategory,
    required this.description,
  });
}

