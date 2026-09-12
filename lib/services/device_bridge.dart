import 'dart:io';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class DeviceBridge {
  static const channel = MethodChannel('com.mbn.ime/device');
  static Future<bool> wirelessDisplay() async {
    if (Platform.isAndroid) {
      return await channel.invokeMethod<bool>('wirelessDisplay') ?? false;
    }
    if (Platform.isWindows) {
      return await channel.invokeMethod<bool>('wirelessDisplay') ?? false;
    }
    return false;
  }

  static Future<String> updatePlatform() async => Platform.isWindows
      ? 'Windows-x64'
      : 'Android-${await channel.invokeMethod<String>('abi')}';
  static Future<bool> storageGranted() async =>
      !Platform.isAndroid ||
      await channel.invokeMethod<bool>('storageGranted') == true;
  static Future<void> requestStorage() =>
      channel.invokeMethod<void>('requestStorage');
  static Future<String> downloadsDirectory() async =>
      (await channel.invokeMethod<String>('downloadsDirectory'))!;
  static Future<String> installApk(String path) async =>
      await channel.invokeMethod<String>('installApk', {'path': path}) ??
      'failed';
  static Future<void> openFolder(String path) async {
    if (Platform.isWindows) {
      await Directory(path).create(recursive: true);
      await Process.start('explorer.exe', [
        path,
      ], mode: ProcessStartMode.detached);
    } else if (Platform.isAndroid) {
      if (await channel.invokeMethod<bool>('openDownloads') != true) {
        throw const FileSystemException('برنامهٔ مدیریت فایل پیدا نشد');
      }
    } else {
      if (!await launchUrl(
        Uri.directory(path),
        mode: LaunchMode.externalApplication,
      )) {
        throw const FileSystemException('پوشه باز نشد');
      }
    }
  }
}
