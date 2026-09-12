import 'dart:io';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/watch_progress.dart';
import '../models/anime_content.dart';
import '../services/external_apps.dart';
import '../widgets/ambient_background.dart';
import '../widgets/smart_cast_sheet.dart';
import '../widgets/download_choice.dart';
import '../widgets/wireless_display_sheet.dart';

/// Clean season/episode picker opened from «شروع تماشا».
///
/// Shows seasons as chips and the selected season's files as a tidy list
/// with per-episode saved positions. Tapping an episode asks whether to
/// resume or restart when a previous position exists.
class EpisodePickerScreen extends StatefulWidget {
  const EpisodePickerScreen({
    super.key,
    required this.content,
    required this.onPlay,
  });

  final AnimeContent content;

  /// Plays [episode] from [startAt]. Completes when the player closes.
  final Future<void> Function(AnimeEpisode episode, Duration startAt) onPlay;

  @override
  State<EpisodePickerScreen> createState() => _EpisodePickerScreenState();
}

class _EpisodePickerScreenState extends State<EpisodePickerScreen> {
  final _progress = WatchProgressStore();
  final _saved = <String, SavedWatchProgress>{};
  late int _seasonIndex = _defaultSeason(widget.content.seasons);

  static int _defaultSeason(List<AnimeSeason> seasons) {
    for (var i = 0; i < seasons.length; i++) {
      final hasRegular = seasons[i].episodes.any(
        (e) => !e.name.contains('تیزر'),
      );
      if (hasRegular) return i;
    }
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final entries = <String, SavedWatchProgress>{};
    for (final season in widget.content.seasons) {
      for (final episode in season.episodes) {
        final saved = await _progress.load(
          contentId: widget.content.id,
          episodeId: episode.id,
        );
        if (saved != null) entries[episode.id] = saved;
      }
    }
    if (mounted) setState(() => _saved.addAll(entries));
  }

