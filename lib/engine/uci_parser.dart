/// Pure-Dart parsers for Stockfish UCI output.
///
/// Keeping these free of any engine/FFI dependency makes them trivially
/// testable and reusable from the analysis pipeline.
library;

/// A `score` reported by the engine, relative to the side to move.
class EngineScore {
  const EngineScore({this.cp, this.mate, this.lowerBound = false, this.upperBound = false})
      : assert(cp != null || mate != null, 'EngineScore needs cp or mate');

  /// Centipawns relative to the side to move (e.g. 34 = +0.34 pawns).
  final int? cp;

  /// Mate in N moves for the side to move (negative = being mated).
  final int? mate;

  final bool lowerBound;
  final bool upperBound;

  bool get isMate => mate != null;

  /// Score converted to the white player's point of view.
  ({int? cp, int? mate}) get whitePov {
    if (mate != null) {
      return (cp: null, mate: mate);
    }
    return (cp: cp, mate: null);
  }

  @override
  String toString() => mate != null ? 'M$mate' : 'cp ${cp ?? 0}';
}

/// One parsed `info ...` line.
class EngineInfoLine {
  const EngineInfoLine({
    required this.depth,
    this.seldepth,
    this.multipv,
    this.score,
    this.pv = const [],
    this.nodes,
    this.nps,
    required this.raw,
  });

  final int depth;
  final int? seldepth;
  final int? multipv;
  final EngineScore? score;

  /// Principal variation in UCI coordinate form (e.g. `e2e4 e7e5`).
  final List<String> pv;

  final int? nodes;
  final int? nps;
  final String raw;

  @override
  String toString() => 'EngineInfoLine(depth: $depth, score: $score, pv: $pv)';
}

/// Parses an `info ...` line. Returns null for lines that carry no
/// depth/score information (e.g. `info string ...` chatter).
EngineInfoLine? parseInfoLine(String line) {
  final tokens = line.trim().split(RegExp(r'\s+'));
  if (tokens.isEmpty || tokens.first != 'info') return null;

  int? depth;
  int? seldepth;
  int? multipv;
  int? nodes;
  int? nps;
  EngineScore? score;
  final pv = <String>[];

  for (var i = 1; i < tokens.length; i++) {
    final token = tokens[i];
    switch (token) {
      case 'depth':
        if (i + 1 < tokens.length) depth = int.tryParse(tokens[++i]);
      case 'seldepth':
        if (i + 1 < tokens.length) seldepth = int.tryParse(tokens[++i]);
      case 'multipv':
        if (i + 1 < tokens.length) multipv = int.tryParse(tokens[++i]);
      case 'nodes':
        if (i + 1 < tokens.length) nodes = int.tryParse(tokens[++i]);
      case 'nps':
        if (i + 1 < tokens.length) nps = int.tryParse(tokens[++i]);
      case 'score':
        score = _parseScore(tokens, i);
        // score cp 34 [lowerbound|upperbound] -> skip its arguments.
        if (score != null) i += score.isMate ? 2 : 2;
        if (i + 1 < tokens.length && (tokens[i + 1] == 'lowerbound' || tokens[i + 1] == 'upperbound')) {
          i++;
        }
      case 'pv':
        pv.addAll(tokens.sublist(i + 1));
        i = tokens.length;
      default:
        break;
    }
  }

  if (depth == null) return null;
  if (score == null && pv.isEmpty) return null;

  return EngineInfoLine(
    depth: depth,
    seldepth: seldepth,
    multipv: multipv,
    score: score,
    pv: pv,
    nodes: nodes,
    nps: nps,
    raw: line,
  );
}

EngineScore? _parseScore(List<String> tokens, int scoreIndex) {
  if (scoreIndex + 2 >= tokens.length) return null;
  final kind = tokens[scoreIndex + 1];
  final value = int.tryParse(tokens[scoreIndex + 2]);
  if (value == null) return null;
  final boundIndex = scoreIndex + 3;
  final lower = boundIndex < tokens.length && tokens[boundIndex] == 'lowerbound';
  final upper = boundIndex < tokens.length && tokens[boundIndex] == 'upperbound';
  switch (kind) {
    case 'cp':
      return EngineScore(cp: value, lowerBound: lower, upperBound: upper);
    case 'mate':
      return EngineScore(mate: value, lowerBound: lower, upperBound: upper);
    default:
      return null;
  }
}

/// Returns the best move from a `bestmove <uci> [ponder <uci>]` line, or null
/// if [line] is not a bestmove line. The engine answers `(none)` when it has
/// no legal move; that is surfaced as null too.
String? parseBestMove(String line) {
  final tokens = line.trim().split(RegExp(r'\s+'));
  if (tokens.length < 2 || tokens.first != 'bestmove') return null;
  final move = tokens[1];
  if (move == '(none)') return null;
  return move;
}

/// Returns the ponder move from a `bestmove ... ponder <uci>` line, if any.
String? parsePonderMove(String line) {
  final tokens = line.trim().split(RegExp(r'\s+'));
  final ponderIndex = tokens.indexOf('ponder');
  if (ponderIndex < 0 || ponderIndex + 1 >= tokens.length) return null;
  return tokens[ponderIndex + 1];
}

/// True when the line is one of the UCI synchronization tokens.
bool isReadyToken(String line, String token) => line.trim() == token;
