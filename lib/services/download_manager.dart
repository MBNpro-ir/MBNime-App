import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/download_paths.dart';
import '../models/anime_content.dart';
import 'device_bridge.dart';
import 'hentai_network.dart';

class DownloadManager extends ChangeNotifier {
  DownloadManager._();
  static final instance = DownloadManager._();
  static const group = 'mbnime-media';
  final downloader = FileDownloader();
  final Map<String, TaskRecord> records = {};
  final Map<String, TaskProgressUpdate> progress = {};
  Future<void>? _initialization;
  StreamSubscription<TaskUpdate>? _subscription;
  Future<void> _queueLock = Future.value();
  bool wifiOnly = false;
  int concurrency = 2;
  bool allPaused = false;
  String? error;

  Future<void> initialize() =>
      _initialization ??= _initialize().catchError((Object exception) {
        _initialization = null;
        throw exception;
      });
  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    wifiOnly = prefs.getBool('downloads_wifi') ?? false;
    concurrency = (prefs.getInt('downloads_concurrency') ?? 2).clamp(1, 4);
    allPaused = prefs.getBool('downloads_all_paused') ?? false;
    _subscription ??= downloader.updates.listen(_update);
    downloader.configureNotificationForGroup(
      group,
      running: const TaskNotification(
        'در حال دانلود · {displayName}',
        '{progress} · {networkSpeed} · {timeRemaining}',
      ),
      complete: const TaskNotification('دانلود تمام شد', '{displayName}'),
      paused: const TaskNotification('دانلود متوقف است', '{displayName}'),
      error: const TaskNotification(
        'دانلود انجام نشد',
        '{displayName} · دوباره تلاش کن',
      ),
      progressBar: true,
      tapOpensFile: true,
    );
    await _configureQueue();
    await downloader.configure(
      globalConfig: [(Config.checkAvailableSpace, 100)],
      androidConfig: [(Config.runInForeground, Config.always)],
    );
    for (final record in await downloader.database.allRecords(group: group)) {
      records[record.taskId] = record;
    }
    await downloader.start(autoCleanDatabase: false);
    if (prefs.getBool('downloads_resume_after_update') == true) {
      await prefs.remove('downloads_resume_after_update');
      await resumeAll();
    }
    notifyListeners();
  }

  void _update(TaskUpdate update) {
    if (update.task.group != group) return;
    final old = records[update.task.taskId];
    if (update is TaskStatusUpdate) {
      records[update.task.taskId] = TaskRecord(
        update.task,
        update.status,
        update.status == TaskStatus.complete ? 1 : old?.progress ?? 0,
        old?.expectedFileSize ?? -1,
        update.exception,
      );
    } else if (update is TaskProgressUpdate) {
      progress[update.task.taskId] = update;
      if (old != null) {
        records[update.task.taskId] = old.copyWith(
          progress: update.progress >= 0 ? update.progress : old.progress,
          expectedFileSize: update.expectedFileSize,
        );
      }
    }
    notifyListeners();
  }

  Future<void> settings({bool? wifi, int? simultaneous}) async {
    await initialize();
    wifiOnly = wifi ?? wifiOnly;
    concurrency = (simultaneous ?? concurrency).clamp(1, 4);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('downloads_wifi', wifiOnly);
    await prefs.setInt('downloads_concurrency', concurrency);
    await _configureQueue();
    notifyListeners();
  }

  Future<String> rootDirectory() async {
    final root = Platform.isAndroid
        ? await DeviceBridge.downloadsDirectory()
        : (await getDownloadsDirectory())?.path;
    if (root == null) {
      throw const FileSystemException('پوشهٔ Downloads پیدا نشد');
    }
    return p.join(root, 'MBNime');
  }

  /// Serializing enqueue avoids double clicks/bulk requests creating duplicate files.
  Future<int> add(
    AnimeContent content,
    AnimeSeason season,
    List<AnimeEpisode> episodes,
  ) {
    final completer = Completer<int>();
    _queueLock = _queueLock.then((_) async {
      try {
        completer.complete(await _add(content, season, episodes));
      } catch (e, stack) {
        completer.completeError(e, stack);
      }
    });
    return completer.future;
  }

  Future<int> _add(
    AnimeContent content,
    AnimeSeason season,
    List<AnimeEpisode> episodes,
  ) async {
    await initialize();
    if (!await DeviceBridge.storageGranted()) {
      throw const FileSystemException(
        'برای ذخیره در Downloads/MBNime دسترسی مدیریت فایل را فعال کن.',
      );
    }
    if (Platform.isAndroid) {
      await downloader.permissions.request(PermissionType.notifications);
    }
    final root = await rootDirectory();
    final directory = p.joinAll([
      root,
      ...downloadFolderParts(content, season),
    ]);
    await Directory(directory).create(recursive: true);
    final cover = await _cacheCover(content);
    // شناسهٔ باندل: همهٔ فایل‌های یک افزودنِ یکجا (چند کیفیت فیلم یا
    // چند قسمت یک کیفیت) در مدیریت دانلود یک گروه بازشونده می‌شوند.
    final bundleId = DateTime.now().microsecondsSinceEpoch.toString();
    var count = 0;
    for (final episode in episodes) {
      final url = Uri.tryParse(episode.fileUrl);
      if (url == null ||
          !['https', 'http'].contains(url.scheme) ||
          url.host.isEmpty) {
        continue;
      }
      final identity = downloadIdentity(content.id, season.id, episode.id);
      final duplicate = records.values.any(
        (record) =>
            record.task.taskId.startsWith('$identity-') &&
            ![
              TaskStatus.failed,
              TaskStatus.notFound,
              TaskStatus.canceled,
            ].contains(record.status),
      );
      if (duplicate) continue;
      // Never overwrite an existing user file, including after history was cleared.
      var filename = episodeDownloadFilename(episode, identity);
      if (await File(p.join(directory, filename)).exists()) continue;
      final task = DownloadTask(
        taskId: '$identity-${DateTime.now().microsecondsSinceEpoch}',
        url: url.toString(),
        filename: filename,
        directory: directory,
        baseDirectory: BaseDirectory.root,
        group: group,
        updates: Updates.statusAndProgress,
        allowPause: true,
        retries: 5,
        requiresWiFi: wifiOnly,
        priority: 0,
        displayName: '${content.title} · ${episode.name}',
        metaData: jsonEncode({
          'coverPath': cover,
          'title': content.title,
          'season': season.name,
          'episode': episode.name,
          'contentId': content.id,
          'seasonId': season.id,
          'episodeId': episode.id,
          'bundleId': bundleId,
        }),
      );
      records[task.taskId] = TaskRecord(task, TaskStatus.enqueued, 0, -1);
      if (await downloader.enqueue(task)) {
        count++;
      } else {
        records[task.taskId] = TaskRecord(task, TaskStatus.failed, 0, -1);
      }
    }
    notifyListeners();
    return count;
  }

  Future<String> _cacheCover(AnimeContent content) async {
    if (content.imageUrl == null) return '';
    final support = await getApplicationSupportDirectory();
    final directory = await Directory(
      p.join(support.path, 'download-covers'),
    ).create(recursive: true);
    final file = File(
      p.join(directory.path, '${downloadIdentity(content.id, '', '')}.img'),
    );
    if (await file.exists()) return file.path;
    // +18 covers on Windows may need the system proxy; the native
    // downloader tasks (real downloads) already follow it via WinINet.
    if (content.isHentai && Platform.isWindows) {
      try {
        final response = await HentaiNetwork.fetchBytes(
          Uri.parse(content.imageUrl!),
        ).timeout(const Duration(seconds: 20));
        if (response.statusCode != 200 ||
            response.bodyBytes.length > 2 * 1024 * 1024) {
          return '';
        }
        await file.writeAsBytes(response.bodyBytes, flush: true);
        return file.path;
      } catch (_) {
        return '';
      }
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final response = await (await client.getUrl(
        Uri.parse(content.imageUrl!),
      )).close().timeout(const Duration(seconds: 7));
      if (response.statusCode != 200) return '';
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 7))) {
        bytes.addAll(chunk);
        if (bytes.length > 2 * 1024 * 1024) return '';
      }
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return '';
    } finally {
      client.close(force: true);
    }
  }

  /// تسک‌هایی که «توقف گروهی» نگه‌شان داشته: روی دسکتاپ pause تکی
  /// برای تسکِ هنوز-شروع‌نشده no-op است (ایزوله‌ای ندارد)، پس تمیز
  /// کنسل می‌شوند (صفری بایت دانلود نشده) و id نگه داشته می‌شود تا
  /// «ادامه» همان‌ها را دوباره در صف بگذارد. روی موبایل pause سطح
  /// کیو کافی است و این مجموعه استفاده نمی‌شود.
  final Set<String> heldForPause = {};

  static bool _isNativeMobile() {
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  Future<bool> pause(Task task) async {
    if (task is! DownloadTask) return false;
    final record = records[task.taskId];
    if (record != null &&
        !_isNativeMobile() &&
        (record.status == TaskStatus.enqueued ||
            record.status == TaskStatus.waitingToRetry)) {
      // دسکتاپ: pause تسکِ در صف بی‌اثر است؛ hold تمیز.
      try {
        if (await downloader.cancelTaskWithId(task.taskId)) {
          heldForPause.add(task.taskId);
          notifyListeners();
          return true;
        }
        return false;
      } catch (_) {
        return false;
      }
    }
    return downloader.pause(task);
  }

  Future<bool> resume(Task task) async {
    if (heldForPause.remove(task.taskId)) {
      // ادامهٔ hold گروهی/تکی: ورود دوباره از مسیر صف هلدینگ تا
      // سقف دانلود هم‌زمان کاربر رعایت شود.
      try {
        final ok = await downloader.enqueue(task);
        notifyListeners();
        return ok;
      } catch (_) {
        return false;
      }
    }
    return task is DownloadTask
        ? downloader.resume(task)
        : Future.value(false);
  }

  /// توقف واقعی همهٔ اعضای فعال یک باندل (در حال اجرا + در صف).
  /// فقط همین باندل می‌ایستد؛ سقف هم‌زمانی بقیه دست نخورده می‌ماند.
  Future<bool> pauseBundleTasks(List<TaskRecord> bundleRecords) async {
    await initialize();
    final running = [
      for (final record in bundleRecords)
        if (record.status == TaskStatus.running) record.task,
    ];
    final waiting = [
      for (final record in bundleRecords)
        if (record.status == TaskStatus.enqueued ||
            record.status == TaskStatus.waitingToRetry)
          record.task,
    ];
    if (running.isEmpty && waiting.isEmpty) return true;
    var ok = true;
    // ۱) در حال اجراها: pause واقعی (resume-data حفظ می‌شود).
    for (final task in running) {
      try {
        ok =
            await downloader.pause(task as DownloadTask) &&
            ok;
      } catch (_) {
        ok = false;
      }
    }
    // ۲) در صف‌ها: hold سطح کیو در موبایل؛ hold تمیز در دسکتاپ.
    if (waiting.isNotEmpty) {
      if (_isNativeMobile()) {
        try {
          await downloader.pauseAll(
            tasks: waiting.whereType<DownloadTask>().toList(growable: false),
          );
        } catch (_) {
          ok = false;
        }
      } else {
        for (final task in waiting) {
          try {
            if (await downloader.cancelTaskWithId(task.taskId)) {
              heldForPause.add(task.taskId);
            } else {
              ok = false;
            }
          } catch (_) {
            ok = false;
          }
        }
      }
    }
    notifyListeners();
    return ok;
  }

  /// ادامهٔ همهٔ اعضای متوقف یک باندل.
  /// hold سراسری («توقف همه» پنل) برداشته می‌شود تا ادامه واقعاً اجرا شود،
  /// ولی فقط همین باندل resume می‌شود و ورود دوباره از مسیر صف هلدینگ
  /// است تا سقف دانلود هم‌زمان کاربر رعایت شود.
  Future<bool> resumeBundleTasks(List<TaskRecord> bundleRecords) async {
    await initialize();
    if (allPaused) {
      allPaused = false;
      await (await SharedPreferences.getInstance()).setBool(
        'downloads_all_paused',
        false,
      );
      await _configureQueue();
    }
    final paused = [
      for (final record in bundleRecords)
        if (record.status == TaskStatus.paused) record.task,
    ];
    final held = [
      for (final record in bundleRecords)
        if (heldForPause.contains(record.task.taskId)) record.task,
    ];
    if (paused.isEmpty && held.isEmpty) return true;
    var ok = true;
    if (paused.isNotEmpty) {
      try {
        // API رسمی ادامهٔ گروهی: با فاصلهٔ زمانی، پاک‌سازی hold کیو،
        // و ورود از مسیر صف هلدینگ (رعایت سقف هم‌زمانی).
        final resumed = await downloader.resumeAll(
          tasks: paused.whereType<DownloadTask>().toList(growable: false),
        );
        ok = resumed.length == paused.length && ok;
      } catch (_) {
        ok = false;
      }
    }
    for (final task in held) {
      try {
        heldForPause.remove(task.taskId);
        ok = await downloader.enqueue(task) && ok;
      } catch (_) {
        ok = false;
      }
    }
    notifyListeners();
    return ok;
  }

  Future<bool> cancel(Task task) {
    heldForPause.remove(task.taskId);
    return downloader.cancelTaskWithId(task.taskId);
  }
  Future<bool> retry(Task task) async {
    heldForPause.remove(task.taskId);
    if (await File(await task.filePath()).exists()) return false;
    return downloader.enqueue(task.copyWith(retriesRemaining: task.retries));
  }

  Future<void> pauseAll() async {
    allPaused = true;
    await (await SharedPreferences.getInstance()).setBool(
      'downloads_all_paused',
      true,
    );
    await _configureQueue();
    for (final record in records.values.toList()) {
      if (record.status == TaskStatus.running) {
        await pause(record.task);
      }
    }
    notifyListeners();
  }

  Future<void> resumeAll() async {
    allPaused = false;
    await (await SharedPreferences.getInstance()).setBool(
      'downloads_all_paused',
      false,
    );
    await _configureQueue();
    for (final record in records.values.toList()) {
      if (record.status == TaskStatus.paused) await resume(record.task);
    }
    notifyListeners();
  }

  Future<void> _configureQueue() => downloader
      .configure(
        globalConfig: [
          (
            Config.holdingQueue,
            (allPaused ? 0 : concurrency, concurrency, concurrency),
          ),
        ],
      )
      .then((_) {});

  Future<void> prepareForUpdate() async {
    await initialize();
    if (!allPaused) {
      await (await SharedPreferences.getInstance()).setBool(
        'downloads_resume_after_update',
        true,
      );
      await pauseAll();
    }
    // A pause command is asynchronous on desktop; wait for the persisted status
    // before closing the process, otherwise partial-download metadata is lost.
    for (var attempt = 0; attempt < 80; attempt++) {
      if (!records.values.any((r) => r.status == TaskStatus.running)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw const FileSystemException(
      'دانلود هنوز متوقف نشده؛ پس از پایان آن دوباره نصب کن.',
    );
  }

  Future<void> clearFinished() async {
    for (final record in records.values.toList()) {
      if ([TaskStatus.complete, TaskStatus.canceled].contains(record.status)) {
        await downloader.database.deleteRecordWithId(record.taskId);
        records.remove(record.taskId);
        heldForPause.remove(record.taskId);
      }
    }
    notifyListeners();
  }
}

String downloadStatusLabel(TaskStatus status) => switch (status) {
  TaskStatus.enqueued => 'در صف',
  TaskStatus.running => 'در حال دانلود',
  TaskStatus.complete => 'تکمیل‌شده',
  TaskStatus.notFound => 'فایل در سرور پیدا نشد',
  TaskStatus.failed => 'ناموفق',
  TaskStatus.canceled => 'لغوشده',
  TaskStatus.waitingToRetry => 'در انتظار تلاش مجدد',
  TaskStatus.paused => 'متوقف',
};
