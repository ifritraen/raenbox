import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/moviebox_models.dart';
import '../../data/services/local_storage_service.dart';
import '../../data/services/moviebox_api_service.dart';
import 'home_screen.dart';

class SectionItem {
  final String id;
  final String title;
  final bool isCustom;
  bool isHidden;
  final CustomSectionConfig? customConfig;

  SectionItem({
    required this.id,
    required this.title,
    this.isCustom = false,
    this.isHidden = false,
    this.customConfig,
  });
}

class SectionCustomizerSheet extends StatefulWidget {
  final int tabIndex;
  final String tabName;
  final List<DynamicFeedSection> currentSections;
  final LocalStorageService storage;
  final MovieBoxApiService apiService;
  final VoidCallback onSectionsUpdated;

  const SectionCustomizerSheet({
    super.key,
    required this.tabIndex,
    required this.tabName,
    required this.currentSections,
    required this.storage,
    required this.apiService,
    required this.onSectionsUpdated,
  });

  static Future<void> show({
    required BuildContext context,
    required int tabIndex,
    required String tabName,
    required List<DynamicFeedSection> currentSections,
    required LocalStorageService storage,
    required MovieBoxApiService apiService,
    required VoidCallback onSectionsUpdated,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SectionCustomizerSheet(
        tabIndex: tabIndex,
        tabName: tabName,
        currentSections: currentSections,
        storage: storage,
        apiService: apiService,
        onSectionsUpdated: onSectionsUpdated,
      ),
    );
  }

  @override
  State<SectionCustomizerSheet> createState() => _SectionCustomizerSheetState();
}

class _SectionCustomizerSheetState extends State<SectionCustomizerSheet> {
  late List<SectionItem> _sections;
  late Set<String> _hiddenIds;

  @override
  void initState() {
    super.initState();
    _loadSections();
  }

  void _loadSections() {
    _hiddenIds = widget.storage.getTabHiddenSections(widget.tabIndex);
    final savedOrder = widget.storage.getTabSectionOrder(widget.tabIndex);

    // Map existing live sections
    final allItems = <String, SectionItem>{};

    for (final sec in widget.currentSections) {
      allItems[sec.title] = SectionItem(
        id: sec.title,
        title: sec.title,
        isCustom: false,
        isHidden: _hiddenIds.contains(sec.title),
      );
    }

    // If Home tab, also include saved custom sections
    if (widget.tabIndex == 0) {
      final customList = widget.storage.getHomeCustomSections();
      for (final cs in customList) {
        allItems[cs.title] = SectionItem(
          id: cs.id,
          title: cs.title,
          isCustom: cs.isCustom,
          isHidden: _hiddenIds.contains(cs.id) || _hiddenIds.contains(cs.title),
          customConfig: cs,
        );
      }
    }

    // Reconcile with saved order
    final ordered = <SectionItem>[];
    for (final id in savedOrder) {
      if (allItems.containsKey(id)) {
        ordered.add(allItems.remove(id)!);
      }
    }
    // Append any remaining
    ordered.addAll(allItems.values);

    _sections = ordered;
  }

  Future<void> _persistChanges() async {
    final order = _sections.map((s) => s.id).toList();
    final hidden = _sections.where((s) => s.isHidden).map((s) => s.id).toSet();

    await widget.storage.setTabSectionOrder(widget.tabIndex, order);
    await widget.storage.setTabHiddenSections(widget.tabIndex, hidden);
    widget.onSectionsUpdated();
  }

