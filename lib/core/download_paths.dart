import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/anime_content.dart';

String safeDownloadComponent(String input) {
  var value = input
      .replaceAll(RegExp(r'[\x00-\x1f\\/:*?"<>|]'), '-')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (value.isEmpty || value == '.' || value == '..') value = 'بدون نام';
  if (RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
    caseSensitive: false,
  ).hasMatch(value)) {
    value = '_$value';
  }
  return String.fromCharCodes(value.runes.take(65));
}

String downloadIdentity(String contentId, String seasonId, String episodeId) =>
    sha256
        .convert(utf8.encode(jsonEncode([contentId, seasonId, episodeId])))
        .toString()
        .substring(0, 16);

String episodeDownloadFilename(AnimeEpisode episode, String identity) {
  var extension = episode.fileType.toLowerCase().trim();
  if (!RegExp(r'^(mp4|mkv|webm|avi|mov|m4v|ts)$').hasMatch(extension)) {
    extension =
        Uri.tryParse(episode.fileUrl)?.path.split('.').last.toLowerCase() ??
        'mp4';
  }
  if (!RegExp(r'^(mp4|mkv|webm|avi|mov|m4v|ts)$').hasMatch(extension)) {
    extension = 'mp4';
  }
  return '${safeDownloadComponent(episode.name)}-$identity.$extension';
}
