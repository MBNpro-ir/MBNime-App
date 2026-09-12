import 'package:flutter/material.dart';
import '../services/device_bridge.dart';

Future<void> showWirelessDisplaySheet(
  BuildContext context, {
  required Future<void> Function() onCast,
  required Future<void> Function() onPlay,
}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const BackButtonIcon(),
                label: const Text('بازگشت'),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'تلویزیون یا مانیتور بدون سیم',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.connected_tv),
              title: const Text('پخش مستقیم روی تلویزیون'),
              subtitle: const Text(
                'Chromecast / DLNA و دستگاه‌های پشتیبانی‌شده',
              ),
              onTap: () => Navigator.pop(context, 'cast'),
            ),
            ListTile(
              leading: const Icon(Icons.screen_share),
              title: const Text('Wireless Display / Miracast'),
              subtitle: const Text(
                'اتصال نمایشگر از تنظیمات دستگاه و نمایش پلیر داخلی',
              ),
              onTap: () => Navigator.pop(context, 'wireless'),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Text(
                'Wireless Display را روی نمایشگر روشن کن. این روش به پشتیبانی سخت‌افزار و سیستم‌عامل نیاز دارد و ممکن است کل صفحه و اعلان‌های دستگاه را نمایش دهد. در بعضی گوشی‌ها Miracast پشتیبانی نمی‌شود.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'cast') {
    await onCast();
    return;
  }
  try {
    if (!await DeviceBridge.wirelessDisplay()) throw StateError('unsupported');
    if (!context.mounted) return;
    final play = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اتصال نمایشگر'),
        content: const Text(
          'نمایشگر را در پنجرهٔ اتصال سیستم انتخاب کن. پس از اتصال، پخش داخلی را شروع کن. در Windows برای نمایش یکسان صفحه‌ها می‌توانی از Win+P و گزینهٔ Duplicate استفاده کنی.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('بعداً'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('شروع پخش داخلی'),
          ),
        ],
      ),
    );
    if (play == true) await onPlay();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'پنجرهٔ اتصال باز نشد. از تنظیمات Cast گوشی یا Win+K در Windows استفاده کن؛ دستگاه باید Miracast را پشتیبانی کند.',
          ),
        ),
      );
    }
  }
}
