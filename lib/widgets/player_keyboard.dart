import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum PlayerCommand {
  toggle,
  back,
  forward,
  volumeUp,
  volumeDown,
  mute,
  fullscreen,
  exitFullscreen,
  faster,
  slower,
  subtitles,
  tracks,
  subtitleSettings,
  fit,
  home,
  end,
  help,
}

class PlayerKeyboard extends StatelessWidget {
  const PlayerKeyboard({
    super.key,
    required this.child,
    required this.onCommand,
    required this.onSeekFraction,
    required this.onFocus,
  });
  final Widget child;
  final void Function(PlayerCommand) onCommand;
  final void Function(double) onSeekFraction;
  final VoidCallback onFocus;
  static const help =
      'Space / K: پخش و توقف\n← / →: ده ثانیه عقب و جلو\n↑ / ↓: صدا\nM: قطع صدا\nF / F11: تمام‌صفحه\nEsc: خروج از تمام‌صفحه\n[ / ]: سرعت پخش\n0 تا 9: رفتن به درصد ویدئو\nHome / End: ابتدا و انتها\nC: زیرنویس روشن/خاموش\nA: ترک صدا و زیرنویس\nS: تنظیمات زیرنویس\nV: اندازهٔ تصویر\nTab و Shift+Tab: جابه‌جایی بین کنترل‌ها\nEnter: فعال‌کردن دکمهٔ انتخاب‌شده\nF1: راهنمای کلیدها';

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      for (final pair in const [
        (LogicalKeyboardKey.space, PlayerCommand.toggle),
        (LogicalKeyboardKey.keyK, PlayerCommand.toggle),
        (LogicalKeyboardKey.mediaPlayPause, PlayerCommand.toggle),
        (LogicalKeyboardKey.arrowLeft, PlayerCommand.back),
        (LogicalKeyboardKey.arrowRight, PlayerCommand.forward),
        (LogicalKeyboardKey.arrowUp, PlayerCommand.volumeUp),
        (LogicalKeyboardKey.arrowDown, PlayerCommand.volumeDown),
        (LogicalKeyboardKey.keyM, PlayerCommand.mute),
        (LogicalKeyboardKey.keyF, PlayerCommand.fullscreen),
        (LogicalKeyboardKey.f11, PlayerCommand.fullscreen),
        (LogicalKeyboardKey.escape, PlayerCommand.exitFullscreen),
        (LogicalKeyboardKey.bracketRight, PlayerCommand.faster),
        (LogicalKeyboardKey.bracketLeft, PlayerCommand.slower),
        (LogicalKeyboardKey.keyC, PlayerCommand.subtitles),
        (LogicalKeyboardKey.keyA, PlayerCommand.tracks),
        (LogicalKeyboardKey.keyS, PlayerCommand.subtitleSettings),
        (LogicalKeyboardKey.keyV, PlayerCommand.fit),
        (LogicalKeyboardKey.home, PlayerCommand.home),
        (LogicalKeyboardKey.end, PlayerCommand.end),
        (LogicalKeyboardKey.f1, PlayerCommand.help),
      ])
        SingleActivator(pair.$1): () => onCommand(pair.$2),
      for (var i = 0; i < 10; i++)
        SingleActivator(
          LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + i),
        ): () =>
            onSeekFraction(i / 10),
    },
    child: _PlayerKeyScope(
      onCommand: onCommand,
      onFocus: onFocus,
      child: child,
    ),
  );
}

/// Slider shortcuts reverse direction in RTL. Capture physical seek keys only
/// inside this player focus subtree, before a focused slider can consume them.
class _PlayerKeyScope extends StatefulWidget {
  const _PlayerKeyScope({
    required this.child,
    required this.onCommand,
    required this.onFocus,
  });
  final Widget child;
  final ValueChanged<PlayerCommand> onCommand;
  final VoidCallback onFocus;
  @override
  State<_PlayerKeyScope> createState() => _PlayerKeyScopeState();
}

class _PlayerKeyScopeState extends State<_PlayerKeyScope> {
  final _focus = FocusNode(debugLabel: 'Player physical keys');
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_key);
  }

  KeyEventResult _key(KeyEvent event) {
    if (!_focus.hasFocus ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final command = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowRight => PlayerCommand.forward,
      LogicalKeyboardKey.arrowLeft => PlayerCommand.back,
      LogicalKeyboardKey.arrowUp => PlayerCommand.volumeUp,
      LogicalKeyboardKey.arrowDown => PlayerCommand.volumeDown,
      _ => null,
    };
    if (command == null) return KeyEventResult.ignored;
    widget.onCommand(command);
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_key);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    autofocus: true,
    onFocusChange: (focused) {
      if (focused) widget.onFocus();
    },
    child: widget.child,
  );
}
