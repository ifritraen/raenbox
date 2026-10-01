import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/moviebox_models.dart';
import '../../data/services/download_service.dart';
import '../../data/services/local_storage_service.dart';
import '../../data/services/moviebox_api_service.dart';
import '../player/player_screen.dart';

class DownloadsScreen extends StatefulWidget {
  final LocalStorageService storage;
  final DownloadService downloadService;
  final MovieBoxApiService apiService;

  const DownloadsScreen({
    super.key,
    required this.storage,
    required this.downloadService,
    required this.apiService,
  });

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    widget.downloadService.addListener(_onDownloadUpdate);
    widget.storage.addListener(_onDownloadUpdate);
  }

  void _onDownloadUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.downloadService.removeListener(_onDownloadUpdate);
    widget.storage.removeListener(_onDownloadUpdate);
    _tabController.dispose();
    super.dispose();
  }

  void _playOffline(LocalRecord record) {
    if (record.downloadPath == null) return;
    final file = File(record.downloadPath!);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File not found on device.')),
      );
      return;
    }

    final stream = StreamLink(
      id: record.subjectId,
      format: 'MP4',
      resolutions: 'Local File',
      url: 'file://${record.downloadPath!}',
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          subjectId: record.subjectId,
          title: record.title,
          coverUrl: record.coverUrl,
          subjectType: record.subjectType,
          initialStream: stream,
          allStreams: [stream],
          apiService: widget.apiService,
          offlineAudioPath: record.audioDownloadPath,
        ),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final activeTasks = widget.downloadService.tasks;
    final completed = widget.storage.getDownloads();

    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        title: const Text(
          'Downloads',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.bgPrimary,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.accentGreen,
          labelColor: Colors.white,
          unselectedLabelColor: AppTheme.textMuted,
          tabs: [
            Tab(text: 'Active (${activeTasks.length})'),
            Tab(text: 'Downloaded (${completed.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Active Tasks Tab
          activeTasks.isEmpty
              ? const Center(
                  child: Text(
                    'No active downloads',
                    style: TextStyle(color: AppTheme.textMuted),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: activeTasks.length,
                  itemBuilder: (context, index) {
                    final task = activeTasks[index];
                    final isDownloading = task.status == DownloadStatus.downloading;
                    final isPending = task.status == DownloadStatus.pending;
                    final isPaused = task.status == DownloadStatus.paused;
                    final isFailed = task.status == DownloadStatus.failed;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.bgCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDownloading
                              ? AppTheme.accentGreen.withValues(alpha: 0.3)
                              : AppTheme.borderSubtle,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Cover thumbnail
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: task.coverUrl != null && task.coverUrl!.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: task.coverUrl!,
                                        width: 44,
                                        height: 62,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, _, _) => Container(
                                          width: 44,
                                          height: 62,
                                          color: AppTheme.bgSurface,
                                          child: const Icon(Icons.movie_outlined,
                                              color: AppTheme.textMuted, size: 22),
                                        ),
                                      )
                                    : Container(
                                        width: 44,
                                        height: 62,
                                        color: AppTheme.bgSurface,
                                        child: const Icon(Icons.movie_outlined,
                                            color: AppTheme.textMuted, size: 22),
                                      ),
                              ),
                              const SizedBox(width: 12),
                              // Title & quality
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      task.displayTitle,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppTheme.accentCyan.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '${task.quality}p HD',
                                            style: TextStyle(
                                                color: AppTheme.accentCyan, fontSize: 10),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (task.activeThreads > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 5, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppTheme.accentGreen.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              '⚡ ${task.activeThreads} th',
                                              style: TextStyle(
                                                color: AppTheme.accentGreen,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    if (task.errorMessage != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        task.errorMessage!,
                                        style: const TextStyle(
                                            color: Colors.redAccent, fontSize: 11),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              // Pause / Resume & Cancel Buttons
                              if (isDownloading)
                                IconButton(
                                  icon: const Icon(Icons.pause_rounded,
                                      color: Colors.white70, size: 20),
                                  onPressed: () => widget.downloadService.pauseDownload(task.id),
                                )
                              else if (isPaused || isFailed)
                                IconButton(
                                  icon: Icon(Icons.play_arrow_rounded,
                                      color: AppTheme.accentGreen, size: 22),
                                  onPressed: () => widget.downloadService.resumeDownload(task.id),
                                ),
                              IconButton(
                                icon: const Icon(Icons.close, color: AppTheme.textMuted, size: 18),
                                onPressed: () => widget.downloadService.removeTask(task.id),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          LinearProgressIndicator(
                            value: task.totalChunks > 0
                                ? (task.currentChunkIndex / task.totalChunks).clamp(0.0, 1.0)
                                : task.progress,
                            backgroundColor: AppTheme.bgSurface,
                            color: isFailed
                                ? Colors.redAccent
                                : isPaused
                                    ? Colors.amber
                                    : AppTheme.accentGreen,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '${(task.progress * 100).toStringAsFixed(1)}%',
                                    style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  if (task.formattedSize.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      '• ${task.formattedSize}',
                                      style: const TextStyle(
                                          color: AppTheme.textMuted, fontSize: 11),
                                    ),
                                  ],
                                ],
                              ),
                              Text(
                                isDownloading
                                    ? (task.formattedSpeed.isNotEmpty
                                        ? '${task.formattedSpeed} • Downloading'
                                        : 'Downloading...')
                                    : isPending
                                        ? 'Queued'
                                        : isPaused
                                            ? 'Paused'
                                            : isFailed
                                                ? 'Failed'
                                                : 'Completed',
                                style: TextStyle(
                                  color: isDownloading
                                      ? AppTheme.accentGreen
                                      : isFailed
                                          ? Colors.redAccent
                                          : isPaused
                                              ? Colors.amber
                                              : AppTheme.textSecondary,
                                  fontSize: 11,
                                  fontWeight: isDownloading ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),

          // Downloaded Videos Tab
          completed.isEmpty
              ? const Center(
                  child: Text(
                    'No downloaded movies yet',
                    style: TextStyle(color: AppTheme.textMuted),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: completed.length,
                  itemBuilder: (context, index) {
                    final item = completed[index];
                    int fileSize = 0;
                    if (item.downloadPath != null) {
                      final f = File(item.downloadPath!);
                      if (f.existsSync()) fileSize = f.lengthSync();
                    }

                    return Container(
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
                            child: item.coverUrl != null && item.coverUrl!.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: item.coverUrl!,
                                    width: 50,
                                    height: 70,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, _, _) => Container(
                                      width: 50,
                                      height: 70,
                                      color: AppTheme.bgSurface,
                                      child: Icon(Icons.play_circle_fill,
                                          color: AppTheme.accentGreen, size: 32),
                                    ),
                                  )
                                : Container(
                                    width: 50,
                                    height: 70,
                                    color: AppTheme.bgSurface,
                                    child: Icon(Icons.play_circle_fill,
                                        color: AppTheme.accentGreen, size: 32),
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
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      'Offline Playback',
                                      style: TextStyle(
                                          color: AppTheme.accentGreen, fontSize: 11),
                                    ),
                                    if (fileSize > 0) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        '• ${_formatFileSize(fileSize)}',
                                        style: const TextStyle(
                                            color: AppTheme.textMuted, fontSize: 11),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.play_arrow_rounded,
                                color: AppTheme.accentGreen, size: 28),
                            onPressed: () => _playOffline(item),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: AppTheme.textMuted, size: 20),
                            onPressed: () =>
                                widget.downloadService.removeTask(item.subjectId),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }
}
