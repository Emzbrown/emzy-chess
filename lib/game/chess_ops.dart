import 'package:chess/chess.dart';

/// Helpers built on top of the `chess` package that keep SAN/UCI/coordinate
/// conversions in one tested place.

/// A legal move candidate expressed in algebraic form.
class MoveEntry {
  const MoveEntry({
    required this.from,
    required this.to,
    required this.san,
    this.promotion,
  });

  final String from;
  final String to;
  final String san;

  /// Promotion piece letter (`q`, `r`, `b`, `n`), if this is a promotion.
  final String? promotion;

  bool get isCapture => san.contains('x');
  bool get isCastle => san == 'O-O' || san == 'O-O-O';

  @override
  String toString() => san;
}

final Map<String, PieceType> _pieceTypesByKey = Map.unmodifiable(Chess.PIECE_TYPES);

String? _pieceLetter(PieceType? type) {
  if (type == null) return null;
  for (final entry in _pieceTypesByKey.entries) {
    if (entry.value == type) return entry.key;
  }
  return null;
}

/// All legal moves for the piece on [square], or an empty list when the square
/// is empty or the move would be illegal.
List<MoveEntry> legalMovesFrom(Chess game, String square) {
  final turn = game.turn;
  final result = <MoveEntry>[];
  for (final move in game.generate_moves({'square': square})) {
    if (move.color != turn) continue;
    final probe = game.copy();
    final applied = probe.move(<String, dynamic>{
      'from': move.fromAlgebraic,
      'to': move.toAlgebraic,
      if (move.promotion != null) 'promotion': _pieceLetter(move.promotion),
    });
    if (applied != true) continue;
    result.add(MoveEntry(
      from: move.fromAlgebraic,
      to: move.toAlgebraic,
      san: game.move_to_san(move),
      promotion: _pieceLetter(move.promotion),
    ));
  }
  return result;
}

/// Legal moves for every square, flattened. Used for SAN lookups.
List<MoveEntry> allLegalMoves(Chess game) {
  final result = <MoveEntry>[];
  for (final square in _allSquares) {
    result.addAll(legalMovesFrom(game, square));
  }
  return result;
}

final List<String> _allSquares = [
  for (var rank = 0; rank < 8; rank++)
    for (var file = 0; file < 8; file++)
      '${'abcdefgh'[file]}${rank + 1}',
];

/// Finds the legal move entry matching [from]/[to] (and promotion, when the
/// engine asks for one), or null when no such legal move exists.
MoveEntry? findMove(Chess game, String from, String to, {String? promotion}) {
  for (final entry in legalMovesFrom(game, from)) {
    if (entry.to != to) continue;
    // Engine moves specify the promotion piece; human touches default to it.
    if (promotion != null && entry.promotion != promotion) continue;
    if (promotion == null && entry.promotion != null) continue;
    return entry;
  }
  return null;
}

/// Finds the legal move whose SAN equals [san], or null.
MoveEntry? findMoveBySan(Chess game, String san) {
  for (final entry in allLegalMoves(game)) {
    if (entry.san == san) return entry;
  }
  return null;
}

/// Converts a UCI coordinate move (`e2e4`, `e7e8q`) into a [MoveEntry] for the
/// current position, or null when it is not legal here.
MoveEntry? moveEntryFromUci(Chess game, String uci) {
  if (uci.length < 4) return null;
  final from = uci.substring(0, 2);
  final to = uci.substring(2, 4);
  final promotion = uci.length > 4 ? uci.substring(4, 5) : null;
  return findMove(game, from, to, promotion: promotion);
}

/// Converts a UCI principal variation into SAN, stopping at the first move
/// that is not legal in the current position.
List<String> pvToSan(Chess game, List<String> uciPv) {
  final sans = <String>[];
  final board = game.copy();
  for (final uci in uciPv) {
    final entry = moveEntryFromUci(board, uci);
    if (entry == null) break;
    board.move(<String, dynamic>{
      'from': entry.from,
      'to': entry.to,
      if (entry.promotion != null) 'promotion': entry.promotion,
    });
    sans.add(entry.san);
  }
  return sans;
}

/// Loads a FEN into a fresh [Chess], falling back to the standard start
/// position when the FEN is malformed. (The `chess` package happily accepts
/// some garbage without throwing, so the shape is checked first.)
Chess boardFromFen(String? fen) {
  if (fen == null || !_looksLikeFen(fen)) return Chess();
  try {
    return Chess.fromFEN(fen);
  } catch (_) {
    return Chess();
  }
}

bool _looksLikeFen(String fen) {
  final parts = fen.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return false;
  if (parts[1] != 'w' && parts[1] != 'b') return false;
  final ranks = parts[0].split('/');
  if (ranks.length != 8) return false;
  for (final rank in ranks) {
    if (rank.isEmpty || !RegExp(r'^[prnbqkPRNBQK1-8]+$').hasMatch(rank)) {
      return false;
    }
  }
  return true;
}

/// Side-to-move character (`w`/`b`) for a FEN.
String turnOfFen(String fen) {
  final parts = fen.trim().split(RegExp(r'\s+'));
  return parts.length > 1 ? parts[1] : 'w';
}

/// Converts the `chess` package color to the `w`/`b` wire representation.
String colorToWire(Color color) => color == Chess.WHITE ? 'w' : 'b';
