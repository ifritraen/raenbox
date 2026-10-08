import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

enum Anime4kMode {
  off,
  modeA,
  modeB,
  modeC,
  modeAA,
  modeBB,
  modeCA;

  String get label {
    switch (this) {
      case Anime4kMode.off:
        return 'Off';
      case Anime4kMode.modeA:
        return 'Mode A';
      case Anime4kMode.modeB:
        return 'Mode B';
      case Anime4kMode.modeC:
        return 'Mode C';
      case Anime4kMode.modeAA:
        return 'Mode A+A';
      case Anime4kMode.modeBB:
        return 'Mode B+B';
      case Anime4kMode.modeCA:
        return 'Mode C+A';
    }
  }

  String get description {
    switch (this) {
      case Anime4kMode.off:
        return 'Original Video Output';
      case Anime4kMode.modeA:
        return 'Reconstruct Lines & Sharpen';
      case Anime4kMode.modeB:
        return 'Soft Line Clarity & Upscale';
      case Anime4kMode.modeC:
        return 'Denoise + Edge Upscale';
      case Anime4kMode.modeAA:
        return 'Double Line Reconstruction';
      case Anime4kMode.modeBB:
        return 'Double Soft Reconstruction';
      case Anime4kMode.modeCA:
        return 'Denoise + Line Reconstruction';
    }
  }

  String toKey() => name;

  static Anime4kMode fromKey(String? key) {
    if (key == null) return Anime4kMode.off;
    return Anime4kMode.values.firstWhere(
      (e) => e.name.toLowerCase() == key.toLowerCase(),
      orElse: () => Anime4kMode.off,
    );
  }
}

enum Anime4kQuality {
  fast,
  hq;

  String get label {
    switch (this) {
      case Anime4kQuality.fast:
        return 'Fast (Mid-End)';
      case Anime4kQuality.hq:
        return 'Quality / HQ (High-End)';
    }
  }

  String toKey() => name;

  static Anime4kQuality fromKey(String? key) {
    if (key == null) return Anime4kQuality.fast;
    return Anime4kQuality.values.firstWhere(
      (e) => e.name.toLowerCase() == key.toLowerCase(),
      orElse: () => Anime4kQuality.fast,
    );
  }
}

class PlayerShaders {
  static const Map<String, List<String>> _fastShaderPipelines = {
    'modeA': [
      'Anime4K_Clamp_Highlights.glsl',
      'Anime4K_Restore_CNN_M.glsl',
      'Anime4K_Upscale_CNN_x2_M.glsl',
    ],
    'modeB': [
      'Anime4K_Clamp_Highlights.glsl',
      'Anime4K_Restore_CNN_Soft_M.glsl',
      'Anime4K_Upscale_CNN_x2_M.glsl',
    ],
    'modeC': [
      'Anime4K_Clamp_Highlights.glsl',
      'Anime4K_Upscale_Denoise_CNN_x2_M.glsl',
    ],
    'modeAA': [
      'Anime4K_Clamp_Highlights.glsl',
      'Anime4K_Restore_CNN_M.glsl',
      'Anime4K_Upscale_CNN_x2_M.glsl',
      'Anime4K_AutoDownscalePre_x2.glsl',
      'Anime4K_Restore_CNN_S.glsl',
      'Anime4K_Upscale_CNN_x2_S.glsl',
    ],
    'modeBB': [
      'Anime4K_Clamp_Highlights.glsl',
      'Anime4K_Restore_CNN_Soft_M.glsl',
      'Anime4K_Upscale_CNN_x2_M.glsl',
      'Anime4K_AutoDownscalePre_x2.glsl',
      'Anime4K_Restore_CNN_Soft_S.glsl',
      'Anime4K_Upscale_CNN_x2_S.glsl',
    ],
    'modeCA': [
      'Anime4K_Clamp_Highlights.glsl',
      'Anime4K_Upscale_Denoise_CNN_x2_M.glsl',
      'Anime4K_AutoDownscalePre_x2.glsl',
      'Anime4K_Restore_CNN_S.glsl',
      'Anime4K_Upscale_CNN_x2_S.glsl',
    ],
  };

