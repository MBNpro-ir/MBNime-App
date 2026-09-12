import 'package:flutter/material.dart';

/// Subtle press-down feedback for tappable cards: scales to 96% while
/// pressed with a snappy spring back. Purely visual, keeps hit-testing
/// and semantics of [child] intact.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.scale = .96,
  });

  final Widget child;
  final VoidCallback onTap;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: widget.onTap,
    onTapDown: (_) => _setPressed(true),
    onTapUp: (_) => _setPressed(false),
    onTapCancel: () => _setPressed(false),
    child: AnimatedScale(
      scale: _pressed ? widget.scale : 1,
      duration: Duration(milliseconds: _pressed ? 65 : 150),
      curve: Curves.easeOutCubic,
      child: widget.child,
    ),
  );
}
