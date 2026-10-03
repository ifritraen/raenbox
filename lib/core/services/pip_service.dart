import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PipService {
  static const MethodChannel _channel = MethodChannel('com.raen.raenbox/pip');
  static final ValueNotifier<bool> inPipNotifier = ValueNotifier<bool>(false);
  static bool _isInitialized = false;

  static VoidCallback? onPauseRequested;

  static void init() {
    if (_isInitialized) return;
    _isInitialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPiPChanged') {
        final bool inPip = call.arguments as bool? ?? false;
        inPipNotifier.value = inPip;
      } else if (call.method == 'pauseOnHomePiP') {
        onPauseRequested?.call();
      }
    });
  }

  /// Request the system to enter Picture-in-Picture mode on Android
  static Future<bool> enterPiP({int numerator = 16, int denominator = 9}) async {
    if (!Platform.isAndroid) return false;
    init();
    try {
      final res = await _channel.invokeMethod<bool>('enterPiP', {
        'numerator': numerator,
        'denominator': denominator,
      });
      final entered = res ?? false;
      if (entered) {
        inPipNotifier.value = true;
      }
      return entered;
    } catch (_) {
      return false;
    }
  }

  /// Enable or disable automatic system OS PiP when user leaves app
  static Future<void> setAutoPiPEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    init();
    try {
      await _channel.invokeMethod('setAutoPiPEnabled', {'enabled': enabled});
    } catch (_) {}
  }

  /// Checks if Picture-in-Picture is supported on the current device
  static Future<bool> isPiPSupported() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('isPiPSupported');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Checks if currently in PiP mode
  static Future<bool> isInPiP() async {
    if (!Platform.isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('isInPiP');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}
