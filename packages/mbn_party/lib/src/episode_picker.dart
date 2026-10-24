import 'package:flutter/material.dart';

class PartyEpisodeChoice {
  const PartyEpisodeChoice(this.id, this.label);
  final String id, label;
}

class PartySeasonChoice {
  const PartySeasonChoice(this.id, this.label, this.episodes);
  final String id, label;
  final List<PartyEpisodeChoice> episodes;
}

class PartyEpisodePicker extends StatefulWidget {
  const PartyEpisodePicker({super.key, required this.seasons});
  final List<PartySeasonChoice> seasons;
  @override
  State<PartyEpisodePicker> createState() => _PartyEpisodePickerState();
}

class _PartyEpisodePickerState extends State<PartyEpisodePicker> {
  late PartySeasonChoice _season = widget.seasons.first;
  late String _episode = _season.episodes.first.id;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('کدام قسمت را می‌فرستی؟'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              key: const Key('party-season-picker'),
              value: _season.id,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'فصل'),
              items: widget.seasons
                  .map(
                    (s) => DropdownMenuItem(
                      value: s.id,
                      child: Text(
                        s.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (id) => setState(() {
                _season = widget.seasons.firstWhere((s) => s.id == id);
                _episode = _season.episodes.first.id;
              }),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: ValueKey('party-episode-picker-${_season.id}'),
              value: _episode,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'قسمت'),
              items: _season.episodes
                  .map(
                    (e) => DropdownMenuItem(
                      value: e.id,
                      child: Text(
                        e.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (id) {
                if (id != null) setState(() => _episode = id);
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('انصراف'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _episode),
        child: const Text('ادامه'),
      ),
    ],
  );
}