  static const Map<String, List<String>> _hqShaderPipelines = {
    'modeA': [
      'Anime4K_Clamp_Highlights.glsl',
      'Anime4K_Restore_CNN_M.glsl',
      'Anime4K_Upscale_CNN_x2_M.glsl',
      'Anime4K_AutoDownscalePre_x2.glsl',
      'Anime4K_Upscale_CNN_x2_M.glsl',
    ],
    'modeB': [
      'Anime4K_Clamp_Highlights.glsl',
      'Anime4K_Restore_CNN_Soft_M.glsl',
      'Anime4K_Upscale_CNN_x2_M.glsl',
      'Anime4K_AutoDownscalePre_x2.glsl',
      'Anime4K_Upscale_CNN_x2_M.glsl',
    ],
    'modeC': [
      'Anime4K_Clamp_Highlights.glsl',
      'Anime4K_Upscale_Denoise_CNN_x2_M.glsl',
      'Anime4K_AutoDownscalePre_x2.glsl',
      'Anime4K_Upscale_CNN_x2_M.glsl',
    ],
    'modeAA': [
      'Anime4K_Clamp_Highlights.glsl',
      'Anime4K_Restore_CNN_M.glsl',
      'Anime4K_Upscale_CNN_x2_M.glsl',
      'Anime4K_AutoDownscalePre_x2.glsl',
      'Anime4K_Restore_CNN_M.glsl',
      'Anime4K_Upscale_CNN_x2_M.glsl',
    ],
    'modeBB': [
      'Anime4K_Clamp_Highlights.glsl',
      'Anime4K_Restore_CNN_Soft_M.glsl',
      'Anime4K_Upscale_CNN_x2_M.glsl',
      'Anime4K_AutoDownscalePre_x2.glsl',
      'Anime4K_Restore_CNN_Soft_M.glsl',
      'Anime4K_Upscale_CNN_x2_M.glsl',
    ],
    'modeCA': [
      'Anime4K_Clamp_Highlights.glsl',
      'Anime4K_Upscale_Denoise_CNN_x2_M.glsl',
      'Anime4K_AutoDownscalePre_x2.glsl',
      'Anime4K_Restore_CNN_M.glsl',
      'Anime4K_Upscale_CNN_x2_M.glsl',
    ],
  };

  static String? _cachedShaderDir;
  static bool _isExtracting = false;

  /// Returns the directory path where Anime4K .glsl shaders are stored
  static Future<String> getShaderBasePath() async {
    if (_cachedShaderDir != null) return _cachedShaderDir!;
    final docs = await getApplicationDocumentsDirectory();
    final shaderDir = Directory('${docs.path}/RaenBox/mpv/Shaders');
    if (!await shaderDir.exists()) {
      await shaderDir.create(recursive: true);
    }
    _cachedShaderDir = '${shaderDir.path}/';
    return _cachedShaderDir!;
  }

