import 'package:flutter/foundation.dart' show kIsWeb;
import 'browser_features.dart';
import 'package:flutter/material.dart';
import 'package:mbn_party/mbn_party.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/anime_content.dart';
import '../core/episode_catalog.dart';
import '../screens/detail_screen.dart';
import 'animeon_api.dart';
import 'adult_access.dart';
import 'hentai_iran_api.dart';

/// Only public catalog identity crosses the account service. Each device
/// resolves its own authorized stream and preferred quality.
class AppParty {
  static ContentApi? api;
  static void bind(
    ContentApi value, {
    required Future<void> Function(AnimeContent) openDetails,
  }) {
    api = value;
    PartyHub.instance.openMedia = open;
    PartyHub.instance.openDetails = (context, media) async {
      final summary = await _summary(media);
      if (context.mounted) await openDetails(summary);
    };
  }

  static PartyJson metadata(AnimeContent item, EpisodeGroup group) => {
    'content_id': item.id,
    'episode_id': group.id,
    'title': item.title,
    'episode_title': group.name,
    'season_title':
        EpisodeCatalog.from(item).seasons
            .where((s) => s.episodes.any((e) => e.id == group.id))
            .firstOrNull
            ?.name ??
        '',
    'kind': item.kind.name,
    'poster': item.imageUrl ?? '',
    'adult': item.isHentai,
    'source': item.isHentai ? 'hentai' : 'anime',
  };

  static Future<void> send(BuildContext context, AnimeContent item) async {
    final seasons = EpisodeCatalog.from(item).seasons
        .where((s) => !s.isTrailerSeason)
        .map(
          (s) => PartySeasonChoice(s.id, s.name, [
            for (final g in s.episodes)
              if (!g.isTrailer && g.variants.isNotEmpty)
                PartyEpisodeChoice(g.id, g.name),
          ]),
        )
        .where((s) => s.episodes.isNotEmpty)
        .toList();
    final groups = EpisodeCatalog.from(
      item,
    ).episodes.where((g) => !g.isTrailer && g.variants.isNotEmpty).toList();
    if (groups.isEmpty || seasons.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('قسمت قابل پخشی پیدا نشد.')));
      return;
    }
    EpisodeGroup? group = groups.first;
    if (groups.length > 1) {
      final id = await showDialog<String>(
        context: context,
        builder: (_) => PartyEpisodePicker(seasons: seasons),
      );
      group = groups.where((g) => g.id == id).firstOrNull;
    }
    if (group != null && context.mounted) {
      await sendPartyMedia(context, metadata(item, group));
    }
  }

  static Future<AnimeContent> _summary(PartyJson media) async {
    final source = partyMediaApp(media);
    if (source != 'anime') {
      throw const PartyException(
        'این فیلم یا سریال برای این اپ نیست؛ برای اپ MBNMovie است.',
      );
    }
    final restricted = media['adult'] == true || media['source'] == 'hentai';
    if (restricted) {
      await AdultAccess.instance.refresh();
      if (!AdultAccess.instance.allowed) {
        throw const PartyException('اجازهٔ دسترسی به این محتوا فعال نیست.');
      }
    }
    return AnimeContent(
      id: media['content_id'].toString(),
      title: media['title']?.toString() ?? '',
      subtitle: '',
      description: '',
      year: 0,
      rating: 0,
      kind: media['kind'] == 'series' ? ContentKind.series : ContentKind.movie,
      colors: const [Color(0xFF172235), Color(0xFF0D1422)],
      genres: const [],
      isHentai: restricted,
    );
  }

  static Future<void> open(
    BuildContext context,
    PartyJson media,
    String? sessionId,
  ) async {
    final browserReservation = kIsWeb ? BrowserFeatures.preparePlayer() : null;
    try {
      await _openPlayer(context, media, sessionId);
    } finally {
      if (browserReservation != null) {
        await BrowserFeatures.releasePlayer(browserReservation);
      }
    }
  }

  static Future<void> _openPlayer(
    BuildContext context,
    PartyJson media,
    String? sessionId,
  ) async {
    final source = api;
    if (source == null) {
      throw const PartyException('کاتالوگ هنوز آماده نشده است.');
    }
    final summary = await _summary(media);
    final restricted = summary.isHentai;
    final item = await (restricted ? HentaiIranApi() : source)
        .details(summary)
        .timeout(
          const Duration(seconds: 35),
          onTimeout: () => throw const PartyException(
            'دریافت قسمت‌ها بیش از حد طول کشید؛ دوباره تلاش کن.',
          ),
        );
    if (!context.mounted) return;
    final catalog = EpisodeCatalog.from(item),
        id = media['episode_id']?.toString() ?? '';
    final group = catalog.episodes
        .where((g) => g.id == id || g.variants.any((v) => v.episode.id == id))
        .firstOrNull;
    // Never silently join another episode if a source changed its catalog.
    if (group == null) {
      throw const PartyException(
        'این قسمت در کاتالوگ فعلی پیدا نشد؛ دعوت تازه‌ای ارسال کن.',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted) return;
    final variant = group.variantFor(
      prefs.getString('preferred_stream_quality'),
    );
    final navigator = Navigator.of(context, rootNavigator: true);
    await navigator.pushAndRemoveUntil<void>(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          content: item,
          episode: variant.episode,
          partySessionId: sessionId,
        ),
      ),
      (route) => route.isFirst,
    );
  }
}
