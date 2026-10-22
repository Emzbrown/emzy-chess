/// Shared game/analysis data models.
library;

import 'dart:math' as math;

/// Where a move came from — the unified board accepts all three.
enum MoveSource { human, engine, network }

/// What kind of game is running.
enum GameMode { practice, engine, network }

/// Outcome of the game.
enum GameStatus { playing, checkmate, stalemate, draw, resigned, disconnected }

/// One committed half-move with everything the UI needs to replay it.
class MoveRecord {
  const MoveRecord({
    required this.san,
    required this.from,
    required this.to,
    required this.fenBefore,
    required this.fenAfter,
    required this.source,
    this.promotion,
  });

  final String san;
  final String from;
  final String to;
  final String? promotion;
  final String fenBefore;
  final String fenAfter;
  final MoveSource source;

  /// UCI coordinate form, e.g. `e2e4` / `e7e8q`.
  String get uci => '$from$to${promotion ?? ''}';

  @override
  String toString() => san;
}

/// Engine evaluation of one position, normalized to White's point of view so
/// the eval bar and the graph always read bottom-up from White's side.
class PlyEvaluation {
  const PlyEvaluation({
    required this.positionIndex,
    required this.cpWhite,
    required this.mateWhite,
    required this.pvUci,
    required this.pvSan,
    required this.depth,
  });

  /// 0 = start position; i = the position after the i-th half-move.
  final int positionIndex;

  /// Centipawns from White's POV (positive favors White).
  final int cpWhite;

  /// Mate in N for White (positive: White mates; negative: Black mates).
  final int? mateWhite;

  final List<String> pvUci;
  final List<String> pvSan;
  final int depth;

  bool get isMate => mateWhite != null;

  /// Centipawns mapped onto a stable ±1000 display scale, with mate scores
  /// parked just inside the limits (so the graph axis never explodes).
  double get displayValue {
    final mate = mateWhite;
    if (mate != null) {
      final distance = math.min(mate.abs(), 9) * 10.0;
      return mate > 0 ? 1000 - distance : -1000 + distance;
    }
    return cpWhite.clamp(-1000, 1000).toDouble();
  }

  /// Bar fraction in [-1, 1]: 1 = White winning completely.
  double get barFraction {
    final mate = mateWhite;
    if (mate != null) return mate > 0 ? 1 : -1;
    return 2 / (1 + math.exp(-cpWhite / 350)) - 1;
  }

  /// Short human label, e.g. `+0.34`, `M3`, `-M2`.
  String get label {
    final mate = mateWhite;
    if (mate != null) {
      return mate > 0 ? 'M$mate' : '-M${mate.abs()}';
    }
    final pawns = cpWhite / 100;
    return pawns >= 0 ? '+${pawns.toStringAsFixed(2)}' : pawns.toStringAsFixed(2);
  }
}

/// Converts a UCI `score cp`/`score mate` (side-to-move POV) to White's POV.
({int? cp, int? mate}) scoreToWhitePov({int? cp, int? mate, required bool whiteToMove}) {
  if (mate != null) {
    return (cp: null, mate: whiteToMove ? mate : -mate);
  }
  if (cp != null) {
    return (cp: whiteToMove ? cp : -cp, mate: null);
  }
  return (cp: null, mate: null);
}
