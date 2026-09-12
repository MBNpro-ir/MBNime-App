import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'screens/update_screen.dart';
import 'services/download_manager.dart';
import 'services/device_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  DeviceBridge.initialize();
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1440, 900),
      minimumSize: Size(1000, 650),
      center: true,
      backgroundColor: Color(0xFF080A0F),
      title: 'MBNime',
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  } else {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }
  runApp(const MbnimeApp());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    UpdatePresentation.start();
    DownloadManager.instance.initialize().catchError((Object error) {
      DownloadManager.instance.error = 'راه‌اندازی دانلودها انجام نشد.';
    });
  });
}