  /// Extracts bundled Anime4K shaders from assets if not already installed
  static Future<void> ensureShadersReady() async {
    if (_isExtracting) return;
    _isExtracting = true;
    try {
      final basePath = await getShaderBasePath();
      final testFile = File('${basePath}Anime4K_Clamp_Highlights.glsl');
      if (await testFile.exists()) {
        _isExtracting = false;
        return;
      }

      debugPrint('[Anime4K] Extracting bundled shaders to $basePath');
      final ByteData assetData = await rootBundle.load('assets/shaders/shaders_new.zip');
      final Uint8List bytes = assetData.buffer.asUint8List(
        assetData.offsetInBytes,
        assetData.lengthInBytes,
      );

      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive) {
        if (file.isFile) {
          final outFile = File('$basePath${file.name}');
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        }
      }
      debugPrint('[Anime4K] Extracted ${archive.length} shader files successfully.');
    } catch (e) {
      debugPrint('[Anime4K] Error extracting shaders: $e');
    } finally {
      _isExtracting = false;
    }
  }

  /// Applies the selected Anime4K shader pipeline to the native libmpv player
  static Future<void> applyShader({
    required dynamic player,
    required Anime4kMode mode,
    required Anime4kQuality quality,
  }) async {
    if (player == null || player.platform == null) return;
    final mpv = player.platform as dynamic;

    if (mode == Anime4kMode.off) {
      try {
        await mpv.setProperty('glsl-shaders', '');
        debugPrint('[Anime4K] Shaders cleared (Off)');
      } catch (e) {
        debugPrint('[Anime4K] Error clearing shaders: $e');
      }
      return;
    }

    await ensureShadersReady();
    final basePath = await getShaderBasePath();

    final pipelines = quality == Anime4kQuality.hq
        ? _hqShaderPipelines
        : _fastShaderPipelines;

    final shaderList = pipelines[mode.name] ?? [];
    if (shaderList.isEmpty) return;

    final separator = Platform.isWindows ? ';' : ':';
    final fullPaths = shaderList.map((f) => '$basePath$f').join(separator);

    try {
      await mpv.setProperty('glsl-shaders', fullPaths);
      debugPrint('[Anime4K] Applied ${mode.label} (${quality.label}) with ${shaderList.length} shaders');
    } catch (e) {
      debugPrint('[Anime4K] Error setting glsl-shaders: $e');
    }
  }

  /// Sets MPV hardware color adjustments (-100 to 100)
  static Future<void> setHardwareColorSettings({
    required dynamic player,
    int brightness = 0,
    int contrast = 0,
    int saturation = 0,
    int gamma = 0,
    int hue = 0,
  }) async {
    if (player == null || player.platform == null) return;
    final mpv = player.platform as dynamic;

    try {
      await mpv.setProperty('brightness', brightness.clamp(-100, 100).toString());
      await mpv.setProperty('contrast', contrast.clamp(-100, 100).toString());
      await mpv.setProperty('saturation', saturation.clamp(-100, 100).toString());
      await mpv.setProperty('gamma', gamma.clamp(-100, 100).toString());
      await mpv.setProperty('hue', hue.clamp(-100, 100).toString());
    } catch (e) {
      debugPrint('[ColorSettings] Error setting MPV color properties: $e');
    }
  }

  /// Applies low-level MPV performance optimizations:
  /// - Direct hardware decoding (mediacodec) on Android for zero-copy frame pipeline
  /// - Lavc fast decode and loop-filter skipping on non-keyframes to free GPU bandwidth
  /// - Multi-threaded decode and frame-drop prevention
  static Future<void> applyPerformanceProperties(dynamic player) async {
    if (player == null || player.platform == null) return;
    final mpv = player.platform as dynamic;

    try {
      if (Platform.isAndroid) {
        await mpv.setProperty('hwdec', 'mediacodec-copy');
      }
      await mpv.setProperty('vd-lavc-fast', 'yes');
      await mpv.setProperty('vd-lavc-skiploopfilter', 'nonkey');
      await mpv.setProperty('vd-lavc-threads', '4');
      await mpv.setProperty('hr-seek', 'always');
      await mpv.setProperty('hr-seek-framedrop', 'no');
      await mpv.setProperty('cache', 'yes');
      await mpv.setProperty('cache-secs', '120');
      await mpv.setProperty('demuxer-readahead-secs', '60');
      await mpv.setProperty('demuxer-max-bytes', '64MiB');
      await mpv.setProperty('demuxer-max-back-bytes', '32MiB');
      await mpv.setProperty('slang', 'en,eng,English,enUS,en-US,enGB,en-GB');
      await mpv.setProperty('subs-fallback', 'no');
      await mpv.setProperty('volume-max', '300');
      debugPrint('[MPV] Low-level performance properties applied successfully');
    } catch (e) {
      debugPrint('[MPV] Error applying performance properties: $e');
    }
  }
}
