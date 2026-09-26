import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/desktop_window_frame.dart';
import 'core/session_store.dart';
import 'core/theme.dart';
import 'core/platform_ui.dart';
import 'services/mbn_sync.dart';
import 'services/mbn_server.dart';
import 'services/auth_handoff.dart';
import 'services/app_links.dart';
import 'services/app_updater.dart';
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
  Timer? _syncTimer;
  Timer? _handoffTimer;
  bool _handoffBusy = false;
  bool _siblingAvailable = false;
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
    _syncTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(MbnSync.instance.syncAll()),
    );
    _handoffTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_checkHandoff()),
    );
    unawaited(_checkSibling());
    _restoreSession();
  }

  @override
  void dispose() {
    _accountTimer?.cancel();
    _syncTimer?.cancel();
    _handoffTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAccount();
      UpdatePresentation.checkNow();
      unawaited(MbnSync.instance.syncAll());
      unawaited(_checkSibling());
      unawaited(_checkHandoff());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(MbnSync.instance.flushPending());
    }
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
            if (_session.userId != null) {
              await MbnSync.instance.bindAccount(_session.userId!);
            }
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

  Future<void> _checkSibling() async {
    final available = await AppLinks.isSiblingAvailable(siblingMovie);
    if (mounted && _siblingAvailable != available) {
      setState(() => _siblingAvailable = available);
    }
  }

  Future<void> _beginHandoff() async {
    final id = await AuthHandoff.create(
      post: _session.server.postJson,
      sourceApp: 'movie',
      targetApp: 'anime',
    );
    final opened = await AppLinks.launchHandoff(siblingMovie, 'request:$id');
    if (!opened) {
      await AuthHandoff.clear(id);
      throw StateError('برنامهٔ دیگر باز نشد.');
    }
    exit(0);
  }

  Future<void> _checkHandoff() async {
    if (_handoffBusy ||
        _restoring ||
        !mounted ||
        AppUpdater.instance.startupCheckPending ||
        AppUpdater.instance.requiredRelease != null) {
      return;
    }
    _handoffBusy = true;
    try {
      final message = await AppLinks.takeHandoff('MBNime');
      if (message == null) return;
      final parts = message.split(':');
      if (parts.length != 2 || parts[1].length < 20) return;
      if (parts[0] == 'request') {
        await _respondHandoff(parts[1]);
      } else if (parts[0] == 'return') {
        await _offerHandoff(parts[1]);
      }
    } finally {
      _handoffBusy = false;
    }
  }

  Future<void> _respondHandoff(String id) async {
    if (_session.isLoggedIn && _session.server.token != null) {
      final approved =
          await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              title: const Text('ورود مشترک به MBNMovie'),
              content: Text(
                'حساب ${_session.email} در MBNime فعال است. اجازه می‌دهی همین حساب در MBNMovie پیشنهاد شود؟',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('خیر'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('بله، پیشنهاد بده'),
                ),
              ],
            ),
          ) ??
          false;
      try {
        if (approved) {
          await AuthHandoff.approve(post: _session.server.postJson, id: id);
        } else {
          await AuthHandoff.deny(post: _session.server.postJson, id: id);
        }
      } catch (_) {}
    }
    await AppLinks.launchHandoff(siblingMovie, 'return:$id');
  }

  Future<void> _offerHandoff(String id) async {
    try {
      final status = await AuthHandoff.status(
        post: _session.server.postJson,
        id: id,
      );
      if (status == null || status['state'] != 'approved') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'حساب فعالی در برنامهٔ دیگر تأیید نشد؛ می‌توانی دستی وارد شوی.',
              ),
            ),
          );
        }
        return;
      }
      final identifier = status['identifier']?.toString() ?? '';
      if (!mounted) return;
      final useIt =
          await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              title: const Text('استفاده از حساب MBNMovie'),
              content: Text(
                'در MBNMovie با $identifier وارد شده‌ای. می‌خواهی همین حساب در MBNime استفاده شود؟',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('ورود با حساب دیگر'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('استفاده از همین حساب'),
                ),
              ],
            ),
          ) ??
          false;
      if (!useIt) return;
      final data = await AuthHandoff.consume(
        post: _session.server.postJson,
        id: id,
        targetApp: 'anime',
      );
      if (data == null) return;
      await _session.loginWithHandoff(data, fallbackIdentifier: identifier);
      if (_session.userId != null) {
        await MbnSync.instance.bindAccount(_session.userId!);
      }
      MbnSync.instance.configure(server: _session.server);
      await MbnSync.instance.syncAll();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ورود مشترک انجام نشد؛ دوباره تلاش کن.'),
          ),
        );
      }
    } finally {
      await AuthHandoff.clear(id);
    }
  }

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
          child: MandatoryUpdateGate(child: TvNavigation(child: child!)),
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
                    await MbnSync.instance.flushPending();
                  } catch (_) {}
                  MbnSync.instance.clear();
                  await _session.logout();
                  _refresh();
                },
              )
            : LoginScreen(
                key: const ValueKey('login'),
                onUseOtherApp: _siblingAvailable ? _beginHandoff : null,
                onLogin: (email, password) async {
                  await _session.login(email: email, password: password);
                  MbnSync.instance.configure(server: _session.server);
                  if (_session.userId != null) {
                    await MbnSync.instance.bindAccount(_session.userId!);
                  }
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