  Future<void> _tapEpisode(AnimeEpisode episode) async {
    final saved = _saved[episode.id];
    var startAt = Duration.zero;
    if (saved != null && saved.isResumable && mounted) {
      final resume = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            episode.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          content: Text(
            'آخرین بار تا ${_fmt(saved.position)} دیده‌ای. ادامه می‌دهی یا از اول؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('از اول'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text('ادامه از ${_fmt(saved.position)}'),
            ),
          ],
        ),
      );
      if (resume == null) return;
      startAt = resume ? saved.position : Duration.zero;
    }
    await widget.onPlay(episode, startAt);
    await _loadSaved();
  }

  Future<void> _showPlayback(AnimeEpisode episode) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'کجا پخش شود؟',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.play_circle_fill),
                title: const Text('پلیر داخلی (پیشنهادی)'),
                onTap: () => Navigator.pop(context, 'internal'),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const BackButtonIcon(),
                  label: const Text('بازگشت'),
                ),
              ),
              ExpansionTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('پلیرهای خارجی'),
                children: [
                  for (final player in ExternalVideoPlayer.values)
                    if (Platform.isAndroid || player == ExternalVideoPlayer.vlc)
                      ListTile(
                        title: Text(ExternalApps.playerName(player)),
                        onTap: () => Navigator.pop(context, player.name),
                      ),
                ],
              ),
              ListTile(
                leading: const Icon(Icons.cast),
                title: const Text('تلویزیون یا مانیتور بدون سیم'),
                onTap: () => Navigator.pop(context, 'remote'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'internal') {
      await _tapEpisode(episode);
    } else if (choice == 'remote') {
      await showWirelessDisplaySheet(
        context,
        onCast: () => showSmartCastSheet(
          context,
          content: widget.content,
          episode: episode,
        ),
        onPlay: () => _tapEpisode(episode),
      );
    } else {
      await _playExternal(episode, ExternalVideoPlayer.values.byName(choice));
    }
  }

  Future<void> _playExternal(
    AnimeEpisode episode,
    ExternalVideoPlayer player,
  ) async {
    final result = await ExternalApps.playVideo(
      player: player,
      url: episode.fileUrl,
      title: '${widget.content.title} · ${episode.name}',
    );
    if (!mounted || result == ExternalLaunchResult.launched) return;
    if (result == ExternalLaunchResult.missing) {
      await _showMissingApp(
        ExternalApps.playerName(player),
        ExternalApps.playerInstallUrl(player),
      );
      return;
    }
    _showFailure('این روش پخش در دستگاه فعلی اجرا نشد.');
  }

  Future<void> _downloadEpisode(AnimeEpisode episode) async {
    await showDownloadChoice(
      context,
      content: widget.content,
      season: widget.content.seasons[_seasonIndex],
      episodes: [episode],
    );
  }

  Future<void> _showMissingApp(String name, String installUrl) =>
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('$name نصب نیست'),
          content: Text('برای انجام این کار باید $name روی دستگاه نصب باشد.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('انصراف'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                ExternalApps.openOfficialDownload(installUrl);
              },
              icon: const Icon(Icons.download_rounded),
              label: const Text('دانلود رسمی'),
            ),
          ],
        ),
      );

  void _showFailure(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final seasons = widget.content.seasons;
    if (seasons.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('انتخاب قسمت')),
        body: const Center(child: Text('هنوز قسمتی موجود نیست.')),
      );
    }
    final season = seasons[_seasonIndex.clamp(0, seasons.length - 1)];
    // Series episodes come newest-first from the API; show them first to
    // last. The synthetic movie-quality list keeps its server order.
    final episodes = season.id == 'movie'
        ? season.episodes
        : season.episodes.reversed.toList(growable: false);
    return Scaffold(
      appBar: AppBar(title: const Text('انتخاب قسمت')),
      body: AmbientBackground(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(
                widget.content.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                '${widget.content.year} · ${widget.content.kindLabel}',
                style: const TextStyle(color: AnimeColors.muted),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: _seasonIndex,
                decoration: const InputDecoration(
                  labelText: 'فصل / کیفیت پخش',
                  prefixIcon: Icon(Icons.layers_rounded),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                items: [
                  for (var i = 0; i < seasons.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(
                        '${seasons[i].name} · ${seasons[i].episodes.length} مورد',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _seasonIndex = value);
                },
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: episodes.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount:
                        constraints.maxWidth < 340 ||
                            MediaQuery.textScalerOf(context).scale(14) > 22
                        ? 1
                        : (constraints.maxWidth / 260).floor().clamp(2, 5),
                    mainAxisExtent:
                        225 +
                        (MediaQuery.textScalerOf(context).scale(14) - 14) * 6,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemBuilder: (_, i) {
                    final episode = episodes[i];
                    final saved = _saved[episode.id];
                    final resumable = saved?.isResumable ?? false;
                    final ratio = (saved != null && saved.durationMs > 0)
                        ? (saved.positionMs / saved.durationMs).clamp(0.0, 1.0)
                        : null;
                    final meta = [
                      if (episode.fileSize.isNotEmpty) '${episode.fileSize} MB',
                      if (episode.fileType.isNotEmpty)
                        episode.fileType.toUpperCase(),
                    ].join(' · ');
                    return Material(
                      color: AnimeColors.surface,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => _showPlayback(episode),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(
                                      color: AnimeColors.orange.withValues(
                                        alpha: .16,
                                      ),
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    child: const Icon(
                                      Icons.play_arrow_rounded,
                                      color: AnimeColors.orange,
                                      size: 26,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          episode.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (meta.isNotEmpty) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            meta,
                                            style: const TextStyle(
                                              color: AnimeColors.muted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                        if (resumable) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            'ادامه از ${_fmt(saved!.position)}',
                                            style: const TextStyle(
                                              color: AnimeColors.cyan,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (ratio != null) ...[
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(
                                    value: ratio,
                                    minHeight: 4,
                                    backgroundColor: Colors.white10,
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                          AnimeColors.orange,
                                        ),
                                  ),
                                ),
                              ],
                              const Spacer(),
                              Wrap(
                                spacing: 7,
                                runSpacing: 7,
                                children: [
                                  FilledButton.tonalIcon(
                                    onPressed: () => _showPlayback(episode),
                                    icon: const Icon(Icons.play_arrow_rounded),
                                    label: const Text('پخش'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _downloadEpisode(episode),
                                    icon: const Icon(Icons.download_rounded),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AnimeColors.cyan,
                                    ),
                                    label: const Text('دانلود'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _fmt(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
