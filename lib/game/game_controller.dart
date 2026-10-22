import 'package:chess/chess.dart';
import 'package:flutter/foundation.dart';

import '../network/protocol.dart';
import 'chess_ops.dart';
import 'models.dart';

/// Unified move-input surface accepted by the [ChessBoard] widget.
///
/// Every move — however it arrives — funnels through this interface:
///  * human touches        -> [applyTouch]
///  * Stockfish best moves -> [applyEngineMove]
///  * TCP network payloads -> [applyNetworkMove]
abstract class BoardInput {
  bool applyTouch(String square);
  bool applyEngineMove(String uciMove, {String? expectedFen});
  bool applyNetworkMove(NetworkMessage message);
}

/// Owns the authoritative board position and the move history for one game.
///
/// Screens feed moves in through the [BoardInput] methods; the [ChessBoard]
/// widget only reads state (`fen`, `targets`, `lastMove`, ...) off this
/// controller and reports touches back through [applyTouch].
class GameController extends ChangeNotifier implements BoardInput {
  GameController({
    String? fen,
    this.playerColor = 'w',
    this.mode = GameMode.practice,
    this.interactive = true,
  }) : _game = boardFromFen(fen);

  Chess _game;

  /// Color the local human plays (`w`/`b`). In practice mode this is White.
  final String playerColor;

  final GameMode mode;

  /// Whether the board forwards touches at all (false on analysis boards).
  final bool interactive;

  final List<MoveRecord> history = [];

  String? selectedSquare;
  Map<String, MoveEntry> targets = {};
  MoveRecord? lastMove;
  GameStatus status = GameStatus.playing;

  /// Color that won, if the game ended (`w`/`b`), or null for a draw.
  String? winner;
  String? endReason;

  // ------------------------------------------------------------------ state

  String get fen => _game.fen;
  Chess get game => _game;
  bool get whiteToMove => _game.turn == Chess.WHITE;
  String get turn => colorToWire(_game.turn);
  bool get gameOver => status != GameStatus.playing;
  int get ply => history.length;

  /// Whether the local human is allowed to move right now.
  bool get canHumanMove =>
      interactive && !gameOver && (mode == GameMode.practice || turn == playerColor);

  /// True when the local side is in check (drives the red king highlight).
  bool get inCheck => _game.in_check;

  /// King square of the side to move, when in check.
  String? get checkedKingSquare {
    if (!_game.in_check) return null;
    for (final square in _allSquares) {
      final piece = _game.get(square);
      if (piece != null && piece.type == Chess.KING && piece.color == _game.turn) {
        return square;
      }
    }
    return null;
  }

  static final List<String> _allSquares = [
    for (var rank = 0; rank < 8; rank++)
      for (var file = 0; file < 8; file++) '${'abcdefgh'[file]}${rank + 1}',
  ];

  String get statusText {
    switch (status) {
      case GameStatus.checkmate:
        final name = winner == 'w' ? 'White' : 'Black';
        return 'Checkmate — $name wins';
      case GameStatus.stalemate:
        return 'Stalemate — draw';
      case GameStatus.draw:
        return endReason ?? 'Draw';
      case GameStatus.resigned:
        final name = winner == 'w' ? 'White' : 'Black';
        return '$name wins by resignation';
      case GameStatus.disconnected:
        return endReason ?? 'Opponent disconnected';
      case GameStatus.playing:
        final who = mode == GameMode.practice
            ? (whiteToMove ? 'White' : 'Black')
            : (turn == playerColor ? 'Your' : (whiteToMove ? "White's" : "Black's"));
        final suffix = _game.in_check ? ' — check!' : ' to move';
        return '$who turn$suffix';
    }
  }

  /// Result token in PGN form (`1-0`, `0-1`, `1/2-1/2`, `*`).
  String get result {
    switch (status) {
      case GameStatus.checkmate:
      case GameStatus.resigned:
        return winner == 'w' ? '1-0' : '0-1';
      case GameStatus.stalemate:
      case GameStatus.draw:
        return '1/2-1/2';
      case GameStatus.disconnected:
        return '*';
      case GameStatus.playing:
        return '*';
    }
  }

  /// SAN moves played so far.
  List<String> get sans => [for (final record in history) record.san];

  // ----------------------------------------------------------- BoardInput

  /// Human touch on [square]: select a piece, then tap a highlighted target.
  @override
  bool applyTouch(String square) {
    if (!canHumanMove) return false;

    final pending = targets[square];
    if (selectedSquare != null && pending != null) {
      return _commit(pending, MoveSource.human);
    }

    final piece = _game.get(square);
    if (piece != null && piece.color == _game.turn) {
      selectedSquare = square;
      targets = {};
      for (final entry in legalMovesFrom(_game, square)) {
        // A tap cannot pick a promotion piece; default to queen (the
        // common case) rather than whatever the generator emitted last.
        final existing = targets[entry.to];
        if (existing == null || entry.promotion == 'q') {
          targets[entry.to] = entry;
        }
      }
    } else {
      selectedSquare = null;
      targets = const {};
    }
    notifyListeners();
    return false;
  }

