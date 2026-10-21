import 'dart:math' as math;
import 'package:flutter/services.dart';
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
  bool _checkingAccount = false;
  bool _restoringRemote = false;
  bool _terminating = false;
  late final SessionWatch _sessionWatch = SessionWatch(
    _forceLogout,
    app: 'anime',
    onSync: () => MbnSync.instance.syncAll(),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _accountTimer = Timer.periodic(
      DevicePerformance.appleMobileWeb
          ? const Duration(seconds: 30)
          : const Duration(seconds: 6),
      (_) => unawaited(_checkAccount()),
    );
    _syncTimer = Timer.periodic(
      DevicePerformance.appleMobileWeb
          ? const Duration(minutes: 5)
          : const Duration(seconds: 60),
      (_) => unawaited(MbnSync.instance.syncAll()),
    );
    _restoreSession();
  }

  @override
  void dispose() {
    _sessionWatch.dispose();
    _accountTimer?.cancel();
    _syncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAccount();
      UpdatePresentation.checkNow();
      unawaited(MbnSync.instance.syncAll());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(MbnSync.instance.flushPending());
    }
  }

  Future<void> _checkAccount() async {
    if ((_session.server.token == null && !_session.isLoggedIn) ||
        _checkingAccount ||
        _restoringRemote ||
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
    var localSession = false;
    try {
      // Render from the cached account first. Remote validation and sync run
      // after the first interactive frame, so a slow Safari request cannot
      // swallow the opening taps behind the splash screen.
      localSession = await _session.restoreLocal().timeout(
        const Duration(seconds: 2),
        onTimeout: () => false,
      );
      if (!localSession &&
          kDebugMode &&
          _debugIdentifier.isNotEmpty &&
          _debugPassword.isNotEmpty) {
        await _session.login(email: _debugIdentifier, password: _debugPassword);
        localSession = _session.isLoggedIn;
      }
    } catch (_) {
      // restore() itself never throws; this guard only ensures a storage
      // failure can never brick the app on the splash screen.
    }
    if (mounted) setState(() => _restoring = false);
    if (localSession) unawaited(_refreshSessionInBackground());
  }

  Future<void> _refreshSessionInBackground() async {
    if (_restoringRemote || !_session.isLoggedIn) return;
    _restoringRemote = true;
    try {
      await _session.restore().timeout(const Duration(seconds: 25));
      if (_session.isLoggedIn) {
        if (_session.userId != null) {
          await MbnSync.instance.bindAccount(_session.userId!);
        }
        MbnSync.instance.configure(server: _session.server);
        unawaited(MbnSync.instance.syncAll());
      }
    } catch (_) {
      // Cached data remains usable when the account server is slow/offline.
    } finally {
      _restoringRemote = false;
      if (mounted) {
        final message = _session.forcedLogoutMessage;
        setState(() {});
        if (message != null) {
          _terminating = true;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _showLogoutDialog(message),
          );
        }
      }
    }
  }

  void _refresh() => setState(() {});

  Future<bool> _loginWithCapacity(
    Future<void> Function() action,
    String identifier,
  ) async {
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
    } finally {}
  }

  Future<void> _beginHandoff() async {
    final token =
        await (widget.sharedTokenReader?.call() ??
            CrossAppAuth.readSiblingToken(siblingId: 'MBNMovie'));
    if (!mounted || _terminating) return;
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
      MbnSync.instance.beginSettingsChoice();
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

  @override
  Widget build(BuildContext context) {
    // WebKit can evict/reload a PWA while an SSE connection is open. The
    // bounded foreground account poll remains active on Apple mobile web.
    _sessionWatch.track(
      DevicePerformance.appleMobileWeb ? null : _session.server.token,
      _session.server.baseUrl,
    );
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
            duration: access.reduceMotion || DevicePerformance.appleMobileWeb
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
                    onUseOtherApp: _beginHandoff,
                    onLogin: (email, password) async {
                      if (!await _loginWithCapacity(
                        () => _session.login(email: email, password: password),
                        email,
                      )) {
                        return;
                      }
                      TextInput.finishAutofillContext(shouldSave: true);
                      MbnSync.instance.configure(server: _session.server);
                      // The session is already issued: local account
                      // bookkeeping must never fail the login itself.
                      try {
                        if (_session.userId != null) {
                          await MbnSync.instance.bindAccount(_session.userId!);
                        }
                      } catch (_) {}
                      MbnSync.instance.beginSettingsChoice();
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
      listenable: Listenable.merge([
        AccessibilityService.instance,
        if (DevicePerformance.appleMobileWeb) BrowserFeatures.safeAreaChanges,
      ]),
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final access = AccessibilityService.instance;
          final uiScale = access.uiScale;
          final textScale = access.textScale;

          final inheritedMedia = MediaQuery.of(context);
          // Layout constraints describe this viewport, including keyboard,
          // fullscreen and desktop chrome changes. An inherited screen size may
          // still describe the previous viewport during a metrics update.
          var rawMedia = inheritedMedia.copyWith(
            size: Size(
              constraints.hasBoundedWidth
                  ? constraints.maxWidth
                  : inheritedMedia.size.width,
              constraints.hasBoundedHeight
                  ? constraints.maxHeight
                  : inheritedMedia.size.height,
            ),
          );
          if (DevicePerformance.appleMobileWeb) {
            // Custom web embedding keeps viewport-fit=cover. Flutter does not
            // supply iOS safe-area insets in that mode, so import Safari's real
            // CSS insets before UI scaling. SafeArea reserves this space inside
            // the viewport; neither the canvas nor pointer coordinates move.
            final area = BrowserFeatures.safeArea;
            final viewPadding = EdgeInsets.fromLTRB(
              math.max(rawMedia.viewPadding.left, area.left),
              math.max(rawMedia.viewPadding.top, area.top),
              math.max(rawMedia.viewPadding.right, area.right),
              math.max(rawMedia.viewPadding.bottom, area.bottom),
            );
            final insets = rawMedia.viewInsets;
            rawMedia = rawMedia.copyWith(
              viewPadding: viewPadding,
              padding: EdgeInsets.fromLTRB(
                math.max(0, viewPadding.left - insets.left),
                math.max(0, viewPadding.top - insets.top),
                math.max(0, viewPadding.right - insets.right),
                math.max(0, viewPadding.bottom - insets.bottom),
              ),
            );
          }
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

          // Use one top-left transform for paint and inverse hit testing. Keep
          // its logical child unconstrained so the scaled UI fills the viewport.
          return SizedBox(
            width: rawMedia.size.width,
            height: rawMedia.size.height,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: targetWidth,
              maxWidth: targetWidth,
              minHeight: targetHeight,
              maxHeight: targetHeight,
              child: Transform.scale(
                scale: uiScale,
                alignment: Alignment.topLeft,
                transformHitTests: true,
                child: SizedBox(
                  width: targetWidth,
                  height: targetHeight,
                  child: MediaQuery(data: scaledMedia, child: child),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
