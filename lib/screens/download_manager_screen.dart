import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';
import '../services/download_manager.dart';
import '../services/device_bridge.dart';
import '../services/external_apps.dart';
import '../models/anime_content.dart';
import '../widgets/download_playback_sheet.dart';
import 'detail_screen.dart';

class DownloadManagerScreen extends StatefulWidget {
  const DownloadManagerScreen({super.key, this.initializeDownloads});
  final Future<void> Function()? initializeDownloads;
  @override
  State<DownloadManagerScreen> createState() => _DownloadManagerScreenState();
}

class _DownloadManagerScreenState extends State<DownloadManagerScreen> {
  final manager = DownloadManager.instance;
  String _search = '';
  String _filter = 'همه';
  @override
  void initState() {
    super.initState();
    unawaited(
      _action(() async {
        await (widget.initializeDownloads?.call() ?? manager.initialize());
        return true;
      }),
    );
  }

  Future<void> _play(Task task) async {
    final path = await task.filePath();
    if (!mounted) return;
    if (!await File(path).exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('فایل پیدا نشد؛ ممکن است جابه‌جا یا حذف شده باشد.'),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    final choice = await showDownloadPlaybackSheet(context);
    if (choice == null || !mounted) return;
    if (choice == 'internal') {
      Map<String, dynamic> metadata = {};
      try {
        metadata = Map<String, dynamic>.from(jsonDecode(task.metaData) as Map);
      } catch (_) {}
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlayerScreen(
            content: AnimeContent(
              id: metadata['contentId'] as String? ?? 'download-${task.taskId}',
              title: metadata['title'] as String? ?? task.displayName,
              subtitle: '',
              description: '',
              year: 0,
              rating: 0,
              kind: ContentKind.movie,
              colors: const [],
              genres: const [],
            ),
            episode: AnimeEpisode(
              id: metadata['episodeId'] as String? ?? task.taskId,
              name: metadata['episode'] as String? ?? task.displayName,
              fileUrl: Uri.file(path).toString(),
            ),
          ),
        ),
      );
    } else {
      final player = ExternalVideoPlayer.values.byName(choice);
      final result = await ExternalApps.playLocalVideo(
        player: player,
        path: path,
        title: task.displayName,
      );
      if (!mounted || result == ExternalLaunchResult.launched) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result == ExternalLaunchResult.missing
                ? '${ExternalApps.playerName(player)} نصب نیست؛ پلیر داخلی را انتخاب کن یا آن را نصب کن.'
                : 'فایل در پلیر خارجی باز نشد؛ پلیر داخلی را امتحان کن.',
          ),
        ),
      );
    }
  }

  Future<void> _action(Future<bool> Function() operation) async {
    try {
      final success = await operation();
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'این عملیات انجام نشد؛ ممکن است سرور ادامهٔ دانلود را پشتیبانی نکند. دوباره تلاش کن.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'عملیات دانلود انجام نشد؛ دسترسی، اینترنت و فضای خالی را بررسی کن.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('مدیریت دانلود ها'),
      actions: [
        IconButton(
          tooltip: 'باز کردن پوشهٔ دانلود',
          icon: const Icon(Icons.folder_open),
          onPressed: () => _action(() async {
            await DeviceBridge.openFolder(await manager.rootDirectory());
            return true;
          }),
        ),
      ],
    ),
    body: ListenableBuilder(
      listenable: manager,
      builder: (context, _) {
        final records =
            manager.records.values
                .where(
                  (r) =>
                      r.task.displayName.toLowerCase().contains(
                        _search.toLowerCase(),
                      ) &&
                      (_filter == 'همه' ||
                          _filter == downloadStatusLabel(r.status)),
                )
                .toList()
              ..sort(
                (a, b) => b.task.creationTime.compareTo(a.task.creationTime),
              );
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'جست‌وجو در دانلودها',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) => setState(() => _search = value),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.start,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilterChip(
                          label: const Text('دانلودهای جدید فقط با Wi‑Fi'),
                          selected: manager.wifiOnly,
                          onSelected: (value) => _action(() async {
                            await manager.settings(wifi: value);
                            return true;
                          }),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('هم‌زمان: '),
                            DropdownButton<int>(
                              value: manager.concurrency,
                              items: [
                                for (var i = 1; i <= 4; i++)
                                  DropdownMenuItem(value: i, child: Text('$i')),
                              ],
                              onChanged: (value) => _action(() async {
                                await manager.settings(simultaneous: value);
                                return true;
                              }),
                            ),
                          ],
                        ),
                        DropdownButton<String>(
                          value: _filter,
                          items: [
                            for (final value in [
                              'همه',
                              'در صف',
                              'در حال دانلود',
                              'متوقف',
                              'تکمیل‌شده',
                              'ناموفق',
                              'لغوشده',
                            ])
                              DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _filter = value!),
                        ),
                        TextButton(
                          onPressed: () => _action(() async {
                            await manager.pauseAll();
                            return true;
                          }),
                          child: const Text('توقف همه'),
                        ),
                        TextButton(
                          onPressed: () => _action(() async {
                            await manager.resumeAll();
                            return true;
                          }),
                          child: const Text('ادامهٔ همه'),
                        ),
                        TextButton(
                          onPressed: () => _action(() async {
                            await manager.clearFinished();
                            return true;
                          }),
                          child: const Text('پاک‌کردن سوابق تکمیل‌شده'),
                        ),
                      ],
                    ),
                    const Text(
                      'پوشه‌ها: Downloads/MBNime → Movies / Series / Anime → Title → Season\nپاک‌کردن سوابق، فایل‌ها را حذف نمی‌کند.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            if (records.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'دانلودی در این بخش نیست. از صفحهٔ قسمت‌ها دانلود داخلی را انتخاب کن.',
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverList.builder(
                  itemCount: records.length,
                  itemBuilder: (context, index) {
                    final record = records[index];
                    final task = record.task;
                    final progress = manager.progress[task.taskId];
                    String cover = '';
                    try {
                      cover =
                          (jsonDecode(task.metaData) as Map)['coverPath']
                              as String? ??
                          '';
                    } catch (_) {}
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (cover.isNotEmpty)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  end: 12,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    File(cover),
                                    width: 52,
                                    height: 76,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        const Icon(Icons.movie),
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    task.displayName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(
                                    value: record.progress.clamp(0, 1),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${downloadStatusLabel(record.status)} · ${(record.progress.clamp(0, 1) * 100).toStringAsFixed(0)}٪${record.expectedFileSize > 0 ? ' · ${(record.expectedFileSize / 1048576).toStringAsFixed(1)} MB' : ''}',
                                  ),
                                  if (record.status == TaskStatus.running &&
                                      progress != null)
                                    Text(
                                      '${progress.networkSpeedAsString} · زمان باقی‌مانده ${progress.timeRemainingAsString}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  if (record.exception != null)
                                    const Text(
                                      'دانلود متوقف شد؛ اتصال، اعتبار لینک و فضای ذخیره‌سازی را بررسی کن.',
                                    ),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      if (record.status == TaskStatus.running)
                                        TextButton.icon(
                                          onPressed: () => _action(
                                            () => manager.pause(task),
                                          ),
                                          icon: const Icon(Icons.pause),
                                          label: const Text('توقف'),
                                        ),
                                      if (record.status == TaskStatus.paused)
                                        TextButton.icon(
                                          onPressed: () => _action(
                                            () => manager.resume(task),
                                          ),
                                          icon: const Icon(Icons.play_arrow),
                                          label: const Text('ادامه'),
                                        ),
                                      if ([
                                        TaskStatus.failed,
                                        TaskStatus.notFound,
                                        TaskStatus.canceled,
                                      ].contains(record.status))
                                        TextButton.icon(
                                          onPressed: () => _action(
                                            () => manager.retry(task),
                                          ),
                                          icon: const Icon(Icons.refresh),
                                          label: const Text('تلاش مجدد'),
                                        ),
                                      if (![
                                        TaskStatus.complete,
                                        TaskStatus.failed,
                                        TaskStatus.notFound,
                                        TaskStatus.canceled,
                                      ].contains(record.status))
                                        TextButton.icon(
                                          onPressed: () => _action(
                                            () => manager.cancel(task),
                                          ),
                                          icon: const Icon(Icons.close),
                                          label: const Text('لغو'),
                                        ),
                                      if (record.status == TaskStatus.complete)
                                        TextButton.icon(
                                          onPressed: () => _action(() async {
                                            await _play(task);
                                            return true;
                                          }),
                                          icon: const Icon(Icons.play_circle),
                                          label: const Text('پخش'),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    ),
  );
}
