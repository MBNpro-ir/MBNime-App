import 'package:flutter/material.dart';

enum ContentKind { movie, series, anime }

class AnimeEpisode {
  const AnimeEpisode({
    required this.id,
    required this.name,
    required this.fileUrl,
    this.imageUrl,
    this.fileType = '',
    this.fileSize = '',
  });

  final String id;
  final String name;
  final String fileUrl;
  final String? imageUrl;
  final String fileType;
  final String fileSize;
}

class AnimeSeason {
  const AnimeSeason({
    required this.id,
    required this.name,
    required this.episodes,
  });

  final String id;
  final String name;
  final List<AnimeEpisode> episodes;
}

class AnimePerson {
  const AnimePerson({required this.id, required this.name, this.imageUrl});

  final String id;
  final String name;
  final String? imageUrl;
}

class AnimeDownload {
  const AnimeDownload({
    required this.id,
    required this.label,
    required this.url,
    this.fileSize = '',
  });

  final String id;
  final String label;
  final String url;
  final String fileSize;
}

/// لینک مرتبط داخل صفحه هنتای (ژانر / استودیو / وضعیت / زیرنویس …).
/// [taxonomy] یکی از مقادیر `genre`, `anime_tag`, `hi_studio`, `hi_status`,
/// `hi_censor`, `hi_year`, `hi_sub` یا `link` (پیوند آزاد سایت) است و
/// [termId] در صورت قابل استخراج بودن شناسه عددی وردپرس را نگه می‌دارد تا
/// ضربه روی چیپ مستقیماً آرشیو درون‌برنامه‌ای را باز کند.
class HentaiRelatedLink {
  const HentaiRelatedLink({
    required this.title,
    required this.url,
    this.taxonomy = 'link',
    this.termId = '',
    this.highlight = false,
  });

  final String title;
  final String url;
  final String taxonomy;
  final String termId;
  final bool highlight;
}

class AnimeComment {
  const AnimeComment({
    required this.id,
    required this.userName,
    required this.text,
    this.userImageUrl,
  });

  final String id;
  final String userName;
  final String text;
  final String? userImageUrl;
}

class AnimeContent {
  const AnimeContent({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.year,
    required this.rating,
    required this.kind,
    required this.colors,
    required this.genres,
    this.episodes = 0,
    this.progress = 0,
    this.imageUrl,
    this.backdropUrl,
    this.detailUrl,
    this.seasons = const [],
    this.imdbId,
    this.runtime = '',
    this.alternateTitles = const [],
    this.countries = const [],
    this.directors = const [],
    this.cast = const [],
    this.related = const [],
    this.downloads = const [],
    this.isHentai = false,
    this.studio = '',
    this.statusLabel = '',
    this.censorLabel = '',
    this.subtitleLabel = '',
    this.viewsText = '',
    this.downloadsText = '',
    this.publishDateText = '',
    this.ageRating = '',
    this.tags = const [],
    this.relatedLinks = const [],
  });

  final String id;
  final String title;
  final String subtitle;
  final String description;
  final int year;
  final double rating;
  final ContentKind kind;
  final List<Color> colors;
  final List<String> genres;
  final int episodes;
  final double progress;
  final String? imageUrl;

  /// Alternate artwork candidate. Its role is verified from decoded image
  /// dimensions because legacy API records can interchange the two fields.
  final String? backdropUrl;
  final String? detailUrl;
  final List<AnimeSeason> seasons;
  final String? imdbId;
  final String runtime;
  final List<String> alternateTitles;
  final List<String> countries;
  final List<AnimePerson> directors;
  final List<AnimePerson> cast;
  final List<AnimeContent> related;
  final List<AnimeDownload> downloads;
  final bool isHentai;

  /// --- فیلدهای اختصاصی هنتای (برای بخش عادی خالی می‌مانند) ---
  /// استودیو (hi_studio)، وضعیت پخش (hi_status)، سانسور (hi_censor) و
  /// زیرنویس (hi_sub) دقیقاً مطابق سایت.
  final String studio;
  final String statusLabel;
  final String censorLabel;
  final String subtitleLabel;

  /// شمارنده‌های متنی سایت (با ارقام فارسی) و تاریخ انتشار میلادی.
  final String viewsText;
  final String downloadsText;
  final String publishDateText;

  /// رده سنی (همیشه ‎+18‎ برای هنتای).
  final String ageRating;

  /// برچسب‌ها (anime_tag) جدا از ژانرها (genre).
  final List<String> tags;

  /// لینک‌های مرتبط سایت (ترکیب ژانر/استودیو/وضعیت/زیرنویس).
  final List<HentaiRelatedLink> relatedLinks;

  String get kindLabel => switch (kind) {
    ContentKind.movie => 'فیلم',
    ContentKind.series => 'سریال',
    ContentKind.anime => 'انیمه',
  };

  String get ratingLabel => rating == rating.roundToDouble()
      ? rating.toStringAsFixed(0)
      : rating.toStringAsFixed(1);
}
