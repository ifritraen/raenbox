import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/moviebox_models.dart';
import '../../data/services/local_storage_service.dart';

Future<void> showBouncyCategorySheet({
  required BuildContext context,
  required LocalStorageService storage,
  LocalRecord? record,
  MediaItem? mediaItem,
}) {
  assert(record != null || mediaItem != null, 'Either record or mediaItem must be provided');
  final effectiveRecord = record ??
      LocalRecord(
        subjectId: mediaItem!.subjectId,
        title: mediaItem.title,
        coverUrl: mediaItem.coverUrl,
        subjectType: mediaItem.subjectType,
        updatedAt: DateTime.now(),
      );

  HapticFeedback.mediumImpact();
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black.withValues(alpha: 0.7),
    transitionDuration: const Duration(milliseconds: 420),
    pageBuilder: (ctx, anim1, anim2) => const SizedBox.shrink(),
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: Colors.transparent,
            child: BouncyCategorySheetContent(
              record: effectiveRecord,
              storage: storage,
            ),
          ),
        ),
      );
    },
  );
}

class BouncyCategorySheetContent extends StatefulWidget {
  final LocalRecord record;
  final LocalStorageService storage;

  const BouncyCategorySheetContent({
    super.key,
    required this.record,
    required this.storage,
  });

  @override
  State<BouncyCategorySheetContent> createState() => _BouncyCategorySheetContentState();
}

