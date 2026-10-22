import 'dart:async';

import 'uci_engine.dart';

/// Process-wide owner of the single Stockfish instance.
///
/// The FFI wrapper only supports one live engine, so the engine-game screen
/// and the analysis screen share this manager.
class EngineManager {
  EngineManager._();

  static final EngineManager instance = EngineManager._();

  UciEngine? _engine;
  Future<UciEngine>? _starting;
  bool _disposed = false;

  /// The shared engine, started on first use.
  Future<UciEngine> ensureStarted() {
    if (_disposed) {
      throw StateError('EngineManager was disposed');
    }
    final existing = _engine;
    if (existing != null) return Future.value(existing);
    return _starting ??= _startFresh();
  }

  Future<UciEngine> _startFresh() async {
    try {
      final engine = await UciEngine.start();
      _engine = engine;
      _starting = null;
      return engine;
    } catch (error) {
      // Allow a retry on the next call.
      _starting = null;
      rethrow;
    }
  }

  bool get isRunning => _engine != null;

  /// Tears the engine down (e.g. when the host app is closing).
  Future<void> shutdown() async {
    _disposed = true;
    final engine = _engine;
    _engine = null;
    _starting = null;
    if (engine != null) {
      await engine.dispose();
    }
  }
}
