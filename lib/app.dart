import 'services/device_performance.dart';
import 'services/cross_app_auth.dart';
import 'dart:async';
import 'services/session_watch.dart';
import 'services/browser_features.dart';
import 'widgets/session_devices_dialog.dart';

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
import 'widgets/server_status_gate.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'screens/splash_screen.dart';
import 'services/animeon_api.dart';
import 'services/accessibility_service.dart';
import 'screens/update_screen.dart';

class MbnimeApp extends StatefulWidget {
  const MbnimeApp({super.key, this.sharedTokenReader});

  final Future<String?> Function()? sharedTokenReader;

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
  bool _sharedLoginBusy = false;
  bool _loginBusy = false;
  bool _terminating = false;
  late final SessionWatch _sessionWatch = SessionWatch(_forceLogout);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _accountTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      unawaited(_checkAccount());
      unawaited(_restoreSharedLogin());
    });
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
    _sessionWatch.dispose();
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
      unawaited(_restoreSharedLogin());
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
        await _forceLogout(
          error.message.isNotEmpty
              ? error.message
              : 'نشست شما پایان یافته است؛ دوباره وارد شوید.',
        );
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
    if (kIsWeb) BrowserFeatures.stop();
    appNavigatorKey.currentState?.popUntil((route) => route.isFirst);
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
          if (_session.forcedLogoutMessage == null) {
            await _restoreSharedLogin(startup: true);
          }
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
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final ctx = appNavigatorKey.currentContext;
              if (ctx != null) {
                MbnSync.instance.checkOtherAppSettingsPrompt(ctx);
              }
            });
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

  Future<void> _restoreSharedLogin({bool startup = false}) async {
    if (_loginBusy ||
        _sharedLoginBusy ||
        (!startup && _restoring) ||
        (!startup && _session.isLoggedIn) ||
        _terminating ||
        !mounted) {
      return;
    }
    _sharedLoginBusy = true;
    try {
      final token =
          await (widget.sharedTokenReader?.call() ??
              CrossAppAuth.readSiblingToken(siblingId: 'MBNMovie'));
      if (token == null) {
        final current = _session.server.token;
        if (startup && current != null) {
          await CrossAppAuth.saveSharedToken(
            token: current,
            email: _session.email ?? "",
          );
        }
        return;
      }
      if (!mounted || _terminating || (!startup && _session.isLoggedIn)) return;
      await _session.loginWithToken(token);
      if (_session.userId != null) {
        await MbnSync.instance.bindAccount(_session.userId!);
      }
      MbnSync.instance.configure(server: _session.server);
      if (mounted) setState(() {});
      unawaited(MbnSync.instance.syncAll());
    } catch (_) {
      // An expired/revoked sibling token never creates a replacement session.
    } finally {
      _sharedLoginBusy = false;
    }
  }

  void _refresh() => setState(() {});

  Future<void> _checkSibling() async {
    final available = await AppLinks.isSiblingAvailable(siblingMovie);
    if (mounted && _siblingAvailable != available) {
      setState(() => _siblingAvailable = available);
    }
  }

  Future<bool> _loginWithCapacity(
    Future<void> Function() action,
    String identifier,
  ) async {
    _loginBusy = true;
    try {
      await action();
      return true;
    } on MbnServerException catch (error) {
      if (error.details?['code'] != 'session_limit') rethrow;
      final ctx = appNavigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) rethrow;
      final result = await showSessionDevicesDialog(
        ctx,
        error.details!,
        _session.server.postJson,
      );
      if (result == null) return false;
      await _session.loginWithHandoff(result, fallbackIdentifier: identifier);
      return true;
    } finally {
      _loginBusy = false;
    }
  }

  Future<void> _beginHandoff() async {
    final token = await CrossAppAuth.readSiblingToken(siblingId: 'MBNMovie');
    if (token == null || token.isEmpty) {
      appMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text(
            'حساب فعالی در برنامه MBNMovie یافت نشد. ابتدا در MBNMovie وارد شوید.',
          ),
        ),
      );
      return;
    }
    try {
      if (!await _loginWithCapacity(
        () => _session.loginWithToken(token),
        'کاربر',
      )) {
        return;
      }
      if (_session.userId != null) {
        await MbnSync.instance.bindAccount(_session.userId!);
      }
      MbnSync.instance.configure(server: _session.server);
      await MbnSync.instance.syncAll();
      if (mounted) {
        setState(() {});
        final displayName = _session.email ?? '';
        appMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(
              displayName.isNotEmpty
                  ? 'ورود با حساب MBNMovie ($displayName)'
                  : 'ورود با حساب MBNMovie با موفقیت انجام شد.',
            ),
          ),
        );
      }
    } catch (_) {
      appMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text(
            'ورود با حساب MBNMovie ناموفق بود؛ لطفاً دوباره تلاش کنید.',
          ),
        ),
      );
    }
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
          appMessengerKey.currentState?.showSnackBar(
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
      if (!await _loginWithCapacity(() async {
        final data = await AuthHandoff.consume(
          post: _session.server.postJson,
          id: id,
          targetApp: 'anime',
        );
        if (data == null) return;
        await _session.loginWithHandoff(data, fallbackIdentifier: identifier);
      }, identifier)) {
        return;
      }
      if (_session.userId != null) {
        await MbnSync.instance.bindAccount(_session.userId!);
      }
      MbnSync.instance.configure(server: _session.server);
      await MbnSync.instance.syncAll();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        appMessengerKey.currentState?.showSnackBar(
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
    _sessionWatch.track(_session.server.token, _session.server.baseUrl);
    return ListenableBuilder(
      listenable: AccessibilityService.instance,
      builder: (context, _) {
        final access = AccessibilityService.instance;
        return MaterialApp(
          navigatorKey: appNavigatorKey,
          scaffoldMessengerKey: appMessengerKey,
          debugShowCheckedModeBanner: false,
          title: 'MBNime',
          theme: AnimeTheme.buildTheme(
            highContrast: access.highContrast,
            visualDensity: isAndroidTv
                ? VisualDensity.standard
                : access.visualDensity,
            reduceMotion: access.reduceMotion,
            boldText: access.boldText,
            focusColor: isAndroidTv
                ? AnimeColors.cyan.withValues(alpha: .4)
                : null,
            hoverColor: isAndroidTv
                ? AnimeColors.cyan.withValues(alpha: .15)
                : null,
          ),
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
              child: MandatoryUpdateGate(
                child: ServerStatusGate(
                  child: TvNavigation(
                    child: AccessibilityAppWrapper(child: child!),
                  ),
                ),
              ),
            ),
          ),
          home: AnimatedSwitcher(
            duration: access.reduceMotion
                ? Duration.zero
                : Duration(
                    milliseconds: DevicePerformance.lightweight ? 180 : 650,
                  ),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) =>
                access.reduceMotion || DevicePerformance.lightweight
                ? child
                : FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(
                        begin: .985,
                        end: 1,
                      ).animate(animation),
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
                      if (!await _loginWithCapacity(
                        () => _session.login(email: email, password: password),
                        email,
                      )) {
                        return;
                      }
                      MbnSync.instance.configure(server: _session.server);
                      if (_session.userId != null) {
                        await MbnSync.instance.bindAccount(_session.userId!);
                      }
                      await MbnSync.instance.syncAll();
                      _refresh();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        final ctx = appNavigatorKey.currentContext;
                        if (ctx != null) {
                          MbnSync.instance.checkOtherAppSettingsPrompt(ctx);
                        }
                      });
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
      },
    );
  }
}

