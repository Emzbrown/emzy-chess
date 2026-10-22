import 'dart:async';

import 'package:chess/chess.dart';
import 'package:flutter/foundation.dart';

import '../engine/uci_engine.dart';
import '../engine/uci_parser.dart';
import 'chess_ops.dart';
import 'models.dart';

/// Drives Stockfish over a whole game (or a single position) and records one
/// [PlyEvaluation] per position for the eval bar and the fl_chart graph.
class AnalysisController extends ChangeNotifier {
  AnalysisController({required this.engine});

  final EngineSearcher engine;

  String startFen = Chess.DEFAULT_POSITION;
  List<String> sans = [];

  /// fens[i] is the position after i half-moves; fens[0] is [startFen].
  List<String> fens = [Chess.DEFAULT_POSITION];

  final List<PlyEvaluation?> evals = [];

  int focusPly = 0;
  bool analyzing = false;
  bool _cancelled = false;
  String? error;

  /// Load a game to analyse from scratch.
  void load({required String startFen, required List<String> sans}) {
    this.startFen = startFen;
    this.sans = List.of(sans);
    fens = [startFen];
    final board = boardFromFen(startFen);
    for (final san in sans) {
      if (board.move(san) == true) {
        fens.add(board.fen);
      } else {
        break;
      }
    }
    evals
      ..clear()
      ..addAll(List<PlyEvaluation?>.filled(fens.length, null));
    focusPly = 0;
    notifyListeners();
  }

  String get focusFen => fens[focusPly.clamp(0, fens.length - 1)];
  PlyEvaluation? get focusEval => evals[focusPly.clamp(0, evals.length - 1)];
  double get progress => fens.isEmpty ? 0 : evals.where((e) => e != null).length / fens.length;

  void focus(int ply) {
    final clamped = ply.clamp(0, fens.length - 1);
    if (clamped == focusPly) return;
    focusPly = clamped;
    notifyListeners();
  }

  /// Analyses every position in order. Cancels any run already in flight.
  Future<void> analyzeAll({int depth = 12}) async {
    if (analyzing) await cancel();
    _cancelled = false;
    analyzing = true;
    error = null;
    notifyListeners();

    try {
      for (var i = 0; i < fens.length; i++) {
        if (_cancelled) break;
        final evaluation = await _analyzePosition(i, depth);
        if (_cancelled) break;
        if (evaluation != null) {
          evals[i] = evaluation;
          // Keep the graph and bar live while the run progresses.
          focusPly = i;
          notifyListeners();
        }
      }
    } catch (e) {
      error = 'Analysis failed: $e';
    } finally {
      analyzing = false;
      _cancelled = false;
      notifyListeners();
    }
  }

  /// Analyses only the focused position (refresh button).
  Future<void> analyzeFocus({int depth = 14}) async {
    if (analyzing) return;
    _cancelled = false;
    analyzing = true;
    error = null;
    notifyListeners();
    try {
      final evaluation = await _analyzePosition(focusPly, depth);
      if (evaluation != null) {
        evals[focusPly] = evaluation;
      }
    } catch (e) {
      error = 'Analysis failed: $e';
    } finally {
      analyzing = false;
      notifyListeners();
    }
  }

  Future<PlyEvaluation?> _analyzePosition(int index, int depth) async {
    final fen = fens[index];
    final whiteToMove = turnOfFen(fen) == 'w';

    EngineInfoLine? best;
    await for (final info in engine.analyze(fen: fen, depth: depth)) {
      final score = info.score;
      if (score == null) continue;
      final deeper = best == null || info.depth >= best.depth;
      if (deeper) best = info;
    }
    if (best?.score == null) return null;
    final score = best!.score!;

    final pov = scoreToWhitePov(
      cp: score.cp,
      mate: score.mate,
      whiteToMove: whiteToMove,
    );
    return PlyEvaluation(
      positionIndex: index,
      cpWhite: pov.cp ?? 0,
      mateWhite: pov.mate,
      pvUci: best.pv,
      pvSan: pvToSan(boardFromFen(fen), best.pv),
      depth: best.depth,
    );
  }

  /// Stops the run in progress.
  Future<void> cancel() async {
    _cancelled = true;
    await engine.requestStop();
  }
}
