import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'network_gate.dart';

/// A short, memory-only permission. Local preferences and sync never grant it.
class AdultAccess {
  AdultAccess({
    http.Client? client,
    this.interval = const Duration(seconds: 10),
    this.lease = const Duration(seconds: 20),
  }) : _client = client ?? http.Client() {
    OfflineMode.changes.addListener(_offlineChanged);
  }

  static final instance = AdultAccess();
  final http.Client _client;
  final Duration interval;
  final Duration lease;
  final changes = ValueNotifier<bool>(false);
  String? _token;
  String _base = '';
  int _generation = 0;
  int _decision = 0;
  int? _refreshing;
  Timer? _timer;
  Timer? _expiry;
  DateTime? _validUntil;

  bool get allowed =>
      changes.value &&
      !OfflineMode.active &&
      _token != null &&
      _validUntil?.isAfter(DateTime.now()) == true;
  String? get credential => allowed ? _token : null;

  void bind(String? token, String base) {
    if (_token == token && _base == base) return;
    _generation++;
    _token = token;
    _base = base;
    deny();
    _timer?.cancel();
    if (token == null || token.isEmpty) return;
    _timer = Timer.periodic(interval, (_) => unawaited(refresh()));
    unawaited(refresh());
  }

  void deny() {
    _decision++;
    _expiry?.cancel();
    _validUntil = null;
    changes.value = false;
  }

  void _offlineChanged() {
    deny();
    if (!OfflineMode.active) unawaited(refresh());
  }

  /// Called only for the current authenticated SSE connection.
  void observe(String token, Object? value) {
    if (token != _token) return;
    _decision++;
    _set(value == true);
  }

  void _set(bool value) {
    _expiry?.cancel();
    if (!value || OfflineMode.active || _token == null) {
      _validUntil = null;
      changes.value = false;
      return;
    }
    _validUntil = DateTime.now().add(lease);
    changes.value = true;
    _expiry = Timer(lease, deny);
  }

  Future<void> refresh() async {
    if (_token == null || OfflineMode.active || _refreshing == _generation) {
      return;
    }
    final generation = _generation, decision = _decision;
    _refreshing = generation;
    try {
      final response = await _client
          .get(
            Uri.parse('$_base/api/anime/adult-access'),
            headers: {
              'Authorization': 'Bearer $_token',
              'Cache-Control': 'no-store',
            },
          )
          .timeout(const Duration(seconds: 5));
      if (generation != _generation || decision != _decision) return;
      final body = response.statusCode == 200
          ? jsonDecode(response.body)
          : null;
      _set(body is Map && body['allowed'] == true);
    } catch (_) {
      if (generation == _generation && decision == _decision) _set(false);
    } finally {
      if (_refreshing == generation) _refreshing = null;
    }
  }

  void requireAllowed() {
    if (!allowed) throw StateError('دسترسی این بخش باید توسط مدیریت فعال شود.');
  }

  void dispose() {
    _generation++;
    _timer?.cancel();
    _expiry?.cancel();
    OfflineMode.changes.removeListener(_offlineChanged);
    _client.close();
    changes.dispose();
  }
}
