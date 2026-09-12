import 'dart:io';
import 'package:flutter/material.dart';
import '../services/external_apps.dart';

Future<String?> showDownloadPlaybackSheet(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(18),
                child: Text('کجا پخش شود؟'),
              ),
              ListTile(
                leading: const Icon(Icons.play_circle),
                title: const Text('پلیر داخلی (پیشنهادی)'),
                onTap: () => Navigator.pop(context, 'internal'),
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
            ],
          ),
        ),
      ),
    );
