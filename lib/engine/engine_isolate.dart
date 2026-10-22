import 'dart:async';
import 'dart:isolate';

import 'package:stockfish/stockfish.dart';

/// Lifecycle phase of the underlying engine, mirrored from the isolate.
enum EnginePhase { starting, ready, error, disposed }

/// Owns the `stockfish` FFI instance inside a background [Isolate] so the UI
/// thread never pays for engine startup, UCI parsing, or output streaming.
///
/// Protocol with the isolate:
///   main -> isolate : UCI command [String], or [EngineIsolate.disposeCommand]
///   isolate -> main : {'kind': 'hello'|'line'|'state'|'error', ...}
class EngineIsolate {
  EngineIsolate._(this._isolate, this._inboxSendPort, this._eventPort);

  final Isolate _isolate;

  /// Command channel into the isolate.
  final SendPort _inboxSendPort;

  /// Event channel out of the isolate.
  final ReceivePort _eventPort;

  final StreamController<String> _lines = StreamController<String>.broadcast();
  final StreamController<EnginePhase> _phases =
      StreamController<EnginePhase>.broadcast();

  EnginePhase _phase = EnginePhase.starting;
  bool _disposed = false;

  static const disposeCommand = '__engine_dispose__';

  /// Engine output, one UCI line per event.
  Stream<String> get lines => _lines.stream;

  /// Engine lifecycle changes.
  Stream<EnginePhase> get phases => _phases.stream;

  EnginePhase get phase => _phase;

  /// Spawns the engine isolate and waits for the handshake.
  static Future<EngineIsolate> spawn() async {
    final eventPort = ReceivePort();
    final isolate = await Isolate.spawn<_EngineBoot>(
      _engineEntryPoint,
      _EngineBoot(eventPort.sendPort),
      debugName: 'stockfish-uci',
      errorsAreFatal: false,
    );

    SendPort? inboxPort;
    final completer = Completer<SendPort>();
    final sub = eventPort.listen((dynamic message) {
      if (message is Map && message['kind'] == 'hello' && !completer.isCompleted) {
        completer.complete(message['port'] as SendPort);
      }
    });
    inboxPort = await completer.future.timeout(const Duration(seconds: 20));
    await sub.cancel();

    final engine = EngineIsolate._(isolate, inboxPort, eventPort);
    engine._pumpEvents();
    return engine;
  }

  void _pumpEvents() {
    _eventPort.listen((dynamic message) {
      if (message is! Map) return;
      switch (message['kind']) {
        case 'line':
          _lines.add(message['text'] as String);
        case 'state':
          final phase = _phaseFrom(message['state'] as String? ?? '');
          _phase = phase;
          _phases.add(phase);
        case 'error':
          _phase = EnginePhase.error;
          _phases.add(EnginePhase.error);
          _lines.add('info string engine error: ${message['message']}');
      }
    });
  }

  static EnginePhase _phaseFrom(String name) {
    switch (name) {
      case 'ready':
        return EnginePhase.ready;
      case 'error':
        return EnginePhase.error;
      case 'disposed':
        return EnginePhase.disposed;
      default:
        return EnginePhase.starting;
    }
  }

  /// Sends one UCI command (e.g. `go depth 12`) to the engine.
  void send(String command) {
    if (_disposed) return;
    _inboxSendPort.send(command);
  }

  /// Shuts the engine down. Safe to call more than once.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      _inboxSendPort.send(disposeCommand);
      // Give the isolate a moment to run engine.quit before killing it.
      await Future<void>.delayed(const Duration(milliseconds: 150));
    } finally {
      _isolate.kill(priority: Isolate.immediate);
      _eventPort.close();
      await _lines.close();
      await _phases.close();
      _phase = EnginePhase.disposed;
    }
  }
}

/// Spawn message handed to the engine isolate.
class _EngineBoot {
  const _EngineBoot(this.events);

  final SendPort events;
}

/// Isolate entry point: creates the FFI engine and relays stdin/stdout.
void _engineEntryPoint(_EngineBoot boot) {
  final inbox = ReceivePort();
  final events = boot.events;

  Stockfish? engine;
  StreamSubscription<String>? stdoutSub;
  void sendError(Object error) {
    events.send({'kind': 'error', 'message': '$error'});
  }

  try {
    engine = Stockfish();
  } catch (error) {
    sendError('Failed to start Stockfish: $error');
  }

  if (engine != null) {
    final alive = engine;
    stdoutSub = alive.stdout.listen(
      (line) => events.send({'kind': 'line', 'text': line}),
      onError: (Object e) => sendError(e),
    );
    alive.state.addListener(() {
      events.send({'kind': 'state', 'state': alive.state.value.name});
    });
    // Forward the current state in case it changed before the listener ran.
    events.send({'kind': 'state', 'state': alive.state.value.name});
  }

  inbox.listen((dynamic message) {
    if (message is! String) return;
    if (message == EngineIsolate.disposeCommand) {
      stdoutSub?.cancel();
      engine?.dispose();
      inbox.close();
      return;
    }
    try {
      engine?.stdin = message;
    } catch (error) {
      sendError(error);
    }
  });

  events.send({'kind': 'hello', 'port': inbox.sendPort});
}