class AccessibilityAppWrapper extends StatelessWidget {
  const AccessibilityAppWrapper({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AccessibilityService.instance,
      builder: (context, _) {
        final access = AccessibilityService.instance;
        final uiScale = access.uiScale;
        final textScale = access.textScale;

        final rawMedia = MediaQuery.of(context);
        final baseMedia = rawMedia.copyWith(
          textScaler: TextScaler.linear(textScale),
          boldText: access.boldText,
          disableAnimations: access.reduceMotion,
        );

        if (rawMedia.size.isEmpty ||
            rawMedia.size.width <= 0 ||
            rawMedia.size.height <= 0 ||
            (uiScale - 1.0).abs() < 0.005) {
          return MediaQuery(data: baseMedia, child: child);
        }

        final targetWidth = rawMedia.size.width / uiScale;
        final targetHeight = rawMedia.size.height / uiScale;

        final scaledMedia = baseMedia.copyWith(
          size: Size(targetWidth, targetHeight),
          padding: EdgeInsets.fromLTRB(
            rawMedia.padding.left / uiScale,
            rawMedia.padding.top / uiScale,
            rawMedia.padding.right / uiScale,
            rawMedia.padding.bottom / uiScale,
          ),
          viewPadding: EdgeInsets.fromLTRB(
            rawMedia.viewPadding.left / uiScale,
            rawMedia.viewPadding.top / uiScale,
            rawMedia.viewPadding.right / uiScale,
            rawMedia.viewPadding.bottom / uiScale,
          ),
          viewInsets: EdgeInsets.fromLTRB(
            rawMedia.viewInsets.left / uiScale,
            rawMedia.viewInsets.top / uiScale,
            rawMedia.viewInsets.right / uiScale,
            rawMedia.viewInsets.bottom / uiScale,
          ),
        );

        return SizedBox(
          width: rawMedia.size.width,
          height: rawMedia.size.height,
          child: FittedBox(
            fit: BoxFit.fill,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: targetWidth,
              height: targetHeight,
              child: MediaQuery(data: scaledMedia, child: child),
            ),
          ),
        );
      },
    );
  }
}
