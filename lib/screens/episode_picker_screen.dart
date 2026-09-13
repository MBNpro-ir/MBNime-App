import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/episode_catalog.dart';
import '../core/theme.dart';
import '../core/watch_progress.dart';
import '../core/player_preferences.dart';
import '../models/anime_content.dart';
import '../services/external_apps.dart';
import '../widgets/ambient_background.dart';
import '../widgets/smart_cast_sheet.dart';
import '../widgets/download_choice.dart';
import '../widgets/default_preference_prompt.dart';
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
    this.deferInitialContent = false,
  });

  final AnimeContent content;

  /// Plays [episode] from [startAt]. Completes when the player closes.
  final Future<void> Function(AnimeEpisode episode, Duration startAt) onPlay;
  final bool deferInitialContent;

  @override
  State<EpisodePickerScreen> createState() => _EpisodePickerScreenState();
}

class _EpisodePickerScreenState extends State<EpisodePickerScreen> {
  final _progress = WatchProgressStore();
  final _saved = <String, SavedWatchProgress>{};
  late final EpisodeCatalog _catalog;
  int _seasonIndex = 0;
  String _selectedQuality = 'بدون برچسب کیفیت';
  Timer? _initialContentTimer;
  late bool _contentReady;

  static int _defaultSeason(List<EpisodeSeasonGroup> seasons) {
    for (var i = 0; i < seasons.length; i++) {
      final hasRegular = seasons[i].episodes.any(
        (episode) => !episode.name.contains('تیزر'),
      );
      if (hasRegular) return i;
    }
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _catalog = EpisodeCatalog.from(widget.content);
    _seasonIndex = _defaultSeason(_catalog.seasons);
    _selectedQuality = recommendedEpisodeQuality(
      _catalog.seasons[_seasonIndex].qualities,
    );
    _contentReady = !widget.deferInitialContent;
    if (_contentReady) {
      unawaited(_loadSaved());
      unawaited(_loadQualityPreference());
    } else {
      // Keep the container-transform frames light on phones. The episode grid
      // and preference I/O start as soon as the short opening animation ends.
      _initialContentTimer = Timer(const Duration(milliseconds: 310), () {
        if (!mounted) return;
        setState(() => _contentReady = true);
        unawaited(_loadSaved());
        unawaited(_loadQualityPreference());
      });
    }
  }

  @override
  void dispose() {
    _initialContentTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    final entries = <String, SavedWatchProgress>{};
    for (final group in _catalog.episodes) {
      SavedWatchProgress? best = await _progress.load(
        contentId: widget.content.id,
        episodeId: group.id,
      );
      for (final variant in group.variants) {
        final legacy = await _progress.load(
          contentId: widget.content.id,
          episodeId: variant.episode.id,
        );
        best = _newerProgress(best, legacy);
      }
      if (best != null) {
        entries[group.id] = best;
        await _progress.save(
          contentId: widget.content.id,
          episodeId: group.id,
          position: best.position,
          duration: best.duration,
          markWatched: best.watched,
        );
      }
    }
    if (mounted) {
      setState(() {
        _saved
          ..clear()
          ..addAll(entries);
      });
    }
  }

  SavedWatchProgress? _newerProgress(
    SavedWatchProgress? current,
    SavedWatchProgress? candidate,
  ) {
    if (candidate == null) return current;
    if (current == null || candidate.watched && !current.watched) {
      return candidate;
    }
    return candidate.positionMs > current.positionMs ? candidate : current;
  }

