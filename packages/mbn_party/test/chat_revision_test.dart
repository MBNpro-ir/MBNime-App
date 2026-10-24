import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mbn_party/mbn_party.dart';

PartyJson message(
  int id, {
  int sender = 1,
  int? reply,
  bool media = false,
  String source = 'movie',
}) => {
  'id': id,
  'room_id': 'r',
  'sender_id': sender,
  'sender': {'id': sender, 'name': 'کاربر $sender'},
  'body': 'پیام فارسی $id Android',
  'kind': media ? 'media' : 'text',
  'created_at': 1,
  'reactions': [],
  'reply_to': reply,
  if (reply != null) 'reply': {'id': reply, 'body': 'متن اصلی'},
  'payload': media
      ? {
          'content_id': 'film',
          'episode_id': 'ep',
          'title': 'فیلم آزمایشی',
          'source': source,
        }
      : {},
};

Future<PartyClient> chat(
  WidgetTester tester,
  List<PartyJson> messages, {
  List<PartyJson>? around,
  void Function()? onAround,
}) async {
  await tester.pumpWidget(const SizedBox());
  final room = <String, dynamic>{
    'id': 'r',
    'kind': 'direct',
    'members': [
      {
        'user_id': 1,
        'user': {'id': 1, 'name': 'من'},
      },
      {
        'user_id': 2,
        'user': {'id': 2, 'name': 'دوست'},
      },
    ],
    'permissions': {
      'can_message': true,
      'can_share': true,
      'can_control': true,
    },
  };
  final client = PartyClient(
    baseUrl: 'http://test.local',
    app: 'movie',
    token: () => 'token',
    httpClient: MockClient((r) async {
      Object data;
      if (r.url.path.endsWith('/bootstrap')) {
        data = {
          'me': {'id': 1, 'public_id': 'user_1'},
          'rooms': [room],
          'friends': [],
          'requests': [],
          'sessions': [],
          'cursor': 0,
        };
      } else if (r.url.path.endsWith('/messages')) {
        if ((int.tryParse(r.url.queryParameters['around'] ?? '') ?? 0) > 0) {
          onAround?.call();
        }
        data = {
          'messages':
              (int.tryParse(r.url.queryParameters['around'] ?? '') ?? 0) > 0
              ? around ?? messages
              : messages,
          'has_more': false,
        };
      } else if (r.url.path.endsWith('/rooms/r')) {
        data = {'room': room};
      } else {
        data = {'ok': true, 'events': [], 'cursor': 0};
      }
      return http.Response(
        jsonEncode(data),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
  await client.refresh();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: PartyScreen(client: client, initialRoomId: 'r'),
    ),
  );
  await tester.pumpAndSettle();
  return client;
}

Future<void> cleanup(WidgetTester tester, PartyClient client) async {
  await tester.pumpWidget(const SizedBox());
  client.dispose();
  PartyHub.instance.openMedia = null;
  PartyHub.instance.openDetails = null;
}

void main() {
  testWidgets(
    'Physical right swipe replies for own and peer messages in RTL; left swipe does not',
    (tester) async {
      for (final sender in [1, 2]) {
        final client = await chat(tester, [message(1, sender: sender)]);
        final row = find.byKey(const ValueKey('party-message-1'));
        await tester.drag(row, const Offset(-100, 0));
        await tester.pumpAndSettle();
        expect(find.byTooltip('لغو پاسخ'), findsNothing);
        await tester.drag(row, const Offset(110, 0));
        await tester.pumpAndSettle();
        expect(find.byTooltip('لغو پاسخ'), findsOneWidget);
        await cleanup(tester, client);
      }
    },
  );

  testWidgets(
    'Opposite empty space opens reaction menu without an add-reaction icon',
    (tester) async {
      final client = await chat(tester, [message(1)]);
      expect(find.byIcon(Icons.add_reaction_outlined), findsNothing);
      final row = tester.getRect(find.byKey(const ValueKey('party-message-1')));
      await tester.tapAt(Offset(row.left + 5, row.center.dy));
      await tester.pumpAndSettle();
      expect(find.text('❤️'), findsOneWidget);
      await cleanup(tester, client);
    },
  );

  testWidgets(
    'Media resolution prevents duplicate opens and reports failure; header opens detail',
    (tester) async {
      final pending = Completer<void>();
      var opens = 0, details = 0;
      PartyHub.instance.openMedia = (_, _, _) {
        opens++;
        return pending.future;
      };
      PartyHub.instance.openDetails = (_, _) async {
        details++;
      };
      final client = await chat(tester, [message(1, media: true)]);
      await tester.tap(find.text('تماشای مستقل'));
      await tester.pump();
      expect(find.text('در حال بارگذاری…'), findsOneWidget);
      final button = tester.widget<OutlinedButton>(
        find
            .ancestor(
              of: find.text('در حال بارگذاری…'),
              matching: find.byWidgetPredicate((w) => w is OutlinedButton),
            )
            .first,
      );
      expect(button.onPressed, isNull);
      expect(opens, 1);
      pending.completeError(const PartyException('خطای دریافت قسمت'));
      await tester.pumpAndSettle();
      expect(find.text('خطای دریافت قسمت'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('party-media-details-1')));
      await tester.pumpAndSettle();
      expect(details, 1);
      await cleanup(tester, client);
    },
  );

  testWidgets(
    'Other-app media stays visible with a notice and cannot open a player',
    (tester) async {
      var opens = 0;
      for (final source in ['anime', 'hentai', 'movie']) {
        PartyHub.instance.openMedia = (_, _, _) async {
          opens++;
        };
        final media = message(1, media: true, source: source);
        if (source == 'movie') {
          media['payload'] = {
            ...Map<String, dynamic>.from(media['payload'] as Map),
            'adult': true,
          };
        }
        final client = await chat(tester, [media]);
        expect(find.textContaining('MBNime'), findsOneWidget);
        await tester.tap(find.text('تماشای مستقل'));
        await tester.pumpAndSettle();
        expect(opens, 0);
        await cleanup(tester, client);
      }
    },
  );

  testWidgets(
    'Reply loads missing context and highlights original for one second',
    (tester) async {
      var aroundCalls = 0;
      final client = await chat(
        tester,
        [message(60, reply: 1)],
        around: [message(1), message(2)],
        onAround: () => aroundCalls++,
      );
      await tester.tap(find.byKey(const ValueKey('party-reply-60')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(aroundCalls, 1);
      expect(find.byKey(const ValueKey('party-message-1')), findsOneWidget);
      Color? color() =>
          (tester
                      .widget<AnimatedContainer>(
                        find.descendant(
                          of: find.byKey(const ValueKey('party-message-1')),
                          matching: find.byType(AnimatedContainer),
                        ),
                      )
                      .decoration
                  as BoxDecoration)
              .color;
      final highlighted = color();
      await tester.pump(const Duration(milliseconds: 699));
      expect(color(), highlighted);
      await tester.pump(const Duration(milliseconds: 2));
      expect(color(), isNot(highlighted));
      await cleanup(tester, client);
    },
  );

  testWidgets(
    'Separate season dropdown resets episode and returns selected episode',
    (tester) async {
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await showDialog<String>(
                  context: context,
                  builder: (_) => const PartyEpisodePicker(
                    seasons: [
                      PartySeasonChoice('s1', 'فصل اول', [
                        PartyEpisodeChoice('e1', 'قسمت اول'),
                        PartyEpisodeChoice('e2', 'قسمت دوم'),
                      ]),
                      PartySeasonChoice('s2', 'فصل دوم', [
                        PartyEpisodeChoice('e3', 'قسمت سوم'),
                      ]),
                    ],
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('party-season-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('فصل دوم').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('party-episode-picker-s2')),
        findsOneWidget,
      );
      expect(find.text('قسمت سوم'), findsOneWidget);
      await tester.tap(find.text('ادامه'));
      await tester.pumpAndSettle();
      expect(selected, 'e3');
    },
  );
}
