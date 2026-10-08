import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'core/proxy/local_stream_proxy.dart';
import 'core/services/miniplayer_service.dart';
import 'core/services/pip_service.dart';
import 'core/theme/app_theme.dart';
import 'data/services/download_service.dart';
import 'data/services/local_storage_service.dart';
import 'data/services/moviebox_api_service.dart';
import 'features/downloads/downloads_screen.dart';
import 'features/home/home_screen.dart';
import 'features/me/me_screen.dart';
import 'features/player/miniplayer_widget.dart';
import 'features/search/search_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Restrict image cache size to prevent unconstrained GPU texture memory bloat
  PaintingBinding.instance.imageCache.maximumSize = 60;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 32 * 1024 * 1024; // 32 MB ceiling

  final storage = await LocalStorageService.getInstance();
  await LocalStreamProxy.instance.start();

  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.bgSecondary,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final apiService = MovieBoxApiService(storage);
  final downloadService = DownloadService.getInstance(storage);

  runApp(RaenBoxApp(
    storage: storage,
    apiService: apiService,
    downloadService: downloadService,
  ));
}

class RaenBoxApp extends StatelessWidget {
  final LocalStorageService storage;
  final MovieBoxApiService apiService;
  final DownloadService downloadService;

  const RaenBoxApp({
    super.key,
    required this.storage,
    required this.apiService,
    required this.downloadService,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: storage,
      child: MainNavigationScaffold(
        storage: storage,
        apiService: apiService,
        downloadService: downloadService,
      ),
      builder: (context, child) {
        return MaterialApp(
          navigatorKey: MiniplayerService.navigatorKey,
          title: 'RaenBox',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.buildTheme(storage.activeThemePreset, isPureOled: storage.isPureOled),
          builder: (context, navigatorChild) {
            return Stack(
              children: [
                ?navigatorChild,
                const MiniplayerWidget(),
              ],
            );
          },
          home: child,
        );
      },
    );
  }
}

class MainNavigationScaffold extends StatefulWidget {
  final LocalStorageService storage;
  final MovieBoxApiService apiService;
  final DownloadService downloadService;

  const MainNavigationScaffold({
    super.key,
    required this.storage,
    required this.apiService,
    required this.downloadService,
  });

  @override
  State<MainNavigationScaffold> createState() => _MainNavigationScaffoldState();
}

class _MainNavigationScaffoldState extends State<MainNavigationScaffold> with WidgetsBindingObserver {
  int _currentIndex = 0; // 0: Home, 1: Search, 2: Downloads, 3: Me
  int _homeCategoryIndex = 0; // 0: Trending, 1: Movie, 2: TV, 3: MidNight, 4: Anime, 5: ShortTV
  bool _isBottomBarVisible = true;
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();
  final ScrollController _categoryTabsScrollController = ScrollController();

