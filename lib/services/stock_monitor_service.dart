import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

class StockMonitorService {
  static const MethodChannel _channel = MethodChannel(
    'com.example.tracx/stock_monitor',
  );

  static Future<bool> start() async {
    if (!Platform.isAndroid) return false;

    final permission = await Permission.notification.request();
    if (!permission.isGranted) {
      return false;
    }

    final result = await _channel.invokeMethod<bool>('start');
    return result ?? false;
  }

  static Future<bool> stop() async {
    if (!Platform.isAndroid) return false;
    final result = await _channel.invokeMethod<bool>('stop');
    return result ?? false;
  }

  static Future<bool> isRunning() async {
    if (!Platform.isAndroid) return false;
    final result = await _channel.invokeMethod<bool>('isRunning');
    return result ?? false;
  }
}