class _BouncyCategorySheetContentState extends State<BouncyCategorySheetContent> {
  bool _isBookmarked = false;
  late List<String> _assignedCategories;
  bool _isCreatingInline = false;
  final TextEditingController _newCatController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refreshAssigned();
  }

  void _refreshAssigned() {
    _isBookmarked = widget.storage.isBookmarked(widget.record.subjectId);
    final bookmarks = widget.storage.getBookmarks();
    final item = bookmarks.firstWhere(
      (e) => e.subjectId == widget.record.subjectId,
      orElse: () => widget.record,
    );
    _assignedCategories = List<String>.from(item.categories);
  }

  @override
  void dispose() {
    _newCatController.dispose();
    super.dispose();
  }

  Future<void> _toggleBookmarkStatus() async {
    HapticFeedback.mediumImpact();
    await widget.storage.toggleBookmark(
      subjectId: widget.record.subjectId,
      title: widget.record.title,
      coverUrl: widget.record.coverUrl,
      subjectType: widget.record.subjectType,
    );
    setState(() {
      _refreshAssigned();
    });
  }

  Future<void> _toggleCategory(String category) async {
    HapticFeedback.selectionClick();
    if (!_isBookmarked) {
      await widget.storage.toggleBookmark(
        subjectId: widget.record.subjectId,
        title: widget.record.title,
        coverUrl: widget.record.coverUrl,
        subjectType: widget.record.subjectType,
      );
    }
    await widget.storage.toggleItemCategory(widget.record.subjectId, category);
    setState(() {
      _refreshAssigned();
    });
  }

  Future<void> _createNewCategory() async {
    final name = _newCatController.text.trim();
    if (name.isEmpty) return;

    HapticFeedback.mediumImpact();
    await widget.storage.addMyListCategory(name);
    if (!_isBookmarked) {
      await widget.storage.toggleBookmark(
        subjectId: widget.record.subjectId,
        title: widget.record.title,
        coverUrl: widget.record.coverUrl,
        subjectType: widget.record.subjectType,
      );
    }
    await widget.storage.toggleItemCategory(widget.record.subjectId, name);
    _newCatController.clear();
    setState(() {
      _isCreatingInline = false;
      _refreshAssigned();
    });
  }

  Future<void> _removeRecord() async {
    HapticFeedback.heavyImpact();
    await widget.storage.removeBookmark(widget.record.subjectId);
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed "${widget.record.title}" from My List'),
          backgroundColor: AppTheme.bgCard,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final allCategories = widget.storage.getMyListCategories();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF14181F),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: AppTheme.borderSubtle, width: 1.2),
          left: BorderSide(color: AppTheme.borderSubtle, width: 1),
          right: BorderSide(color: AppTheme.borderSubtle, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 30,
            spreadRadius: 10,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Item Preview Header
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 46,
                      height: 64,
                      child: widget.record.coverUrl != null && widget.record.coverUrl!.startsWith('http')
                          ? CachedNetworkImage(
                              imageUrl: widget.record.coverUrl!,
                              fit: BoxFit.cover,
                              memCacheWidth: 140,
                              memCacheHeight: 192,
                              placeholder: (context, url) => Container(color: AppTheme.bgCard),
                              errorWidget: (context, url, error) => Container(
                                color: AppTheme.bgCard,
                                child: const Icon(Icons.movie, color: Colors.white38),
                              ),
                            )
                          : Container(
                              color: AppTheme.bgCard,
                              child: const Icon(Icons.movie, color: Colors.white38),
                            ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.record.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.bgCard,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppTheme.borderSubtle),
                              ),
                              child: Text(
                                widget.record.subjectType == 2 ? 'TV SERIES' : 'MOVIE',
                                style: TextStyle(
                                  color: AppTheme.accentGreen,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: _toggleBookmarkStatus,
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _isBookmarked
                                      ? AppTheme.accentGreen.withValues(alpha: 0.15)
                                      : Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: _isBookmarked ? AppTheme.accentGreen : Colors.white24,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _isBookmarked ? Icons.bookmark : Icons.bookmark_add_outlined,
                                      size: 12,
                                      color: _isBookmarked ? AppTheme.accentGreen : Colors.white70,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _isBookmarked ? 'In My List' : 'Add to My List',
                                      style: TextStyle(
                                        color: _isBookmarked ? AppTheme.accentGreen : Colors.white70,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_assignedCategories.length} categor${_assignedCategories.length == 1 ? 'y' : 'ies'}',
                              style: const TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white60),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            Divider(color: AppTheme.borderSubtle, height: 1),

            // Category Selection List
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'ADD TO CATEGORIES',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                      if (!_isCreatingInline)
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isCreatingInline = true;
                            });
                          },
                          child: Row(
                            children: [
                              Icon(Icons.add, color: AppTheme.accentGreen, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                'New Category',
                                style: TextStyle(
                                  color: AppTheme.accentGreen,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Inline Category Creation Input
                  if (_isCreatingInline) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.bgCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.6)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.label_outline, color: AppTheme.accentGreen, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _newCatController,
                              autofocus: true,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              decoration: const InputDecoration(
                                hintText: 'Category name...',
                                hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 14),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              onSubmitted: (_) => _createNewCategory(),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.check, color: AppTheme.accentGreen),
                            onPressed: _createNewCategory,
                            tooltip: 'Create and assign',
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                            onPressed: () {
                              _newCatController.clear();
                              setState(() => _isCreatingInline = false);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (allCategories.isEmpty && !_isCreatingInline)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Column(
                          children: [
                            const Icon(Icons.folder_open_outlined, color: Colors.white24, size: 42),
                            const SizedBox(height: 8),
                            const Text(
                              'No categories created yet',
                              style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton.icon(
                              onPressed: () => setState(() => _isCreatingInline = true),
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Create First Category'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.accentGreen,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Category checkboxes list
                  for (final category in allCategories) ...[
                    Builder(
                      builder: (context) {
                        final isAssigned = _assignedCategories.contains(category);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isAssigned
                                ? AppTheme.accentGreen.withValues(alpha: 0.12)
                                : AppTheme.bgCard.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isAssigned
                                  ? AppTheme.accentGreen.withValues(alpha: 0.6)
                                  : AppTheme.borderSubtle,
                              width: isAssigned ? 1.2 : 1.0,
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _toggleCategory(category),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Icon(
                                    isAssigned ? Icons.check_box : Icons.check_box_outline_blank,
                                    color: isAssigned ? AppTheme.accentGreen : Colors.white38,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      category,
                                      style: TextStyle(
                                        color: isAssigned ? Colors.white : Colors.white70,
                                        fontSize: 14,
                                        fontWeight: isAssigned ? FontWeight.w600 : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  if (isAssigned)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppTheme.accentGreen.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        'Added',
                                        style: TextStyle(
                                          color: AppTheme.accentGreen,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),

            Divider(color: AppTheme.borderSubtle, height: 1),

            // Bottom Actions: Remove from My List & Done
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  if (_isBookmarked) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _removeRecord,
                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                        label: const Text(
                          'Remove Item',
                          style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ] else ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _toggleBookmarkStatus,
                        icon: Icon(Icons.bookmark_add_outlined, size: 18, color: AppTheme.accentGreen),
                        label: Text(
                          'Add to My List',
                          style: TextStyle(color: AppTheme.accentGreen, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppTheme.accentGreen.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentGreen,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'Done',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
