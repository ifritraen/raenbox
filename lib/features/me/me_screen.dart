import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/moviebox_models.dart';
import '../../data/services/local_storage_service.dart';
import '../../data/services/moviebox_api_service.dart';
import '../detail/detail_screen.dart';
import '../settings/settings_screen.dart';
import 'bouncy_category_sheet.dart';

class MeScreen extends StatefulWidget {
  final LocalStorageService storage;
  final MovieBoxApiService apiService;

  const MeScreen({
    super.key,
    required this.storage,
    required this.apiService,
  });

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedCategory = 'All';


  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    widget.storage.addListener(_onUpdate);
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.storage.removeListener(_onUpdate);
    _tabController.dispose();
    super.dispose();
  }

  void _showRegionPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final isAuto = widget.storage.isAutoRegion;
        final detectedCatalog = LocalStorageService.getCatalog(widget.storage.detectedRegion);

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Content Catalog & Language (Dynamic)',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                // Option A: Auto-Detect
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isAuto ? AppTheme.accentGreen : AppTheme.borderSubtle,
                      width: isAuto ? 1.5 : 0.8,
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(Icons.my_location, color: AppTheme.accentGreen),
                    title: const Text(
                      'Auto-Detect (Recommended)',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: Text(
                      'Detected: ${detectedCatalog.flag} ${detectedCatalog.name}',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                    trailing: isAuto ? Icon(Icons.check_circle, color: AppTheme.accentGreen) : null,
                    onTap: () {
                      widget.storage.setAutoRegion(true);
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Content catalog set to Auto-Detect (${detectedCatalog.name})')),
                      );
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Select Language / Content Catalog:',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                ...LocalStorageService.supportedCatalogs.map((catalog) {
                  final isSelected = !isAuto && widget.storage.activeRegion == catalog.code;
                  return ListTile(
                    leading: Text(catalog.flag, style: const TextStyle(fontSize: 20)),
                    title: Text(
                      catalog.name,
                      style: TextStyle(
                        color: isSelected ? AppTheme.accentGreen : Colors.white,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      catalog.description,
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                    ),
                    trailing: isSelected ? Icon(Icons.check, color: AppTheme.accentGreen) : null,
                    onTap: () {
                      widget.storage.setActiveRegion(catalog.code, isManual: true);
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Content catalog set to ${catalog.name}')),
                      );
                    },
                  );
                }),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final history = widget.storage.getWatchHistory();
    final bookmarks = widget.storage.getBookmarks();
    final favorites = widget.storage.getFavorites();

    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Profile Card
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: AppTheme.bgCard,
                    child: Icon(Icons.person, color: AppTheme.accentGreen, size: 34),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'RaenBox',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: _showRegionPicker,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppTheme.bgCard,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.public, color: AppTheme.accentGreen, size: 14),
                                const SizedBox(width: 6),
                                Text(
                                  widget.storage.isAutoRegion
                                      ? 'Auto (${widget.storage.activeRegionCountryName})'
                                      : widget.storage.activeRegionCountryName,
                                  style: TextStyle(
                                    color: AppTheme.accentGreen,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.arrow_drop_down, color: AppTheme.accentGreen, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Keep Screen Awake Wake Lock Toggle
                  Tooltip(
                    message: widget.storage.isKeepScreenAwake
                        ? 'Screen wake lock: ON'
                        : 'Screen wake lock: OFF (sleep allowed)',
                    child: InkWell(
                      onTap: () async {
                        final next = !widget.storage.isKeepScreenAwake;
                        await widget.storage.setKeepScreenAwake(next);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(next ? 'Wake Lock enabled (Screen stays awake)' : 'Wake Lock disabled'),
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: AppTheme.bgCard,
                            ),
                          );
                        }
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: widget.storage.isKeepScreenAwake
                              ? AppTheme.accentGreen.withValues(alpha: 0.15)
                              : AppTheme.bgCard,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: widget.storage.isKeepScreenAwake
                                ? AppTheme.accentGreen.withValues(alpha: 0.6)
                                : AppTheme.borderSubtle,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.storage.isKeepScreenAwake ? Icons.wb_sunny : Icons.wb_sunny_outlined,
                              color: widget.storage.isKeepScreenAwake ? AppTheme.accentGreen : AppTheme.textMuted,
                              size: 16,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              widget.storage.isKeepScreenAwake ? 'Stay Awake' : 'Sleep OK',
                              style: TextStyle(
                                color: widget.storage.isKeepScreenAwake ? AppTheme.accentGreen : AppTheme.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Settings Screen Button
                  Tooltip(
                    message: 'Settings',
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SettingsScreen(storage: widget.storage),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppTheme.bgCard,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.borderSubtle),
                        ),
                        child: const Icon(Icons.settings_outlined, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Tabs for Local Lists
            TabBar(
              controller: _tabController,
              indicatorColor: AppTheme.accentGreen,
              labelColor: Colors.white,
              unselectedLabelColor: AppTheme.textMuted,
              tabs: [
                Tab(text: 'My List (${bookmarks.length})'),
                Tab(text: 'Likes (${favorites.length})'),
                Tab(text: 'History (${history.length})'),
              ],
            ),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildMyListTab(bookmarks),
                  _buildMediaGrid(favorites),
                  _buildHistoryList(history),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // My List Category Architecture & Long-Tap Bouncy Integration
  // -------------------------------------------------------------
  Widget _buildMyListTab(List<LocalRecord> bookmarks) {
    final categories = widget.storage.getMyListCategories();
    if (_selectedCategory != 'All' && !categories.contains(_selectedCategory)) {
      _selectedCategory = 'All';
    }

    final filtered = _selectedCategory == 'All'
        ? bookmarks
        : bookmarks.where((b) => b.categories.contains(_selectedCategory)).toList();

    return Column(
      children: [
        _buildCategoryPills(bookmarks, categories),
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyCategoryState(bookmarks.isEmpty)
              : _buildMyListGrid(filtered),
        ),
      ],
    );
  }

  Widget _buildCategoryPills(List<LocalRecord> bookmarks, List<String> categories) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(vertical: 6),
      color: AppTheme.bgPrimary,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          // Create New Category Plus + Button at the top
          GestureDetector(
            onTap: _showCreateCategoryDialog,
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.accentGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.6)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, color: AppTheme.accentGreen, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'New',
                    style: TextStyle(
                      color: AppTheme.accentGreen,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 'All' Category Pill
          _buildPill(
            label: 'All (${bookmarks.length})',
            isSelected: _selectedCategory == 'All',
            onTap: () => setState(() => _selectedCategory = 'All'),
          ),

          // User Custom Category Pills
          for (final category in categories)
            Builder(
              builder: (context) {
                final count = bookmarks.where((b) => b.categories.contains(category)).length;
                return _buildPill(
                  label: '$category ($count)',
                  isSelected: _selectedCategory == category,
                  onTap: () => setState(() => _selectedCategory = category),
                  onLongPress: () => _showCategoryOptionsDialog(category),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPill({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accentGreen : AppTheme.bgSecondary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.accentGreen : AppTheme.borderSubtle,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.white,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMyListGrid(List<LocalRecord> records) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2 / 3.4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: records.length,
      itemBuilder: (context, index) {
        final item = records[index];
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
            showBouncyCategorySheet(
              context: context,
              record: item,
              storage: widget.storage,
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox.expand(
                        child: item.coverUrl != null && item.coverUrl!.startsWith('http')
                            ? CachedNetworkImage(
                                imageUrl: item.coverUrl!,
                                fit: BoxFit.cover,
                                memCacheWidth: 220,
                                memCacheHeight: 330,
                                placeholder: (context, url) => Container(color: AppTheme.bgCard),
                                errorWidget: (context, url, error) =>
                                    const Icon(Icons.movie, color: Colors.white54),
                              )
                            : Container(
                                color: AppTheme.bgCard,
                                child: const Icon(Icons.movie, color: Colors.white54),
                              ),
                      ),
                    ),
                    if (item.categories.isNotEmpty)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.7), width: 0.8),
                          ),
                          child: Text(
                            '${item.categories.length}',
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

  Widget _buildEmptyCategoryState(bool isTotalEmpty) {
    if (isTotalEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bookmark_outline, color: Colors.white24, size: 48),
            const SizedBox(height: 10),
            Text('No saved items in My List yet', style: const TextStyle(color: AppTheme.textMuted, fontSize: 14)),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.folder_open_outlined, color: Colors.white24, size: 48),
          const SizedBox(height: 10),
          Text(
            'No items in "$_selectedCategory"',
            style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Long press any item in My List to add it here',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: () => setState(() => _selectedCategory = 'All'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.bgSecondary,
              foregroundColor: AppTheme.accentGreen,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: AppTheme.accentGreen),
              ),
            ),
            child: const Text('View All Items'),
          ),
        ],
      ),
    );
  }

  void _showCreateCategoryDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppTheme.bgSecondary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              Icon(Icons.create_new_folder_outlined, color: AppTheme.accentGreen, size: 22),
              const SizedBox(width: 8),
              const Text(
                'New Category',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Category name (e.g. Anime, Must Watch)',
              hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
              filled: true,
              fillColor: AppTheme.bgSurface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.borderSubtle),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.accentGreen),
              ),
            ),
            onSubmitted: (_) async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                await widget.storage.addMyListCategory(name);
                setState(() => _selectedCategory = name);
                if (ctx.mounted) Navigator.of(ctx).pop();
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentGreen,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  await widget.storage.addMyListCategory(name);
                  setState(() => _selectedCategory = name);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                }
              },
              child: const Text('Create', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showCategoryOptionsDialog(String category) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Category: $category',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Divider(color: AppTheme.borderSubtle, height: 1),
              ListTile(
                leading: Icon(Icons.edit_outlined, color: AppTheme.accentCyan),
                title: const Text('Rename Category', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showRenameCategoryDialog(category);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Delete Category', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showDeleteCategoryConfirm(category);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showRenameCategoryDialog(String category) {
    final controller = TextEditingController(text: category);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppTheme.bgSecondary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text(
            'Rename Category',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppTheme.bgSurface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.borderSubtle),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.accentGreen),
              ),
            ),
            onSubmitted: (_) async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != category) {
                await widget.storage.renameMyListCategory(category, newName);
                if (_selectedCategory == category) {
                  setState(() => _selectedCategory = newName);
                }
              }
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentGreen,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final newName = controller.text.trim();
                if (newName.isNotEmpty && newName != category) {
                  await widget.storage.renameMyListCategory(category, newName);
                  if (_selectedCategory == category) {
                    setState(() => _selectedCategory = newName);
                  }
                }
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteCategoryConfirm(String category) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppTheme.bgSecondary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text(
            'Delete Category',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Are you sure you want to delete "$category"? Items will remain in My List.',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                await widget.storage.deleteMyListCategory(category);
                if (_selectedCategory == category) {
                  setState(() => _selectedCategory = 'All');
                }
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMediaGrid(List<LocalRecord> records) {
    if (records.isEmpty) {
      return const Center(
        child: Text('No saved items yet', style: TextStyle(color: AppTheme.textMuted)),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2 / 3.4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: records.length,
      itemBuilder: (context, index) {
        final item = records[index];
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
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

  Widget _buildHistoryList(List<LocalRecord> history) {
    if (history.isEmpty) {
      return const Center(
        child: Text('No watch history yet', style: TextStyle(color: AppTheme.textMuted)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: history.length,
      itemBuilder: (context, index) {
        final item = history[index];
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
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderSubtle),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 50,
                    height: 70,
                    child: item.coverUrl != null
                        ? CachedNetworkImage(
                            imageUrl: item.coverUrl!,
                            fit: BoxFit.cover,
                            memCacheWidth: 150,
                            memCacheHeight: 210,
                          )
                        : Container(color: AppTheme.bgSurface),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: item.progressPercent,
                        backgroundColor: AppTheme.bgSurface,
                        color: AppTheme.accentGreen,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Watched ${(item.progressPercent * 100).toInt()}%',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.play_circle_fill, color: AppTheme.accentGreen, size: 28),
              ],
            ),
          ),
        );
      },
    );
  }
}
