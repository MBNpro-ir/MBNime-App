import 'package:flutter/material.dart';

/// Physical left-to-right reply gesture, independent of the chat's RTL locale.
/// The bubble keeps its normal controls; the empty space opens its menu.
class PartyMessageInteraction extends StatefulWidget {
  const PartyMessageInteraction({
    super.key,
    required this.child,
    required this.onReply,
    required this.onReaction,
  });
  final Widget child;
  final VoidCallback? onReply, onReaction;
  @override
  State<PartyMessageInteraction> createState() =>
      _PartyMessageInteractionState();
}

class _PartyMessageInteractionState extends State<PartyMessageInteraction> {
  double _drag = 0;
  void _end() {
    final reply = _drag >= 56;
    setState(() => _drag = 0);
    if (reply) widget.onReply?.call();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onHorizontalDragUpdate: widget.onReply == null
        ? null
        : (details) =>
              setState(() => _drag = (_drag + details.delta.dx).clamp(0, 80)),
    onHorizontalDragEnd: widget.onReply == null ? null : (_) => _end(),
    onHorizontalDragCancel: () => setState(() => _drag = 0),
    child: Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey('party-message-empty-space'),
            behavior: HitTestBehavior.opaque,
            onTap: widget.onReaction,
          ),
        ),
        TweenAnimationBuilder<double>(
          tween: Tween(end: _drag),
          duration: Duration(milliseconds: _drag == 0 ? 160 : 0),
          builder: (context, value, child) =>
              Transform.translate(offset: Offset(value, 0), child: child),
          child: widget.child,
        ),
      ],
    ),
  );
}
