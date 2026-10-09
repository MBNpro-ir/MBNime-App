import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/device_performance.dart';

/// Keeps the scoped adult accent during the route-overlay transition.
class WatchEpisodeButton extends StatelessWidget {
  const WatchEpisodeButton({
    super.key,
    required this.loading,
    required this.hasPlayable,
    required this.desktop,
    required this.adult,
    required this.pickerBuilder,
  });
  final bool loading, hasPlayable, desktop, adult;
  final WidgetBuilder pickerBuilder;
  @override
  Widget build(BuildContext context) {
    final enabled = !loading && hasPlayable;
    final watchTheme = adult
        ? hentaiTheme(Theme.of(context))
        : Theme.of(context);
    if (DevicePerformance.appleMobileWeb) {
      return Theme(
        data: watchTheme,
        child: FilledButton.icon(
          onPressed: enabled
              ? () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => Theme(
                      data: watchTheme,
                      child: Builder(builder: pickerBuilder),
                    ),
                  ),
                )
              : null,
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(loading ? 'در حال دریافت لینک پخش…' : 'شروع تماشا'),
        ),
      );
    }
    return OpenContainer<void>(
      transitionType: ContainerTransitionType.fade,
      transitionDuration: Duration(milliseconds: desktop ? 500 : 300),
      closedColor: Colors.transparent,
      middleColor: AnimeColors.surfaceHigh,
      openColor: AnimeColors.background,
      closedElevation: 0,
      openElevation: 0,
      closedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(desktop ? 18 : 40),
      ),
      openShape: const RoundedRectangleBorder(),
      tappable: false,
      openBuilder: (context, _) => Theme(
        data: watchTheme,
        child: Builder(builder: pickerBuilder),
      ),
      closedBuilder: (context, openContainer) => Theme(
        data: watchTheme,
        child: SizedBox(
          width: double.infinity,
          height: desktop ? 176 : null,
          child: FilledButton(
            onPressed: enabled ? openContainer : null,
            style: FilledButton.styleFrom(
              minimumSize: desktop ? const Size(210, 176) : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(desktop ? 18 : 40),
              ),
            ),
            child: desktop
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 62,
                        height: 62,
                        decoration: const BoxDecoration(
                          color: Colors.black12,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow_rounded, size: 40),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        loading ? 'در حال دریافت…' : 'شروع تماشا',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (!loading) ...[
                        const SizedBox(height: 5),
                        const Text(
                          'انتخاب فصل و قسمت',
                          style: TextStyle(fontSize: 11, color: Colors.black54),
                        ),
                      ],
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.play_arrow_rounded),
                      const SizedBox(width: 8),
                      Text(loading ? 'در حال دریافت لینک پخش…' : 'شروع تماشا'),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
