import 'package:shared_preferences/shared_preferences.dart';

/// Saved playback position of a single episode.
class SavedWatchProgress {
  const SavedWatchProgress({
    required this.positionMs,
    required this.durationMs,
    this.watched = false,
  });

  final int positionMs;
  final int durationMs;
  final bool watched;

  Duration get position => Duration(milliseconds: positionMs);
  Duration get duration => Duration(milliseconds: durationMs);

  /// Offer "resume" only for genuinely partial watches.
  bool get isResumable =>
      positionMs > 15000 &&
      (durationMs <= 0 || positionMs < durationMs - 30000);

  bool get almostWatched =>
      !watched &&
      durationMs > 0 &&
      positionMs > 0 &&
      positionMs <= durationMs &&
      durationMs - positionMs <= const Duration(minutes: 5).inMilliseconds;
}

/// Persists per-episode playback positions in local preferences so the
/// user can resume later. The watched marker is stored independently from the
/// position so replaying or moving to the next episode does not erase history.
class WatchProgressStore {
  static String _posKey(String contentId, String episodeId) =>
      'watch_pos_${contentId}_$episodeId';
  static String _durKey(String contentId, String episodeId) =>
      'watch_dur_${contentId}_$episodeId';
  static String _watchedKey(String contentId, String episodeId) =>
      'watch_done_${contentId}_$episodeId';

  Future<void> save({
    required String contentId,
    required String episodeId,
    required Duration position,
    required Duration duration,
    bool markWatched = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_posKey(contentId, episodeId), position.inMilliseconds);
    await prefs.setInt(_durKey(contentId, episodeId), duration.inMilliseconds);
    final reachedEnd =
        duration > Duration.zero &&
        position >= duration - const Duration(seconds: 10);
    if (markWatched || reachedEnd) {
      await prefs.setBool(_watchedKey(contentId, episodeId), true);
    }
  }

  Future<SavedWatchProgress?> load({
    required String contentId,
    required String episodeId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final pos = prefs.getInt(_posKey(contentId, episodeId));
    final watched = prefs.getBool(_watchedKey(contentId, episodeId)) ?? false;
    if ((pos == null || pos <= 0) && !watched) return null;
    final dur = prefs.getInt(_durKey(contentId, episodeId)) ?? 0;
    return SavedWatchProgress(
      positionMs: pos ?? 0,
      durationMs: dur,
      watched: watched,
    );
  }

  Future<void> clear({
    required String contentId,
    required String episodeId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_posKey(contentId, episodeId));
    await prefs.remove(_durKey(contentId, episodeId));
    await prefs.remove(_watchedKey(contentId, episodeId));
  }
}
