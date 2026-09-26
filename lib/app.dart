import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/desktop_window_frame.dart';
import 'core/session_store.dart';
import 'core/theme.dart';
import 'core/platform_ui.dart';
import 'services/mbn_sync.dart';
import 'services/mbn_server.dart';
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

class _MbnimeAppState extends State<MbnimeApp> with WidgetsBindingObserver {
  static const _debugIdentifier = String.fromEnvironment(
    'MBN_DEBUG_IDENTIFIER',
  );
  static const _debugPassword = String.fromEnvironment('MBN_DEBUG_PASSWORD');
  final AnimeOnApi _api = AnimeOnApi();
  late final SessionStore _session = SessionStore(_api);
  bool _restoring = true;
  Timer? _accountTimer;
  bool _checkingAccount = false;
  bool _terminating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _accountTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _checkAccount(),
    );
    _restoreSession();
  }

  @override
  void dispose() {
    _accountTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkAccount();
  }

  Future<void> _checkAccount() async {
    if ((_session.server.token == null && !_session.isLoggedIn) ||
        _checkingAccount ||
        _terminating) {
      return;
    }
    _checkingAccount = true;
    try {
      final message = await _session.accountRestriction();
      if (message != null) {
        await _forceLogout(message);
      } else if (!_session.isLoggedIn) {
        await _session.restore();
        if (mounted && _session.isLoggedIn) setState(() {});
      }
    } on MbnServerException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        await _forceLogout('نشست شما پایان یافته است؛ دوباره وارد شوید.');
      }
    } catch (_) {
      // Connectivity errors keep the current session.
    } finally {
      _checkingAccount = false;
    }
  }

  Future<void> _forceLogout(String message) async {
    if (_terminating || !mounted) return;
    _terminating = true;
    MbnSync.instance.clear();
    try {
      await _session.logout();
    } catch (_) {
      // The durable signed-out marker still blocks restoration.
    }
    if (!mounted) return;
    appNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showLogoutDialog(message),
    );
  }

  Future<void> _showLogoutDialog(String message) async {
    final dialogContext = appNavigatorKey.currentContext;
    if (!mounted || dialogContext == null) return;
    await showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('خروج از حساب'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('رفتن به ورود'),
          ),
        ],
      ),
    );
    _terminating = false;
  }

  Future<void> _restoreSession() async {
    try {
      await Future.wait([
        () async {
          await _session.restore();
          if (!_session.isLoggedIn &&
              _session.forcedLogoutMessage == null &&
              kDebugMode &&
              _debugIdentifier.isNotEmpty &&
              _debugPassword.isNotEmpty) {
            await _session.login(
              email: _debugIdentifier,
              password: _debugPassword,
            );
          }
          if (_session.isLoggedIn) {
            MbnSync.instance.configure(server: _session.server);
            await MbnSync.instance.syncAll();
          }
        }(),
        Future<void>.delayed(const Duration(milliseconds: 1450)),
      ]);
    } catch (_) {
      // restore() itself never throws; this guard only ensures a storage
      // failure can never brick the app on the splash screen.
    }
    if (mounted) setState(() => _restoring = false);
    final message = _session.forcedLogoutMessage;
    if (mounted && message != null) {
      _terminating = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showLogoutDialog(message),
      );
    }
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
      // Actually localize framework-provided strings (back-button tooltips,
      // selection menus, accessibility labels): a bare `locale` + forced
      // RTL only affects app-authored text/layout, leaving Flutter's own
      // controls in English without delegates + supportedLocales.
      supportedLocales: const [Locale('fa', 'IR'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
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
                server: _session.server,
                api: _api,
                onLogout: () async {
                  try {
                    await MbnSync.instance.pushAll();
                  } catch (_) {}
                  MbnSync.instance.clear();
                  await _session.logout();
                  _refresh();
                },
              )
            : LoginScreen(
                key: const ValueKey('login'),
                onLogin: (email, password) async {
                  await _session.login(email: email, password: password);
                  MbnSync.instance.configure(server: _session.server);
                  await MbnSync.instance.syncAll();
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
