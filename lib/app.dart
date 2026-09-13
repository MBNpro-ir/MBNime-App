import 'package:flutter/material.dart';

import 'core/desktop_window_frame.dart';
import 'core/session_store.dart';
import 'core/theme.dart';
import 'core/platform_ui.dart';
import 'widgets/tv_navigation.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'screens/splash_screen.dart';
import 'services/animeon_api.dart';
import 'screens/update_screen.dart';

class MbnimeApp extends StatefulWidget {
  const MbnimeApp({super.key});

  @override
  State<MbnimeApp> createState() => _MbnimeAppState();
}

class _MbnimeAppState extends State<MbnimeApp> {
  final AnimeOnApi _api = AnimeOnApi();
  late final SessionStore _session = SessionStore(_api);
  bool _restoring = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      await Future.wait([
        _session.restore(),
        Future<void>.delayed(const Duration(milliseconds: 1450)),
      ]);
    } catch (_) {
      // restore() itself never throws; this guard only ensures a storage
      // failure can never brick the app on the splash screen.
    }
    if (mounted) setState(() => _restoring = false);
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      scaffoldMessengerKey: appMessengerKey,
      debugShowCheckedModeBanner: false,
      title: 'MBNime',
      theme: isAndroidTv
          ? AnimeTheme.dark.copyWith(
              visualDensity: VisualDensity.standard,
              focusColor: AnimeColors.cyan.withValues(alpha: .4),
              hoverColor: AnimeColors.cyan.withValues(alpha: .15),
            )
          : AnimeTheme.dark,
      locale: const Locale('fa', 'IR'),
      builder: (context, child) => DesktopWindowFrame(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: TvNavigation(child: MandatoryUpdateGate(child: child!)),
        ),
      ),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 650),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: .985, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: _restoring
            ? const SplashScreen(key: ValueKey('splash'))
            : _session.isLoggedIn
            ? MainShell(
                key: const ValueKey('main'),
                email: _session.email!,
                api: _api,
                onLogout: () async {
                  await _session.logout();
                  _refresh();
                },
              )
            : LoginScreen(
                key: const ValueKey('login'),
                onLogin: (email, password) async {
                  await _session.login(email: email, password: password);
                  _refresh();
                },
                onLoginWithCode: (code) async {
                  await _session.loginWithCode(code);
                  _refresh();
                },
                onRegister: (name, email, mobile, password) async {
                  await _session.register(
                    name: name,
                    email: email,
                    mobile: mobile,
                    password: password,
                  );
                  _refresh();
                },
              ),
      ),
    );
  }
}
