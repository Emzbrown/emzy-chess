import 'dart:async';

import 'engine_isolate.dart';
import 'uci_parser.dart';

/// A single search target, as handed to [EngineSearcher.analyze].
///
/// Kept as a tiny interface so the analysis pipeline can be tested with a
/// fake engine instead of the real FFI-backed one.
abstract class EngineSearcher {
  /// Runs a bounded analysis of [fen] and emits every scored `info` line,
  /// completing when the engine answers with `bestmove`.
  Stream<EngineInfoLine> analyze({required String fen, required int depth});

  /// Asks a running search to finish and yield its `bestmove` early.
  Future<void> requestStop();
}

/// Exception thrown when the engine dies or misbehaves.
class EngineException implements Exception {
  EngineException(this.message);

  final String message;

  @override
  String toString() => 'EngineException: $message';
}

/// High-level UCI driver on top of [EngineIsolate].
///
/// Owns the request/response bookkeeping (`uci`/`isready` handshakes,
/// `bestmove` futures, analysis streams) so screens can simply ask for a
/// best move or an evaluation stream.
class UciEngine implements EngineSearcher {
  UciEngine._(this._isolate) {
    _subscription = _isolate.lines.listen(_handleLine);
  }

  final EngineIsolate _isolate;
  late final StreamSubscription<String> _subscription;

  final Completer<void> _booted = Completer<void>();
  final List<Completer<void>> _readyWaiters = [];

  Completer<String>? _bestMoveWaiter;
  Completer<void>? _analysisDone;
  StreamController<EngineInfoLine>? _analysisStream;

  /// Parsed `info` lines from any search, for live display.
  final StreamController<EngineInfoLine> info =
      StreamController<EngineInfoLine>.broadcast();

  /// Lifecycle of the raw engine process.
  Stream<EnginePhase> get phases => _isolate.phases;

  /// True once the UCI handshake (`uci`/`uciok`, `isready`/`readyok`) passed.
  bool get isReady => _booted.isCompleted;

  /// Starts the engine isolate and completes the UCI handshake.
  static Future<UciEngine> start() async {
    final isolate = await EngineIsolate.spawn();
    final engine = UciEngine._(isolate);
    await engine._handshake();
    return engine;
  }

  Future<void> _handshake() async {
    _isolate.send('uci');
    await _waitToken('uciok', timeout: const Duration(seconds: 20));
    _isolate.send('setoption name Hash value 64');
    _isolate.send('setoption name Clear Hash');
    await ready();
    if (!_booted.isCompleted) _booted.complete();
  }

  /// Sends `isready` and resolves on `readyok`. Also used as a barrier to make
  /// sure buffered options are applied before searching.
  Future<void> ready() async {
    _isolate.send('isready');
    await _waitToken('readyok', timeout: const Duration(seconds: 20));
  }

  Future<void> _waitToken(String token, {required Duration timeout}) {
    final completer = Completer<void>();
    _readyWaiters.add(completer);
    // The waiting is driven by _handleLine; enforce the timeout here.
    completer.future.timeout(timeout, onTimeout: () {
      _readyWaiters.remove(completer);
      completer.completeError(EngineException('Timed out waiting for $token'));
    });
    return completer.future;
  }

  void _handleLine(String line) {
    final trimmed = line.trim();

    if (trimmed == 'readyok') {
      if (_readyWaiters.isNotEmpty) _readyWaiters.removeAt(0).complete();
      return;
    }

    final bestMove = parseBestMove(trimmed);
    if (bestMove != null || trimmed.startsWith('bestmove')) {
      final done = _analysisDone;
      _analysisDone = null;
      final stream = _analysisStream;
      _analysisStream = null;
      // `bestmove` terminates an analysis search; the stream carries only
      // scored `info` lines, so just close it here.
      unawaited(stream?.close());

      final waiter = _bestMoveWaiter;
      _bestMoveWaiter = null;
      if (waiter != null && !waiter.isCompleted) {
        if (bestMove == null) {
          waiter.completeError(EngineException('Engine has no legal move'));
        } else {
          waiter.complete(bestMove);
        }
      }
      done?.complete();
      return;
    }

    final parsed = parseInfoLine(trimmed);
    if (parsed != null) {
      if (!info.isClosed) info.add(parsed);
      final stream = _analysisStream;
      if (stream != null && !stream.isClosed) stream.add(parsed);
    }
  }

  /// Searches [fen] for [movetimeMs] and returns the engine's best move in UCI
  /// form (e.g. `e2e4`). Only one search may run at a time.
  Future<String> bestMove({required String fen, int movetimeMs = 1000}) async {
    _ensureIdle();
    final completer = Completer<String>();
    _bestMoveWaiter = completer;
    _isolate.send('position fen $fen');
    _isolate.send('go movetime $movetimeMs');
    return completer.future.timeout(
      Duration(milliseconds: movetimeMs + 5000),
      onTimeout: () {
        if (_bestMoveWaiter == completer) _bestMoveWaiter = null;
        throw EngineException('Engine did not answer within the search budget');
      },
    );
  }

  /// Analyses [fen] to a fixed [depth], emitting every scored `info` line and
  /// completing on the final `bestmove`.
  @override
  Stream<EngineInfoLine> analyze({required String fen, required int depth}) {
    _ensureIdle();
    final controller = StreamController<EngineInfoLine>();
    _analysisStream = controller;
    _analysisDone = Completer<void>();

    controller.onListen = () {
      _isolate.send('position fen $fen');
      _isolate.send('go depth $depth');
    };
    controller.onCancel = () async {
      // If the consumer stops early (e.g. the user left the screen) ask the
      // engine to stop so the next search is not blocked.
      if (_analysisStream == controller) {
        _analysisStream = null;
        _analysisDone = null;
        _isolate.send('stop');
      }
    };

    return controller.stream;
  }

  /// Stops a running search; a pending `bestmove`/`bestmove` stream completes
  /// with whatever the engine has.
  @override
  Future<void> requestStop() async {
    if (_bestMoveWaiter == null && _analysisStream == null) return;
    _isolate.send('stop');
    await _analysisDone?.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {},
    );
  }

  /// Clears the engine's search history (call at the start of a new game).
  Future<void> newGame() async {
    _isolate.send('ucinewgame');
    await ready();
  }

  void _ensureIdle() {
    if (_bestMoveWaiter != null || _analysisStream != null) {
      throw StateError('An engine search is already running');
    }
    if (_booted.isCompleted && _isolate.phase == EnginePhase.error) {
      throw EngineException('Engine is not running');
    }
  }

  Future<void> dispose() async {
    try {
      _isolate.send('quit');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    } catch (_) {
      // Engine may already be gone; disposal below is still safe.
    }
    await _subscription.cancel();
    await info.close();
    await _isolate.dispose();
  }
}