  Future<void> _loadQualityPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final quality = prefs.getString('preferred_stream_quality');
    final available = _catalog.seasons[_seasonIndex].qualities;
    if (!mounted || quality == null || !available.contains(quality)) {
      return;
    }
    setState(() => _selectedQuality = quality);
  }

  Future<void> _setQuality(String quality) async {
    setState(() => _selectedQuality = quality);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('preferred_stream_quality', quality);
  }

  void _selectSeason(int index) {
    final qualities = _catalog.seasons[index].qualities;
    setState(() {
      _seasonIndex = index;
      if (!qualities.contains(_selectedQuality)) {
        _selectedQuality = recommendedEpisodeQuality(qualities);
      }
    });
  }

  Future<void> _tapEpisode(EpisodeGroup group, EpisodeVariant variant) async {
    final saved = _saved[group.id];
    var startAt = Duration.zero;
    if (saved != null && saved.isResumable && mounted) {
      final resume = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(group.name, maxLines: 2, overflow: TextOverflow.ellipsis),
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
    await widget.onPlay(variant.episode, startAt);
    await _loadSaved();
  }

  Future<void> _showPlayback(EpisodeGroup group) async {
    final variant = group.variantFor(_selectedQuality);
    final allowedPlayers = <String>{
      PlaybackPreferenceStore.internalPlayer,
      ExternalVideoPlayer.vlc.name,
      if (Platform.isAndroid) ExternalVideoPlayer.mxPlayer.name,
      if (Platform.isAndroid) ExternalVideoPlayer.mxPlayerPro.name,
    };
    String? choice = await PlaybackPreferenceStore.defaultPlayer();
    var selectedManually = false;
    if (!allowedPlayers.contains(choice)) {
      if (!mounted) return;
      choice =
          await showModalBottomSheet<String>(
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
                    ExpansionTile(
                      leading: const Icon(Icons.open_in_new),
                      title: const Text('پلیرهای خارجی'),
                      children: [
                        for (final player in ExternalVideoPlayer.values)
                          if (Platform.isAndroid ||
                              player == ExternalVideoPlayer.vlc)
                            ListTile(
                              title: Text(ExternalApps.playerName(player)),
                              onTap: () => Navigator.pop(context, player.name),
                            ),
                      ],
                    ),
                    ListTile(
                      leading: const Icon(Icons.cast),
                      title: const Text('تلویزیون یا مانیتور بدون سیم'),
                      onTap: () async {
                        // Keep this menu underneath its child: Back pops one level.
                        final destination = await showWirelessDisplaySheet(
                          context,
                          onCast: (initialDestination) => showSmartCastSheet(
                            context,
                            content: widget.content,
                            episode: variant.episode,
                            initialDestination: initialDestination,
                          ),
                        );
                        if (destination != null && context.mounted) {
                          Navigator.pop(context, destination);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ) ??
          '';
      selectedManually = choice.isNotEmpty;
    }
    if (!mounted || choice.isEmpty) return;
    if (selectedManually && allowedPlayers.contains(choice)) {
      final label = choice == PlaybackPreferenceStore.internalPlayer
          ? 'پلیر داخلی'
          : ExternalApps.playerName(ExternalVideoPlayer.values.byName(choice));
      await maybeSuggestDefaultPlayer(context, value: choice, label: label);
      if (!mounted) return;
    }
    if (choice == 'internal') {
      await _tapEpisode(group, variant);
    } else if (choice == 'wireless') {
      await _tapEpisode(group, variant);
    } else if (choice != 'cast') {
      await _playExternal(
        variant.episode,
        ExternalVideoPlayer.values.byName(choice),
      );
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

  Future<void> _downloadEpisode(EpisodeGroup group) async {
    final variant = await _chooseDownloadVariant(group);
    if (variant == null || !mounted) return;
    await showDownloadChoice(
      context,
      content: widget.content,
      season: variant.season,
      episodes: [variant.episode],
    );
  }

  Future<EpisodeVariant?> _chooseDownloadVariant(EpisodeGroup group) async {
    if (group.variants.length == 1) return group.variants.single;
    return showModalBottomSheet<EpisodeVariant>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              leading: Icon(Icons.download_rounded),
              title: Text('کیفیت دانلود را انتخاب کن'),
            ),
            for (final variant in group.variants)
              ListTile(
                leading: const Icon(Icons.high_quality_rounded),
                title: Text(variant.quality),
                subtitle: Text(_variantMeta(variant)),
                trailing: variant.quality == _selectedQuality
                    ? const Icon(Icons.check_circle_rounded)
                    : null,
                onTap: () => Navigator.pop(context, variant),
              ),
          ],
        ),
      ),
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

  Widget _selectorRow({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) => Row(
    children: [
      Icon(icon, size: 20, color: AnimeColors.orange),
      const SizedBox(width: 7),
      Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(width: 12),
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: children),
        ),
      ),
    ],
  );

  Widget _episodeCard(EpisodeGroup group) {
    final variant = group.variantFor(_selectedQuality);
    final saved = _saved[group.id];
    final resumable = saved?.isResumable ?? false;
    final watched = saved?.watched ?? false;
    final almostWatched = saved?.almostWatched ?? false;
    final ratio = (saved != null && saved.durationMs > 0)
        ? (saved.positionMs / saved.durationMs).clamp(0.0, 1.0)
        : null;
    final statusColor = watched
        ? AnimeColors.cyan
        : almostWatched
        ? const Color(0xFFFFD600)
        : AnimeColors.orange;
    final statusIcon = watched
        ? Icons.check_circle_rounded
        : almostWatched
        ? Icons.timelapse_rounded
        : resumable
        ? Icons.play_circle_fill_rounded
        : Icons.radio_button_unchecked_rounded;
    final status = watched
        ? 'تماشا کردی'
        : almostWatched
        ? 'تقریباً تماشا کردی'
        : resumable
        ? 'ادامه از ${_fmt(saved!.position)}'
        : 'تماشا نشده';
    return Material(
      key: Key('episode-card-${group.id}'),
      color: watched
          ? AnimeColors.cyan.withValues(alpha: .10)
          : almostWatched
          ? const Color(0xFFFFD600).withValues(alpha: .10)
          : AnimeColors.surface,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => _showPlayback(group),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      variant.quality,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(
                    alpha: watched || almostWatched || resumable ? .16 : .07,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: statusColor.withValues(
                      alpha: watched || almostWatched || resumable ? .45 : .18,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(statusIcon, size: 20, color: statusColor),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 9),
              if (ratio != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 7,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation(statusColor),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _variantMeta(variant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AnimeColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Text(
                    '${group.variants.length} کیفیت',
                    style: const TextStyle(
                      color: AnimeColors.muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _showPlayback(group),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('پخش'),
                    ),
                  ),
                  const SizedBox(width: 7),
                  IconButton.outlined(
                    tooltip: 'دانلود با انتخاب کیفیت',
                    onPressed: () => _downloadEpisode(group),
                    color: AnimeColors.cyan,
                    icon: const Icon(Icons.download_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final seasons = _catalog.seasons;
    if (seasons.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('انتخاب قسمت')),
        body: const Center(child: Text('هنوز قسمتی موجود نیست.')),
      );
    }
    final season = seasons[_seasonIndex.clamp(0, seasons.length - 1)];
    final episodes = season.episodes;
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
            Container(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AnimeColors.surface.withValues(alpha: .92),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  if (seasons.length > 1) ...[
                    _selectorRow(
                      title: 'فصل',
                      icon: Icons.video_library_rounded,
                      children: [
                        for (var i = 0; i < seasons.length; i++) ...[
                          ChoiceChip(
                            label: Text(seasons[i].name),
                            selected: i == _seasonIndex,
                            onSelected: (_) => _selectSeason(i),
                          ),
                          const SizedBox(width: 7),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  _selectorRow(
                    title: 'کیفیت',
                    icon: Icons.high_quality_rounded,
                    children: [
                      for (final quality in season.qualities) ...[
                        ChoiceChip(
                          key: Key('quality-$quality'),
                          label: Text(quality),
                          selected: quality == _selectedQuality,
                          onSelected: (_) => _setQuality(quality),
                        ),
                        const SizedBox(width: 7),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: !_contentReady
                  ? const SizedBox.expand()
                  : LayoutBuilder(
                      builder: (context, constraints) => GridView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        itemCount: episodes.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount:
                              MediaQuery.textScalerOf(context).scale(14) > 22
                              ? 1
                              : (constraints.maxWidth / 245).floor().clamp(
                                  2,
                                  5,
                                ),
                          mainAxisExtent:
                              210 +
                              (MediaQuery.textScalerOf(context).scale(14) -
                                      14) *
                                  4,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemBuilder: (_, i) {
                          return _episodeCard(episodes[i]);
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

String _variantMeta(EpisodeVariant variant) {
  final values = [
    if (variant.episode.fileSize.isNotEmpty) '${variant.episode.fileSize} MB',
    if (variant.episode.fileType.isNotEmpty)
      variant.episode.fileType.toUpperCase(),
  ];
  return values.isEmpty ? 'پخش آنلاین' : values.join(' · ');
}
