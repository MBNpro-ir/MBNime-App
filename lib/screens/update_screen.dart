import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_updater.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();
final appMessengerKey = GlobalKey<ScaffoldMessengerState>();

Future<String?> showInstallPermissionPrompt(
  BuildContext context,
) => showDialog<String>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('اجازهٔ نصب لازم است'),
    content: const Text(
      'برای نصب بروزرسانی، گزینهٔ «اجازه از این منبع» را برای MBNime فعال کن و به برنامه برگرد. فایل دانلودشده محفوظ است. می‌توانی دوباره اجازه بدهی یا از گیت‌هاب دستی دانلود کنی.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('بعداً'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, 'github'),
        child: const Text('دانلود از گیت‌هاب'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, 'retry'),
        child: const Text('درخواست دوباره'),
      ),
    ],
  ),
);

Future<void> _installUpdate(BuildContext context, AppUpdater updater) async {
  do {
    await updater.install();
    if (!context.mounted || !updater.installationPermissionRequired) return;
    final choice = await showInstallPermissionPrompt(context);
    if (!context.mounted) return;
    if (choice == 'retry') continue;
    if (choice == 'github') await _openRelease(context);
    return;
  } while (context.mounted);
}

Future<void> _openRelease(BuildContext context) async {
  try {
    if (await launchUrl(
      Uri.https('github.com', '/${AppUpdater.repository}/releases/latest'),
      mode: LaunchMode.externalApplication,
    )) {
      return;
    }
  } catch (_) {}
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'مرورگر باز نشد. آدرس: github.com/MBNpro-ir/MBNime-App/releases/latest',
        ),
      ),
    );
  }
}

class UpdatePresentation {
  static String? _prompted;
  static bool _announced = false;
  static bool _dialog = false;
  static void start() {
    AppUpdater.instance.addListener(_changed);
    unawaited(AppUpdater.instance.initialize());
  }

  static void _changed() {
    final updater = AppUpdater.instance;
    if (updater.phase == UpdatePhase.downloading && !_announced) {
      _announced = true;
      appMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text(
            '✨ نسخهٔ جدید پیدا شد؛ بروزرسانی خودکار در حال دانلود است.',
          ),
          duration: Duration(seconds: 8),
        ),
      );
    }
    final context = appNavigatorKey.currentContext;
    if (context == null || _dialog) return;
    if (updater.installedNotes != null) {
      final notes = updater.installedNotes!;
      updater.installedNotes = null;
      _dialog = true;
      unawaited(
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('🎉 به نسخهٔ ${updater.currentVersion} بروز شدی'),
            content: SingleChildScrollView(
              child: SelectableText(
                notes.isEmpty ? 'برنامه با موفقیت بروزرسانی شد.' : notes,
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('عالیه'),
              ),
            ],
          ),
        ).whenComplete(() {
          _dialog = false;
          _changed();
        }),
      );
    } else if (updater.phase == UpdatePhase.ready &&
        _prompted != updater.release?.version.toString()) {
      _prompted = updater.release!.version.toString();
      _dialog = true;
      unawaited(
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              '📦 بروزرسانی ${updater.release!.version} آمادهٔ نصب است',
            ),
            content: const Text(
              'فایل دانلود و بررسی شد. می‌توانی الان نصب کنی یا بعداً از منوی بروزرسانی برگردی.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('بعداً'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  appNavigatorKey.currentState?.push(
                    MaterialPageRoute<void>(
                      builder: (_) => const UpdateScreen(),
                    ),
                  );
                },
                child: const Text('مشاهده و نصب'),
              ),
            ],
          ),
        ).whenComplete(() => _dialog = false),
      );
    }
  }
}

class UpdateScreen extends StatelessWidget {
  const UpdateScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('بروزرسانی برنامه')),
    body: ListenableBuilder(
      listenable: AppUpdater.instance,
      builder: (context, _) {
        final updater = AppUpdater.instance;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Icon(Icons.system_update_alt, size: 64),
                const SizedBox(height: 20),
                Text(
                  'نسخهٔ نصب‌شده: ${updater.currentVersion}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(switch (updater.phase) {
                  UpdatePhase.idle => 'نسخهٔ جدیدتری پیدا نشد.',
                  UpdatePhase.checking => 'در حال بررسی آخرین انتشار…',
                  UpdatePhase.downloading =>
                    'در حال دانلود نسخهٔ ${updater.release?.version}…',
                  UpdatePhase.ready => '✅ دانلود کامل شد و صحت فایل تأیید شد.',
                  UpdatePhase.installing =>
                    'در حال آماده‌سازی نصب؛ لطفاً صبر کن…',
                  UpdatePhase.failed => 'بررسی بروزرسانی کامل نشد.',
                }),
                if ([
                  UpdatePhase.checking,
                  UpdatePhase.downloading,
                  UpdatePhase.installing,
                ].contains(updater.phase)) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: updater.phase == UpdatePhase.downloading
                        ? updater.progress
                        : null,
                  ),
                ],
                if (updater.error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      updater.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (updater.release != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    'تازه‌های نسخهٔ ${updater.release!.version}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  SelectableText(updater.release!.notes),
                ],
                const SizedBox(height: 24),
                if (updater.phase == UpdatePhase.ready)
                  FilledButton.icon(
                    onPressed: () async {
                      final accepted = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('نصب بروزرسانی؟'),
                          content: const Text(
                            'در Windows برنامه بسته و پس از بروزرسانی دوباره باز می‌شود. دانلودهای جاری را ابتدا متوقف کن. در Android تأیید نصب سیستم نمایش داده می‌شود.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('انصراف'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('آپدیت کن'),
                            ),
                          ],
                        ),
                      );
                      if (accepted == true && context.mounted) {
                        await _installUpdate(context, updater);
                      }
                    },
                    icon: const Icon(Icons.install_desktop),
                    label: const Text('نصب بروزرسانی'),
                  ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => _openRelease(context),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('دانلود دستی از گیت‌هاب'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      [
                        UpdatePhase.checking,
                        UpdatePhase.downloading,
                        UpdatePhase.installing,
                      ].contains(updater.phase)
                      ? null
                      : updater.check,
                  icon: const Icon(Icons.refresh),
                  label: const Text('بررسی دوباره'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