  void _onReorder(int oldIndex, int newIndex) {
    HapticFeedback.selectionClick();
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _sections.removeAt(oldIndex);
      _sections.insert(newIndex, item);
    });
    _persistChanges();
  }

  void _toggleVisibility(SectionItem item) {
    HapticFeedback.lightImpact();
    setState(() {
      item.isHidden = !item.isHidden;
    });
    _persistChanges();
  }

  Future<void> _deleteCustomSection(SectionItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Delete Custom Section', style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove "${item.title}" from your Home tab?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      HapticFeedback.mediumImpact();
      await widget.storage.removeHomeCustomSection(item.id);
      setState(() {
        _sections.removeWhere((s) => s.id == item.id);
      });
      await _persistChanges();
    }
  }

  Future<void> _resetToDefault() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Reset Layout', style: TextStyle(color: Colors.white)),
        content: Text(
          'Restore default section order and show all hidden sections for ${widget.tabName}?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentGreen),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reset', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      HapticFeedback.mediumImpact();
      await widget.storage.resetTabSectionConfig(widget.tabIndex);
      setState(() {
        _loadSections();
      });
      widget.onSectionsUpdated();
    }
  }

  void _openLibraryPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => LibrarySectionPickerSheet(
        storage: widget.storage,
        onSectionSelected: (title, type, keyword, genre, country, sort) async {
          final id = 'lib_${DateTime.now().millisecondsSinceEpoch}';
          final newSec = CustomSectionConfig(
            id: id,
            title: title,
            type: type,
            keyword: keyword,
            genre: genre,
            country: country,
            sort: sort,
            isCustom: true,
            librarySource: title,
          );
          await widget.storage.addHomeCustomSection(newSec);
          setState(() {
            _loadSections();
          });
          await _persistChanges();
        },
      ),
    );
  }

  void _openCustomSectionCreator() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => CustomSectionDialog(
        apiService: widget.apiService,
        storage: widget.storage,
        onSaved: () {
          setState(() {
            _loadSections();
          });
          _persistChanges();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),

            // Header Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.dashboard_customize, color: AppTheme.accentGreen, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'Customize ${widget.tabName} Feed',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white54, size: 20),
                    tooltip: 'Reset to default',
                    onPressed: _resetToDefault,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(color: AppTheme.borderSubtle, height: 1),

            // Instructional tip
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.drag_indicator, color: AppTheme.textMuted, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Hold & drag to reorder. Tap eye to hide/show.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  ),
                  const Spacer(),
                  Text(
                    '${_sections.where((s) => !s.isHidden).length} Visible',
                    style: TextStyle(
                      color: AppTheme.accentGreen,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            // Reorderable list
            Expanded(
              child: _sections.isEmpty
                  ? const Center(
                      child: Text(
                        'No sections found on this tab',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      itemCount: _sections.length,
                      onReorder: _onReorder,
                      itemBuilder: (context, index) {
                        final item = _sections[index];
                        return _buildSectionTile(item, index);
                      },
                    ),
            ),

            // Home Tab Action Bar (+ Add from Library, + Create Custom Section)
            if (widget.tabIndex == 0) ...[
              Divider(color: AppTheme.borderSubtle, height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(color: AppTheme.borderSubtle),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: Icon(Icons.library_add_outlined, size: 18, color: AppTheme.accentCyan),
                        label: const Text('Add From Library', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: _openLibraryPicker,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentGreen,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.add_circle_outline, size: 18),
                        label: const Text('New Custom Section', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: _openCustomSectionCreator,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTile(SectionItem item, int index) {
    return Container(
      key: ValueKey(item.id),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: item.isHidden ? AppTheme.bgCard.withValues(alpha: 0.35) : AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.isHidden ? AppTheme.borderSubtle.withValues(alpha: 0.3) : AppTheme.borderSubtle,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: ReorderableDragStartListener(
          index: index,
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.drag_handle, color: Colors.white54, size: 22),
          ),
        ),
        title: Text(
          item.title,
          style: TextStyle(
            color: item.isHidden ? Colors.white38 : Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            decoration: item.isHidden ? TextDecoration.lineThrough : null,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: item.isCustom
            ? Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppTheme.accentCyan.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'CUSTOM',
                      style: TextStyle(color: AppTheme.accentCyan, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Visibility Toggle
            IconButton(
              icon: Icon(
                item.isHidden ? Icons.visibility_off_outlined : Icons.visibility,
                color: item.isHidden ? Colors.white30 : AppTheme.accentGreen,
                size: 20,
              ),
              tooltip: item.isHidden ? 'Show section' : 'Hide section',
              onPressed: () => _toggleVisibility(item),
            ),
            // Delete button if custom
            if (item.isCustom && widget.tabIndex == 0)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                tooltip: 'Delete custom section',
                onPressed: () => _deleteCustomSection(item),
              ),
          ],
        ),
      ),
    );
  }
}

// ==============================================================================
// CUSTOM SECTION CREATOR DIALOG (Search, Filter, Sort, Live Preview)
// ==============================================================================
class CustomSectionDialog extends StatefulWidget {
  final MovieBoxApiService apiService;
  final LocalStorageService storage;
  final VoidCallback onSaved;

  const CustomSectionDialog({
    super.key,
    required this.apiService,
    required this.storage,
    required this.onSaved,
  });

  @override
  State<CustomSectionDialog> createState() => _CustomSectionDialogState();
}

class _CustomSectionDialogState extends State<CustomSectionDialog> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _keywordController = TextEditingController();

  String _selectedType = 'all'; // 'all', 'movie', 'tv', 'anime'
  String _selectedGenre = 'All';
  String _selectedCountry = 'All';
  String _selectedYear = 'All';
  String _selectedSort = 'ForYou';

  bool _isPreviewLoading = false;
  List<MediaItem> _previewItems = [];
  bool _hasPreviewed = false;

  final List<String> _genres = [
    'All', 'Action', 'Adventure', 'Animation', 'Comedy', 'Crime',
    'Drama', 'Fantasy', 'Horror', 'Mystery', 'Romance', 'Sci-Fi', 'Thriller',
  ];

  final List<String> _countries = [
    'All', 'United States', 'Korea', 'Japan', 'India', 'Bangladesh',
    'China', 'Philippines', 'United Kingdom', 'France',
  ];

  final List<String> _years = [
    'All', '2026', '2025', '2024', '2023', '2022', '2021', '2020', '2010s', '2000s', '1990s',
  ];

  final List<String> _sortOptions = ['ForYou', 'Popular', 'Latest', 'HighRating'];

  @override
  void dispose() {
    _titleController.dispose();
    _keywordController.dispose();
    super.dispose();
  }

  void _updateAutoTitle() {
    if (_titleController.text.trim().isNotEmpty && !_titleController.text.startsWith('✨')) {
      return;
    }
    final parts = <String>[];
    if (_selectedGenre != 'All') parts.add(_selectedGenre);
    if (_selectedCountry != 'All') parts.add(_selectedCountry);
    if (_selectedYear != 'All') parts.add(_selectedYear);
    if (_keywordController.text.trim().isNotEmpty) {
      parts.add('"${_keywordController.text.trim()}"');
    }

    final typeStr = _selectedType == 'movie'
        ? 'Movies'
        : _selectedType == 'tv'
            ? 'Series'
            : _selectedType == 'anime'
                ? 'Anime'
                : 'Picks';

    if (parts.isEmpty) {
      _titleController.text = '✨ Custom $typeStr';
    } else {
      _titleController.text = '✨ ${parts.join(" ")} $typeStr';
    }
  }

  Future<void> _runPreview() async {
    setState(() {
      _isPreviewLoading = true;
      _hasPreviewed = true;
    });

    try {
      final keyword = _keywordController.text.trim();
      List<MediaItem> items = [];

      if (keyword.isNotEmpty) {
        items = await widget.apiService.search(keyword, perPage: 10);
      } else {
        String channelId = '1';
        if (_selectedType == 'tv') channelId = '2';
        if (_selectedType == 'anime') channelId = '1006';

        items = await widget.apiService.fetchWebSubjectFilter(
          channelId: channelId,
          genre: _selectedGenre,
          country: _selectedCountry,
          year: _selectedYear,
          sort: _selectedSort,
          perPage: 10,
        );
      }

      if (mounted) {
        setState(() {
          _previewItems = items;
          _isPreviewLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _previewItems = [];
          _isPreviewLoading = false;
        });
      }
    }
  }

  Future<void> _saveSection() async {
    final title = _titleController.text.trim().isEmpty
        ? 'Custom Section'
        : _titleController.text.trim();

    final config = CustomSectionConfig(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      type: _selectedType,
      keyword: _keywordController.text.trim().isNotEmpty ? _keywordController.text.trim() : null,
      genre: _selectedGenre != 'All' ? _selectedGenre : null,
      country: _selectedCountry != 'All' ? _selectedCountry : null,
      year: _selectedYear != 'All' ? _selectedYear : null,
      sort: _selectedSort,
      isCustom: true,
    );

    HapticFeedback.mediumImpact();
    await widget.storage.addHomeCustomSection(config);
    widget.onSaved();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Handle Bar
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, color: AppTheme.accentGreen, size: 22),
                  const SizedBox(width: 10),
                  const Text(
                    'Create Custom Section',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(color: AppTheme.borderSubtle, height: 1),

            // Scrollable Form
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                children: [
                  // 1. Section Title
                  const Text('Section Title', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'e.g. ✨ 90s Cyberpunk Thrillers',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: AppTheme.bgCard,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppTheme.borderSubtle),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppTheme.borderSubtle),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppTheme.accentGreen),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. Content Type
                  const Text('Content Type', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ('all', 'All Media'),
                      ('movie', 'Movies'),
                      ('tv', 'TV Series'),
                      ('anime', 'Anime'),
                    ].map((t) {
                      final isSel = _selectedType == t.$1;
                      return ChoiceChip(
                        selected: isSel,
                        selectedColor: AppTheme.accentGreen.withValues(alpha: 0.25),
                        backgroundColor: AppTheme.bgCard,
                        side: BorderSide(color: isSel ? AppTheme.accentGreen : AppTheme.borderSubtle),
                        label: Text(
                          t.$2,
                          style: TextStyle(
                            color: isSel ? AppTheme.accentGreen : Colors.white70,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                        ),
                        onSelected: (_) {
                          setState(() => _selectedType = t.$1);
                          _updateAutoTitle();
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // 3. Search Keyword (Optional)
                  const Text('Search Keyword (Optional)', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _keywordController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    onChanged: (_) => _updateAutoTitle(),
                    decoration: InputDecoration(
                      hintText: 'e.g. Batman, Werewolf, Marvel, Zombie',
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 20),
                      filled: true,
                      fillColor: AppTheme.bgCard,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppTheme.borderSubtle),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppTheme.borderSubtle),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppTheme.accentGreen),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 4. Filters Grid (Genre, Country, Year, Sort)
                  const Text('Filters & Sorting', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDropdown(
                          label: 'Genre',
                          value: _selectedGenre,
                          options: _genres,
                          onChanged: (v) {
                            setState(() => _selectedGenre = v);
                            _updateAutoTitle();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildDropdown(
                          label: 'Country',
                          value: _selectedCountry,
                          options: _countries,
                          onChanged: (v) {
                            setState(() => _selectedCountry = v);
                            _updateAutoTitle();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDropdown(
                          label: 'Year',
                          value: _selectedYear,
                          options: _years,
                          onChanged: (v) {
                            setState(() => _selectedYear = v);
                            _updateAutoTitle();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildDropdown(
                          label: 'Sort',
                          value: _selectedSort,
                          options: _sortOptions,
                          onChanged: (v) => setState(() => _selectedSort = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 5. Live Preview Area
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Live Preview', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                      TextButton.icon(
                        icon: _isPreviewLoading
                            ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentGreen))
                            : Icon(Icons.visibility_outlined, size: 16, color: AppTheme.accentGreen),
                        label: Text('Test & Preview', style: TextStyle(color: AppTheme.accentGreen, fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: _isPreviewLoading ? null : _runPreview,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 145,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.borderSubtle),
                    ),
                    child: _isPreviewLoading
                        ? Center(child: CircularProgressIndicator(color: AppTheme.accentGreen))
                        : !_hasPreviewed
                            ? const Center(
                                child: Text(
                                  'Tap "Test & Preview" to load sample titles',
                                  style: TextStyle(color: Colors.white38, fontSize: 12),
                                ),
                              )
                            : _previewItems.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No titles match these filters',
                                      style: TextStyle(color: Colors.white54, fontSize: 12),
                                    ),
                                  )
                                : ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _previewItems.length,
                                    separatorBuilder: (context, index) => const SizedBox(width: 8),
                                    itemBuilder: (context, index) {
                                      final item = _previewItems[index];
                                      return ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: SizedBox(
                                          width: 80,
                                          child: (item.coverUrl != null && item.coverUrl!.startsWith('http'))
                                              ? CachedNetworkImage(
                                                  imageUrl: item.coverUrl!,
                                                  fit: BoxFit.cover,
                                                  memCacheWidth: 200,
                                                  memCacheHeight: 300,
                                                  placeholder: (context, url) => Container(color: Colors.white10),
                                                  errorWidget: (context, url, error) => Container(
                                                    color: Colors.white10,
                                                    child: const Icon(Icons.movie, color: Colors.white30, size: 24),
                                                  ),
                                                )
                                              : Container(color: Colors.white10),
                                        ),
                                      );
                                    },
                                  ),
                  ),
                  const SizedBox(height: 24),

                  // Save Section Button
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentGreen,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 20),
                    label: const Text('Save & Add to Home', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    onPressed: _saveSection,
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: options.contains(value) ? value : options.first,
          isExpanded: true,
          dropdownColor: AppTheme.bgSecondary,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          icon: const Icon(Icons.arrow_drop_down, color: Colors.white54, size: 18),
          items: options.map((opt) {
            return DropdownMenuItem<String>(
              value: opt,
              child: Text(
                opt == 'All' ? '$label: All' : opt,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) onChanged(val);
          },
        ),
      ),
    );
  }
}

// ==============================================================================
// LIBRARY SECTION PICKER SHEET
// ==============================================================================
class LibraryPresetItem {
  final String title;
  final String type; // 'movie', 'tv', 'anime', 'all'
  final String? keyword;
  final String? genre;
  final String? country;
  final String sort;
  final String categoryGroup;
  final bool is18Plus;

  const LibraryPresetItem({
    required this.title,
    required this.type,
    this.keyword,
    this.genre,
    this.country,
    required this.sort,
    required this.categoryGroup,
    this.is18Plus = false,
  });
}

class LibrarySectionPickerSheet extends StatefulWidget {
  final LocalStorageService? storage;
  final Future<void> Function(
    String title,
    String type,
    String? keyword,
    String? genre,
    String? country,
    String sort,
  ) onSectionSelected;

  const LibrarySectionPickerSheet({
    super.key,
    this.storage,
    required this.onSectionSelected,
  });

  static const List<LibraryPresetItem> catalogPresets = [
    // --- Trending Tab ---
    LibraryPresetItem(title: '🔥 Trending Right Now', type: 'all', sort: 'Popular', categoryGroup: 'Trending'),
    LibraryPresetItem(title: '🎬 Trending Movies', type: 'movie', sort: 'ForYou', categoryGroup: 'Trending'),
    LibraryPresetItem(title: '📺 Trending TV Series', type: 'tv', sort: 'ForYou', categoryGroup: 'Trending'),
    LibraryPresetItem(title: '⚡ Trending Anime', type: 'anime', sort: 'Popular', categoryGroup: 'Trending'),
    LibraryPresetItem(title: '📱 Trending Short Dramas', type: 'tv', keyword: 'Short Drama', sort: 'Popular', categoryGroup: 'Trending'),
    LibraryPresetItem(title: '🍿 New Releases in Cinema', type: 'movie', sort: 'Latest', categoryGroup: 'Trending'),
    LibraryPresetItem(title: '✨ Popular on Streaming Today', type: 'all', sort: 'Popular', categoryGroup: 'Trending'),

    // --- Rankings & Awards ---
    LibraryPresetItem(title: '⭐ Highest Rated Masterpieces', type: 'movie', sort: 'HighRating', categoryGroup: 'Rankings'),
    LibraryPresetItem(title: '👑 All-Time Cult Classics', type: 'movie', sort: 'HighRating', categoryGroup: 'Rankings'),
    LibraryPresetItem(title: '🏆 Top Rated TV Sagas', type: 'tv', sort: 'HighRating', categoryGroup: 'Rankings'),
    LibraryPresetItem(title: '🥇 Top Rated Anime Series', type: 'anime', sort: 'HighRating', categoryGroup: 'Rankings'),
    LibraryPresetItem(title: '🎟️ Box Office Number 1 Hits', type: 'movie', sort: 'Popular', categoryGroup: 'Rankings'),

    // --- Movies Tab ---
    LibraryPresetItem(title: '🎬 Hollywood Blockbusters', type: 'movie', country: 'United States', sort: 'ForYou', categoryGroup: 'Movies'),
    LibraryPresetItem(title: '💥 Action & Explosive Thrills', type: 'movie', genre: 'Action', sort: 'Popular', categoryGroup: 'Movies'),
    LibraryPresetItem(title: '🚀 Sci-Fi & Cyberpunk Worlds', type: 'movie', genre: 'Sci-Fi', sort: 'Popular', categoryGroup: 'Movies'),
    LibraryPresetItem(title: '👻 Late Night Horror & Supernatural', type: 'movie', genre: 'Horror', sort: 'Popular', categoryGroup: 'Movies'),
    LibraryPresetItem(title: '🕵️ Crime & Gangster Thrillers', type: 'movie', genre: 'Crime', sort: 'Popular', categoryGroup: 'Movies'),
    LibraryPresetItem(title: '😂 Laugh-Out-Loud Comedies', type: 'movie', genre: 'Comedy', sort: 'Popular', categoryGroup: 'Movies'),
    LibraryPresetItem(title: '❤️ Romantic Melodramas & Love', type: 'movie', genre: 'Romance', sort: 'Popular', categoryGroup: 'Movies'),
    LibraryPresetItem(title: '🧩 Psychological & Mind-Benders', type: 'movie', genre: 'Thriller', sort: 'Popular', categoryGroup: 'Movies'),
    LibraryPresetItem(title: '🗡️ Epic Adventure & Quests', type: 'movie', genre: 'Adventure', sort: 'Popular', categoryGroup: 'Movies'),
    LibraryPresetItem(title: '🧙 Fantasy & Magic Realms', type: 'movie', genre: 'Fantasy', sort: 'Popular', categoryGroup: 'Movies'),
    LibraryPresetItem(title: '🎨 Animated Feature Masterpieces', type: 'movie', genre: 'Animation', sort: 'Popular', categoryGroup: 'Movies'),
    LibraryPresetItem(title: '📜 True Story & Documentaries', type: 'movie', genre: 'Documentary', sort: 'Popular', categoryGroup: 'Movies'),
    LibraryPresetItem(title: '👨‍👩‍👧 Family & Kids Adventures', type: 'movie', genre: 'Family', sort: 'Popular', categoryGroup: 'Movies'),
    LibraryPresetItem(title: '🎖️ War & Military Epics', type: 'movie', genre: 'War', sort: 'Popular', categoryGroup: 'Movies'),
    LibraryPresetItem(title: '🔍 Mystery & Detective Cases', type: 'movie', genre: 'Mystery', sort: 'Popular', categoryGroup: 'Movies'),
    LibraryPresetItem(title: '🤠 Classic Westerns & Outlaws', type: 'movie', genre: 'Western', sort: 'Popular', categoryGroup: 'Movies'),

    // --- TV Series Tab ---
    LibraryPresetItem(title: '📺 Top Global TV Shows', type: 'tv', sort: 'Popular', categoryGroup: 'TV Shows'),
    LibraryPresetItem(title: '🕵️ Western Crime & Police Dramas', type: 'tv', genre: 'Crime', country: 'United States', sort: 'Popular', categoryGroup: 'TV Shows'),
    LibraryPresetItem(title: '🛸 Sci-Fi & Speculative Series', type: 'tv', genre: 'Sci-Fi', sort: 'Popular', categoryGroup: 'TV Shows'),
    LibraryPresetItem(title: '😂 Classic Sitcoms & Comedy Shows', type: 'tv', genre: 'Comedy', sort: 'Popular', categoryGroup: 'TV Shows'),
    LibraryPresetItem(title: '🎭 Deep Drama & Character Stories', type: 'tv', genre: 'Drama', sort: 'Popular', categoryGroup: 'TV Shows'),
    LibraryPresetItem(title: '💥 Action & Thriller Series', type: 'tv', genre: 'Action', sort: 'Popular', categoryGroup: 'TV Shows'),
    LibraryPresetItem(title: '🔮 Fantasy & Magic Sagas', type: 'tv', genre: 'Fantasy', sort: 'Popular', categoryGroup: 'TV Shows'),
    LibraryPresetItem(title: '🔍 Mystery & Investigative Series', type: 'tv', genre: 'Mystery', sort: 'Popular', categoryGroup: 'TV Shows'),
    LibraryPresetItem(title: '❤️ Romantic TV Dramas', type: 'tv', genre: 'Romance', sort: 'Popular', categoryGroup: 'TV Shows'),
    LibraryPresetItem(title: '🌟 High-Budget Prestige Series', type: 'tv', sort: 'HighRating', categoryGroup: 'TV Shows'),

    // --- Anime Tab ---
    LibraryPresetItem(title: '💥 Action & Shonen Anime', type: 'anime', genre: 'Action', sort: 'Popular', categoryGroup: 'Anime'),
    LibraryPresetItem(title: '🔮 Fantasy & Isekai World', type: 'anime', genre: 'Fantasy', sort: 'Popular', categoryGroup: 'Anime'),
    LibraryPresetItem(title: '🌸 Romance & Slice of Life Anime', type: 'anime', genre: 'Romance', sort: 'Popular', categoryGroup: 'Anime'),
    LibraryPresetItem(title: '🚀 Sci-Fi & Cyberpunk Anime', type: 'anime', genre: 'Sci-Fi', sort: 'Popular', categoryGroup: 'Anime'),
    LibraryPresetItem(title: '😂 Comedy & Parody Anime', type: 'anime', genre: 'Comedy', sort: 'Popular', categoryGroup: 'Anime'),
    LibraryPresetItem(title: '👹 Supernatural & Dark Anime', type: 'anime', genre: 'Horror', sort: 'Popular', categoryGroup: 'Anime'),
    LibraryPresetItem(title: '🎬 Top Anime Movies & Theatricals', type: 'anime', genre: 'Animation', sort: 'HighRating', categoryGroup: 'Anime'),
    LibraryPresetItem(title: '⚔️ Must-Watch Top Anime Series', type: 'anime', sort: 'HighRating', categoryGroup: 'Anime'),
    LibraryPresetItem(title: '🤖 Mecha & Robots Anime', type: 'anime', genre: 'Sci-Fi', sort: 'Popular', categoryGroup: 'Anime'),
    LibraryPresetItem(title: '⚽ Sports & Competitive Anime', type: 'anime', keyword: 'Sports', sort: 'Popular', categoryGroup: 'Anime'),

    // --- ShortTV & Mini-Dramas Tab ---
    LibraryPresetItem(title: '👑 CEO & Billionaire Mini-Dramas', type: 'tv', keyword: 'CEO', sort: 'Popular', categoryGroup: 'ShortTV'),
    LibraryPresetItem(title: '🐺 Werewolf & Supernatural Shorts', type: 'tv', keyword: 'Werewolf', sort: 'Popular', categoryGroup: 'ShortTV'),
    LibraryPresetItem(title: '⚡ Revenge & Drama Series', type: 'tv', keyword: 'Revenge', sort: 'Popular', categoryGroup: 'ShortTV'),
    LibraryPresetItem(title: '📱 Short Drama Showcase', type: 'tv', keyword: 'Short Drama', sort: 'Popular', categoryGroup: 'ShortTV'),
    LibraryPresetItem(title: '🕶️ Mafia Boss & Secret Identity', type: 'tv', keyword: 'Mafia', sort: 'Popular', categoryGroup: 'ShortTV'),
    LibraryPresetItem(title: '⏳ Rebirth & Destiny Returns', type: 'tv', keyword: 'Rebirth', sort: 'Popular', categoryGroup: 'ShortTV'),
    LibraryPresetItem(title: '💍 Contract Marriage & Sweet Love', type: 'tv', keyword: 'Marriage', sort: 'Popular', categoryGroup: 'ShortTV'),
    LibraryPresetItem(title: '🥊 Underdog to King Shorts', type: 'tv', keyword: 'Billionaire', sort: 'Popular', categoryGroup: 'ShortTV'),

    // --- Regional Cinema & Series (All Regional Catalogs) ---
    LibraryPresetItem(title: '🇧🇩 New Bangla Movies', type: 'movie', country: 'Bangladesh', sort: 'ForYou', categoryGroup: 'Regional'),
    LibraryPresetItem(title: '🇧🇩 Bangla Web Series', type: 'tv', country: 'Bangladesh', sort: 'ForYou', categoryGroup: 'Regional'),
    LibraryPresetItem(title: '🇧🇩 Bengali Dubbed Movies', type: 'movie', keyword: 'Bengali dub', sort: 'Popular', categoryGroup: 'Regional'),
    LibraryPresetItem(title: '🇧🇩 Dhallywood Action Cinema', type: 'movie', country: 'Bangladesh', genre: 'Action', sort: 'Popular', categoryGroup: 'Regional'),
    LibraryPresetItem(title: '🇮🇳 Bollywood & Indian Cinema', type: 'movie', country: 'India', sort: 'ForYou', categoryGroup: 'Regional'),
    LibraryPresetItem(title: '🇮🇳 Top Indian Web Series', type: 'tv', country: 'India', sort: 'Popular', categoryGroup: 'Regional'),
    LibraryPresetItem(title: '🇮🇳 South Indian Blockbusters', type: 'movie', country: 'India', keyword: 'South Indian', sort: 'Popular', categoryGroup: 'Regional'),
    LibraryPresetItem(title: '🇮🇳 Punjabi Cinema', type: 'movie', country: 'India', keyword: 'Punjabi', sort: 'Popular', categoryGroup: 'Regional'),
    LibraryPresetItem(title: '🇮🇳 Hindi Dubbed South Hits', type: 'movie', country: 'India', keyword: 'Hindi dub', sort: 'Popular', categoryGroup: 'Regional'),
    LibraryPresetItem(title: '🇵🇭 Pinoy Movies & Cinema', type: 'movie', country: 'Philippines', sort: 'ForYou', categoryGroup: 'Regional'),
    LibraryPresetItem(title: '🇵🇭 Filipino Teleserye & Series', type: 'tv', country: 'Philippines', sort: 'Popular', categoryGroup: 'Regional'),
    LibraryPresetItem(title: '🇳🇬 Nollywood Blockbusters', type: 'movie', country: 'Nigeria', sort: 'ForYou', categoryGroup: 'Regional'),
    LibraryPresetItem(title: '🇳🇬 African Cinema Spotlight', type: 'movie', country: 'Nigeria', sort: 'Popular', categoryGroup: 'Regional'),
    LibraryPresetItem(title: '🇳🇬 Naija Drama Series', type: 'tv', country: 'Nigeria', sort: 'Popular', categoryGroup: 'Regional'),
    LibraryPresetItem(title: '🇰🇷 Best K-Drama Collection', type: 'tv', country: 'Korea', sort: 'Popular', categoryGroup: 'Regional'),
    LibraryPresetItem(title: '🇰🇷 Korean Cinema & K-Thrillers', type: 'movie', country: 'Korea', sort: 'ForYou', categoryGroup: 'Regional'),
    LibraryPresetItem(title: '🏮 C-Drama Romance & Historical', type: 'tv', country: 'China', sort: 'Popular', categoryGroup: 'Regional'),
    LibraryPresetItem(title: '🇨🇳 Chinese Martial Arts & Wuxia', type: 'movie', country: 'China', sort: 'ForYou', categoryGroup: 'Regional'),
    LibraryPresetItem(title: '🌸 J-Drama Heartwarmers', type: 'tv', country: 'Japan', sort: 'Popular', categoryGroup: 'Regional'),
    LibraryPresetItem(title: '🇯🇵 Japanese Cinema & Classics', type: 'movie', country: 'Japan', sort: 'ForYou', categoryGroup: 'Regional'),
    LibraryPresetItem(title: '🌙 Turkish Drama Sagas', type: 'tv', country: 'Turkey', sort: 'Popular', categoryGroup: 'Regional'),
    LibraryPresetItem(title: '🇵🇰 Pakistani TV Masterpieces', type: 'tv', country: 'Pakistan', sort: 'Popular', categoryGroup: 'Regional'),
    LibraryPresetItem(title: '🇬🇧 British & UK Cinema', type: 'movie', country: 'United Kingdom', sort: 'ForYou', categoryGroup: 'Regional'),
    LibraryPresetItem(title: '🇫🇷 French & European Cinema', type: 'movie', country: 'France', sort: 'ForYou', categoryGroup: 'Regional'),

    // --- MidNight Tab / 18+ (Explicitly flagged) ---
    LibraryPresetItem(title: '💋 Vivamax Exclusives', type: 'movie', keyword: 'Vivamax', country: 'Philippines', sort: 'Popular', categoryGroup: 'MidNight', is18Plus: true),
    LibraryPresetItem(title: '🔥 Tbonx Late-Night Cinema', type: 'movie', keyword: 'Tbonx', sort: 'Popular', categoryGroup: 'MidNight', is18Plus: true),
    LibraryPresetItem(title: '🌶️ Cinepop Sensual Spotlight', type: 'movie', keyword: 'Cinepop', sort: 'Popular', categoryGroup: 'MidNight', is18Plus: true),
    LibraryPresetItem(title: '🔞 UllU Hot Drama Collection', type: 'tv', keyword: 'UllU', country: 'India', sort: 'Popular', categoryGroup: 'MidNight', is18Plus: true),
    LibraryPresetItem(title: '🌙 Late-Night Shorts & Romance', type: 'movie', keyword: 'Late-night', sort: 'Popular', categoryGroup: 'MidNight', is18Plus: true),
    LibraryPresetItem(title: '🔞 Adult Anime & Hentai', type: 'anime', keyword: 'Hentai', sort: 'Popular', categoryGroup: 'MidNight', is18Plus: true),
    LibraryPresetItem(title: '🔞 Japanese 18+ Cinema', type: 'movie', country: 'Japan', keyword: '18+', sort: 'Popular', categoryGroup: 'MidNight', is18Plus: true),
    LibraryPresetItem(title: '🔞 Korean 18+ Melodramas', type: 'movie', country: 'Korea', keyword: '18+', sort: 'Popular', categoryGroup: 'MidNight', is18Plus: true),
    LibraryPresetItem(title: '🔞 Pinoy Bold Cinema', type: 'movie', country: 'Philippines', keyword: '18+', sort: 'Popular', categoryGroup: 'MidNight', is18Plus: true),
  ];

  @override
  State<LibrarySectionPickerSheet> createState() => _LibrarySectionPickerSheetState();
}

class _LibrarySectionPickerSheetState extends State<LibrarySectionPickerSheet> {
  String _selectedCategory = 'All';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> _getAvailableCategories(bool is18PlusDisabled) {
    final categories = ['All', 'Trending', 'Movies', 'TV Shows', 'Anime', 'ShortTV', 'Regional', 'Rankings'];
    if (!is18PlusDisabled) {
      categories.add('MidNight');
    }
    return categories;
  }

  @override
  Widget build(BuildContext context) {
    final is18PlusDisabled = widget.storage?.is18PlusDisabled ?? true;
    final availableCategories = _getAvailableCategories(is18PlusDisabled);

    final filteredPresets = LibrarySectionPickerSheet.catalogPresets.where((p) {
      // 1. Adult Kill Switch Filtering
      if (is18PlusDisabled && p.is18Plus) return false;

      // 2. Category Tab Filtering
      if (_selectedCategory != 'All' && p.categoryGroup != _selectedCategory) {
        return false;
      }

      // 3. Search Query Filtering
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchTitle = p.title.toLowerCase().contains(query);
        final matchGenre = p.genre?.toLowerCase().contains(query) ?? false;
        final matchCountry = p.country?.toLowerCase().contains(query) ?? false;
        final matchKeyword = p.keyword?.toLowerCase().contains(query) ?? false;
        final matchType = p.type.toLowerCase().contains(query);
        return matchTitle || matchGenre || matchCountry || matchKeyword || matchType;
      }

      return true;
    }).toList();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Handle Bar
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.library_add, color: AppTheme.accentCyan, size: 22),
                  const SizedBox(width: 10),
                  const Text(
                    'Add Section From Library',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search genres, countries, rankings...',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 18),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.white54, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppTheme.bgCard,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppTheme.borderSubtle),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppTheme.borderSubtle),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppTheme.accentCyan),
                  ),
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
              ),
            ),

            // Horizontal Category Filter Chips
            Container(
              height: 42,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: availableCategories.length,
                separatorBuilder: (context, index) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final cat = availableCategories[index];
                  final isSel = _selectedCategory == cat;
                  final isMidnight = cat == 'MidNight';
                  return ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    selected: isSel,
                    selectedColor: isMidnight
                        ? Colors.redAccent.withValues(alpha: 0.3)
                        : AppTheme.accentCyan.withValues(alpha: 0.25),
                    backgroundColor: AppTheme.bgCard,
                    side: BorderSide(
                      color: isSel
                          ? (isMidnight ? Colors.redAccent : AppTheme.accentCyan)
                          : AppTheme.borderSubtle,
                    ),
                    label: Text(
                      isMidnight ? 'MidNight🔞' : cat,
                      style: TextStyle(
                        color: isSel
                            ? (isMidnight ? Colors.redAccent : AppTheme.accentCyan)
                            : Colors.white70,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        fontSize: 11,
                      ),
                    ),
                    onSelected: (_) => setState(() => _selectedCategory = cat),
                  );
                },
              ),
            ),
            Divider(color: AppTheme.borderSubtle, height: 1),

            // Filtered Preset Section List
            Expanded(
              child: filteredPresets.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.search_off, color: Colors.white24, size: 40),
                          const SizedBox(height: 8),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'No sections found for "$_searchQuery"'
                                : 'No sections available in this category',
                            style: const TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: filteredPresets.length,
                      separatorBuilder: (context, index) => Divider(color: AppTheme.borderSubtle, height: 1),
                      itemBuilder: (context, index) {
                        final p = filteredPresets[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: p.is18Plus
                                  ? Colors.redAccent.withValues(alpha: 0.15)
                                  : AppTheme.accentCyan.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              p.is18Plus ? Icons.explicit : Icons.add,
                              color: p.is18Plus ? Colors.redAccent : AppTheme.accentCyan,
                              size: 18,
                            ),
                          ),
                          title: Text(
                            p.title,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          subtitle: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  p.type.toUpperCase(),
                                  style: TextStyle(color: AppTheme.accentGreen, fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                              ),
                              if (p.genre != null) ...[
                                const SizedBox(width: 5),
                                Text(
                                  '• ${p.genre}',
                                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                                ),
                              ],
                              if (p.country != null) ...[
                                const SizedBox(width: 5),
                                Text(
                                  '• ${p.country}',
                                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                                ),
                              ],
                              const SizedBox(width: 5),
                              Text(
                                '• ${p.sort}',
                                style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                              ),
                            ],
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.accentCyan.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.accentCyan.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              '+ Add',
                              style: TextStyle(
                                color: AppTheme.accentCyan,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            Navigator.of(context).pop();
                            widget.onSectionSelected(p.title, p.type, p.keyword, p.genre, p.country, p.sort);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