  DateTime? _lastBackPressTime;
  bool _showExitToast = false;
  Timer? _exitToastTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PipService.init();
    MiniplayerService.instance.init(widget.storage);
    if (widget.storage.isKeepScreenAwake) {
      WakelockPlus.enable();
    }
    widget.storage.addListener(_onStorageChanged);
    widget.storage.checkAndTriggerAutoExport();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.storage.checkAndTriggerAutoExport();
    }
  }

  void _onStorageChanged() {
    if (widget.storage.isKeepScreenAwake) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
    if (mounted) setState(() {});
  }

  void _scrollCategoryTabIntoView(int index) {
    if (_categoryTabsScrollController.hasClients) {
      final offset = (index * 75.0).clamp(0.0, _categoryTabsScrollController.position.maxScrollExtent);
      _categoryTabsScrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void _triggerExitToast() {
    _exitToastTimer?.cancel();
    setState(() => _showExitToast = true);
    _exitToastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showExitToast = false);
    });
  }

  void _handleBackPress() {
    // 1. If not on Home tab (e.g. Search, Downloads, Me), jump to Trending root in Home
    if (_currentIndex != 0) {
      setState(() {
        _currentIndex = 0;
        _isBottomBarVisible = true;
      });
      _homeKey.currentState?.resetToTrendingRoot();
      return;
    }

    // 2. If on Home tab, check if HomeScreen handles it (exiting section to rails or category to Trending)
    final handledByHome = _homeKey.currentState?.handleBackPressed() ?? false;
    if (handledByHome) {
      if (!_isBottomBarVisible) {
        setState(() => _isBottomBarVisible = true);
      }
      return;
    }

    // 3. User is at Home -> Trending root. Check double back exit!
    final now = DateTime.now();
    if (_lastBackPressTime == null || now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      _lastBackPressTime = now;
      _triggerExitToast();
    } else {
      _exitToastTimer?.cancel();
      SystemNavigator.pop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _exitToastTimer?.cancel();
    widget.storage.removeListener(_onStorageChanged);
    _categoryTabsScrollController.dispose();
    super.dispose();
  }

  String _getRegionFlag(String region) => widget.storage.activeCatalog.flag;

  void _showGeoRegionModal(BuildContext ctx) {
    final detectedCatalog = LocalStorageService.getCatalog(widget.storage.detectedRegion);

    showModalBottomSheet(
      context: ctx,
      backgroundColor: AppTheme.bgSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (bCtx) {
        final curIsAuto = widget.storage.isAutoRegion;
        final curActive = widget.storage.activeRegion;

        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Content Catalog & Language',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                          onPressed: () => Navigator.of(bCtx).pop(),
                        ),
                      ],
                    ),
                  ),
                  Divider(color: AppTheme.borderSubtle),

                  // Quick Toggle: Location Based vs Global Version
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              widget.storage.setAutoRegion(true);
                              Navigator.of(bCtx).pop();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: curIsAuto ? AppTheme.accentGreen.withValues(alpha: 0.2) : AppTheme.bgCard,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: curIsAuto ? AppTheme.accentGreen : AppTheme.borderSubtle,
                                  width: curIsAuto ? 1.5 : 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.my_location, color: curIsAuto ? AppTheme.accentGreen : Colors.white70),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Location Based',
                                    style: TextStyle(
                                      color: curIsAuto ? AppTheme.accentGreen : Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    'Auto: ${detectedCatalog.flag} ${detectedCatalog.name}',
                                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              widget.storage.setActiveRegion('GLOBAL', isManual: true);
                              Navigator.of(bCtx).pop();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: (!curIsAuto && curActive == 'GLOBAL')
                                    ? AppTheme.accentGreen.withValues(alpha: 0.2)
                                    : AppTheme.bgCard,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: (!curIsAuto && curActive == 'GLOBAL')
                                      ? AppTheme.accentGreen
                                      : AppTheme.borderSubtle,
                                  width: (!curIsAuto && curActive == 'GLOBAL') ? 1.5 : 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.public,
                                    color: (!curIsAuto && curActive == 'GLOBAL')
                                        ? AppTheme.accentGreen
                                        : Colors.white70,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Global Version',
                                    style: TextStyle(
                                      color: (!curIsAuto && curActive == 'GLOBAL')
                                          ? AppTheme.accentGreen
                                          : Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const Text('Worldwide', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: Text(
                      'Select Language / Content Catalog:',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),

                  ...LocalStorageService.supportedCatalogs.map((catalog) {
                    final isSel = !curIsAuto && curActive == catalog.code;
                    return ListTile(
                      dense: true,
                      leading: Text(catalog.flag, style: const TextStyle(fontSize: 20)),
                      title: Text(
                        catalog.name,
                        style: TextStyle(
                          color: isSel ? AppTheme.accentGreen : Colors.white,
                          fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        catalog.description,
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                      ),
                      trailing: isSel ? Icon(Icons.check_circle, color: AppTheme.accentGreen, size: 18) : null,
                      onTap: () {
                        widget.storage.setActiveRegion(catalog.code, isManual: true);
                        Navigator.of(bCtx).pop();
                      },
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: PipService.inPipNotifier,
      builder: (context, inPip, child) {
        if (inPip &&
            MiniplayerService.instance.isActive &&
            MiniplayerService.instance.videoController != null) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: Video(
                controller: MiniplayerService.instance.videoController!,
                controls: NoVideoControls,
              ),
            ),
          );
        }

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _handleBackPress();
          },
          child: Scaffold(
            backgroundColor: AppTheme.bgPrimary,
            body: Stack(
              children: [
                // 1. All screen views inside NotificationListener to catch scroll directions
                NotificationListener<UserScrollNotification>(
                  onNotification: (notification) {
                    if (MiniplayerService.instance.isActive) {
                      if (!_isBottomBarVisible) {
                        setState(() => _isBottomBarVisible = true);
                      }
                      return false;
                    }
                    if (notification.direction == ScrollDirection.reverse) {
                      // Scrolling down -> auto-hide bottom dock
                      if (_isBottomBarVisible) {
                        setState(() => _isBottomBarVisible = false);
                      }
                    } else if (notification.direction == ScrollDirection.forward) {
                      // Scrolling up -> auto-show bottom dock
                      if (!_isBottomBarVisible) {
                        setState(() => _isBottomBarVisible = true);
                      }
                    }
                    return false;
                  },
                  child: IndexedStack(
                    index: _currentIndex,
                    children: [
                  HomeScreen(
                    key: _homeKey,
                    apiService: widget.apiService,
                    storage: widget.storage,
                    onCategoryChanged: (idx) {
                      if (_homeCategoryIndex != idx) {
                        setState(() => _homeCategoryIndex = idx);
                        _scrollCategoryTabIntoView(idx);
                      }
                    },
                  ),
                  SearchScreen(apiService: widget.apiService),
                  DownloadsScreen(
                    storage: widget.storage,
                    downloadService: widget.downloadService,
                    apiService: widget.apiService,
                  ),
                  MeScreen(
                    storage: widget.storage,
                    apiService: widget.apiService,
                  ),
                ],
              ),
            ),

            // 2. Docked Bottom Bar + Category Tabs Bar above it with Auto-Hide Animation
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomDock(),
            ),

            // 3. Double-Back Exit Floating Toast Overlay
            if (_showExitToast)
              Positioned(
                bottom: 95,
                left: 0,
                right: 0,
                child: Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 180),
                    builder: (context, val, child) {
                      return Opacity(
                        opacity: val,
                        child: Transform.scale(
                          scale: 0.9 + 0.1 * val,
                          child: child,
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.bgSecondary.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppTheme.accentGreen.withValues(alpha: 0.5),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.exit_to_app, color: AppTheme.accentGreen, size: 16),
                          const SizedBox(width: 8),
                          const Text(
                            'Press back again to exit',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
      },
    );
  }

  Widget _buildBottomDock() {
    final isAuto = widget.storage.isAutoRegion;
    final region = widget.storage.activeRegion;
    final flag = _getRegionFlag(region);
    final label = region == 'GLOBAL' ? '🌐 Global' : '$flag $region';

    return AnimatedSlide(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      offset: _isBottomBarVisible ? Offset.zero : const Offset(0, 1),
      child: IgnorePointer(
        ignoring: !_isBottomBarVisible,
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.bgSecondary.withValues(alpha: 0.98),
            border: Border(
              top: BorderSide(color: AppTheme.borderSubtle, width: 0.8),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.65),
                blurRadius: 14,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Category Tabs Bar (Directly above bottom bar, on Home tab)
                if (_currentIndex == 0) _buildCategoryTabsBar(),

                // 2. Thin Bottom Bar: Icons only + Geo Toggle Button
                SizedBox(
                  height: 48,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildNavItem(icon: Icons.home_rounded, index: 0),
                      _buildNavItem(icon: Icons.search_rounded, index: 1),

                      // Center: Geo Toggle Button
                      GestureDetector(
                        onTap: () => _showGeoRegionModal(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isAuto ? AppTheme.accentGreen.withValues(alpha: 0.2) : AppTheme.bgCard,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isAuto ? AppTheme.accentGreen : AppTheme.borderSubtle,
                              width: isAuto ? 1.2 : 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                label,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Icon(Icons.arrow_drop_down, color: Colors.white54, size: 14),
                            ],
                          ),
                        ),
                      ),

                      _buildNavItem(icon: Icons.download_rounded, index: 2),
                      _buildNavItem(icon: Icons.person_rounded, index: 3),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({required IconData icon, required int index}) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          _currentIndex = index;
          _isBottomBarVisible = true;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Icon(
          icon,
          size: 24,
          color: isSelected ? AppTheme.accentGreen : AppTheme.textMuted,
        ),
      ),
    );
  }

  Widget _buildCategoryTabsBar() {
    final tabs = HomeScreen.getCategoryTabs(widget.storage);
    if (_homeCategoryIndex >= tabs.length) {
      _homeCategoryIndex = (tabs.length - 1).clamp(0, 999);
    }
    return Container(
      height: 38,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.borderSubtle, width: 0.5)),
      ),
      child: ListView.builder(
        controller: _categoryTabsScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: tabs.length,
        itemBuilder: (context, index) {
          final isSelected = _homeCategoryIndex == index;
          return GestureDetector(
            onTap: () {
              setState(() => _homeCategoryIndex = index);
              _homeKey.currentState?.setCategoryIndex(index);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    tabs[index],
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (isSelected)
                    Container(
                      width: 20,
                      height: 2,
                      decoration: BoxDecoration(
                        gradient: AppTheme.brandGradient,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