  /// A Stockfish `bestmove` in UCI form (e.g. `e2e4`, `e7e8q`).
  @override
  bool applyEngineMove(String uciMove, {String? expectedFen}) {
    if (gameOver) return false;
    final entry = moveEntryFromUci(_game, uciMove);
    if (entry == null) return false;
    return _commit(entry, MoveSource.engine);
  }

  /// A decoded `{"type": "MOVE", "san": ..., "fen": ...}` payload. Validates
  /// the SAN against the local position and falls back to a FEN resync when
  /// the two sides have drifted apart.
  @override
  bool applyNetworkMove(NetworkMessage message) {
    switch (message.type) {
      case NetworkMessageType.move:
        return _applyNetworkMove(message.san, message.fen);
      case NetworkMessageType.newGame:
        reset();
        return true;
      case NetworkMessageType.resign:
        _endGame(
          status: GameStatus.resigned,
          // The opponent resigned; the local player (playerColor) wins.
          winner: playerColor,
          reason: 'Opponent resigned',
        );
        return true;
      case NetworkMessageType.sync:
        final fen = message.fen;
        if (fen != null) {
          _resync(fen);
          return true;
        }
        return false;
      default:
        return false;
    }
  }

  bool _applyNetworkMove(String? san, String? reportedFen) {
    if (gameOver) return false;
    if (san != null) {
      final entry = findMoveBySan(_game, san);
      if (entry != null) {
        final made = _commit(entry, MoveSource.network);
        // Trust the sender's FEN only to detect drift; local rules rule.
        if (made && reportedFen != null && reportedFen != _game.fen) {
          _resync(reportedFen);
        }
        return made;
      }
    }
    // SAN did not fit the local position: resync rather than desync forever.
    if (reportedFen != null) {
      _resync(reportedFen);
      return true;
    }
    return false;
  }

  // ------------------------------------------------------------- commits

  bool _commit(MoveEntry entry, MoveSource source) {
    final fenBefore = _game.fen;
    final applied = _game.move(<String, dynamic>{
      'from': entry.from,
      'to': entry.to,
      if (entry.promotion != null) 'promotion': entry.promotion,
    });
    if (applied != true) return false;

    final record = MoveRecord(
      san: entry.san,
      from: entry.from,
      to: entry.to,
      promotion: entry.promotion,
      fenBefore: fenBefore,
      fenAfter: _game.fen,
      source: source,
    );
    history.add(record);
    lastMove = record;
    selectedSquare = null;
    targets = const {};
    _refreshGameEnd();
    notifyListeners();
    return true;
  }

  /// Plays [san] directly (used by replay/analysis and by tests).
  bool playSan(String san, {MoveSource source = MoveSource.human}) {
    final entry = findMoveBySan(_game, san);
    if (entry == null) return false;
    return _commit(entry, source);
  }

  void _refreshGameEnd() {
    if (_game.in_checkmate) {
      _endGame(
        status: GameStatus.checkmate,
        winner: whiteToMove ? 'b' : 'w',
        reason: 'Checkmate',
      );
    } else if (_game.in_stalemate) {
      _endGame(status: GameStatus.stalemate, reason: 'Stalemate');
    } else if (_game.in_threefold_repetition) {
      _endGame(status: GameStatus.draw, reason: 'Threefold repetition');
    } else if (_game.insufficient_material) {
      _endGame(status: GameStatus.draw, reason: 'Insufficient material');
    } else if (_game.in_draw) {
      _endGame(status: GameStatus.draw, reason: 'Fifty-move rule');
    }
  }

  void _endGame({required GameStatus status, String? winner, String? reason}) {
    this.status = status;
    this.winner = winner;
    endReason = reason;
    selectedSquare = null;
    targets = const {};
  }

  /// Forces the board to a known FEN (protocol resync / host authority).
  void _resync(String fen) {
    final board = boardFromFen(fen);
    _game = board;
    selectedSquare = null;
    targets = const {};
    status = GameStatus.playing;
    winner = null;
    endReason = null;
    notifyListeners();
  }

  /// Resigns on behalf of the local player (network/engine games).
  void resign() {
    if (gameOver) return;
    // In practice mode both sides are the human, so the side to move
    // resigns; in engine/network games the local player is playerColor.
    final resigning = mode == GameMode.practice ? turn : playerColor;
    _endGame(
      status: GameStatus.resigned,
      winner: resigning == 'w' ? 'b' : 'w',
      reason: 'You resigned',
    );
    notifyListeners();
  }

  /// Resets to the start position (optionally a custom FEN).
  void reset({String? fen}) {
    _game = boardFromFen(fen);
    history.clear();
    selectedSquare = null;
    targets = const {};
    lastMove = null;
    status = GameStatus.playing;
    winner = null;
    endReason = null;
    notifyListeners();
  }

  /// Rebuilds the position after [ply] half-moves from a fresh start
  /// position — used by the analysis screen to scrub through history.
  void replay(String startFen, List<String> sans, {required int ply}) {
    _game = boardFromFen(startFen);
    history.clear();
    selectedSquare = null;
    targets = const {};
    lastMove = null;
    status = GameStatus.playing;
    winner = null;
    endReason = null;
    final count = ply.clamp(0, sans.length);
    for (var i = 0; i < count; i++) {
      if (!playSan(sans[i], source: MoveSource.human)) break;
    }
    notifyListeners();
  }
}
