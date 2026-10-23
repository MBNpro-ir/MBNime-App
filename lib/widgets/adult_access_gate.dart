import 'package:flutter/material.dart';
import '../services/adult_access.dart';

/// Unmount sensitive screens (and their player) as soon as access is revoked.
class AdultAccessGate extends StatefulWidget {
  const AdultAccessGate({
    super.key,
    this.restricted = true,
    required this.builder,
  });
  final bool restricted;
  final WidgetBuilder builder;

  @override
  State<AdultAccessGate> createState() => _AdultAccessGateState();
}

class _AdultAccessGateState extends State<AdultAccessGate> {
  bool _wasAllowed = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.restricted) return widget.builder(context);
    return ValueListenableBuilder<bool>(
      valueListenable: AdultAccess.instance.changes,
      builder: (context, _, child) {
        final allowed = AdultAccess.instance.allowed;
        if (_wasAllowed && !allowed) {
          // Sheets and dialogs live on the Navigator above this subtree.
          // Close them too, so revoked episode titles cannot remain visible.
          final navigator = Navigator.of(context);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (navigator.mounted && !AdultAccess.instance.allowed) {
              navigator.popUntil((route) => route.isFirst);
            }
          });
        }
        _wasAllowed = allowed;
        return allowed
            ? widget.builder(context)
            : Scaffold(
                appBar: AppBar(title: const Text('دسترسی محدود')),
                body: const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'دسترسی این بخش باید توسط مدیریت فعال شود.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
      },
    );
  }
}
