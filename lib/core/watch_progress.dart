import 'package:shared_preferences/shared_preferences.dart';

/// Saved playback position of a single episode.
class SavedWatchProgress {
  const SavedWatchProgress({
    required this.positionMs,
    required this.durationMs,
  });

  final int positionMs;
  final int durationMs;

  Duration get position => Duration(milliseconds: positionMs);
  Duration get duration => Duration(milliseconds: durationMs);

  /// Offer "resume" only for genuinely partial watches.
  bool get isResumable =>
      positionMs > 15000 &&
      (durationMs <= 0 || positionMs < durationMs - 30000);
}

/// Persists per-episode playback positions in local preferences so the
/// user can resume later. Finished episodes (position at the very end)
/// are cleared automatically.
class WatchProgressStore {
  static String _posKey(String contentId, String episodeId) =>
      'watch_pos_${contentId}_$episodeId';
  static String _durKey(String contentId, String episodeId) =>
      'watch_dur_${contentId}_$episodeId';

  Future<void> save({
    required String contentId,
    required String episodeId,
    required Duration position,
    required Duration duration,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (duration > Duration.zero &&
        position >= duration - const Duration(seconds: 10)) {
      // Watched to the end: forget the saved position.
      await prefs.remove(_posKey(contentId, episodeId));
      await prefs.remove(_durKey(contentId, episodeId));
      return;
    }
    await prefs.setInt(_posKey(contentId, episodeId), position.inMilliseconds);
    await prefs.setInt(_durKey(contentId, episodeId), duration.inMilliseconds);
  }

  Future<SavedWatchProgress?> load({
    required String contentId,
    required String episodeId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final pos = prefs.getInt(_posKey(contentId, episodeId));
    if (pos == null || pos <= 0) return null;
    final dur = prefs.getInt(_durKey(contentId, episodeId)) ?? 0;
    return SavedWatchProgress(positionMs: pos, durationMs: dur);
  }

  Future<void> clear({
    required String contentId,
    required String episodeId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_posKey(contentId, episodeId));
    await prefs.remove(_durKey(contentId, episodeId));
  }
}
