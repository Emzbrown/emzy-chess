import 'package:chess/chess.dart' show Chess, Piece;
import 'package:flutter/material.dart';

import '../../game/game_controller.dart';
import '../../game/models.dart';

/// The unified chess board.
///
/// Renders whatever position the [GameController] holds and funnels input
/// back through the [BoardInput] interface, so a single widget serves all
/// three move sources:
///   * human touches        -> [GameController.applyTouch]
///   * Stockfish best moves -> [GameController.applyEngineMove]
///   * TCP network payloads -> [GameController.applyNetworkMove]
class ChessBoard extends StatelessWidget {
  const ChessBoard({
    super.key,
    required this.controller,
    this.orientation = 'w',
  });

  /// Readable/writable game state; also the [BoardInput] sink.
  final GameController controller;

  /// `w` = White at the bottom, `b` = Black at the bottom.
  final String orientation;

  static const Color lightSquare = Color(0xFFF0D9B5);
  static const Color darkSquare = Color(0xFFB58863);
  static const Color lastMoveColor = Color(0x66F7E56B);
  static const Color selectedColor = Color(0xB3F7F757);
  static const Color checkColor = Color(0x99E05D5D);

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final squareSize = constraints.maxWidth / 8;
            return Column(
              children: [
                for (var row = 0; row < 8; row++)
                  Row(
                    children: [
                      for (var col = 0; col < 8; col++)
                        _buildSquare(
                          context,
                          square: _squareAt(row, col),
                          size: squareSize,
                          row: row,
                          col: col,
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _squareAt(int row, int col) {
    final file = orientation == 'w' ? col : 7 - col;
    final rank = orientation == 'w' ? 7 - row : row;
    return '${'abcdefgh'[file]}${rank + 1}';
  }

  Widget _buildSquare(
    BuildContext context, {
    required String square,
    required double size,
    required int row,
    required int col,
  }) {
    final fileIndex = 'abcdefgh'.indexOf(square[0]);
    final rankIndex = int.parse(square[1]) - 1;
    final isLight = (fileIndex + rankIndex) % 2 == 0;
    final piece = controller.game.get(square);

    final isSelected = controller.selectedSquare == square;
    final isLastMove = controller.lastMove != null &&
        (controller.lastMove!.from == square || controller.lastMove!.to == square);
    final isCheckSquare = controller.checkedKingSquare == square;
    final target = controller.targets[square];

    Color color = isLight ? lightSquare : darkSquare;
    if (isLastMove) color = Color.lerp(color, lastMoveColor, 1)!;
    if (isCheckSquare) color = Color.lerp(color, checkColor, 1)!;

    final children = <Widget>[
      Positioned.fill(
        child: ColoredBox(color: color),
      ),
      if (isSelected)
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selectedColor,
              border: Border.all(color: Colors.black.withValues(alpha: 0.35), width: 2),
            ),
          ),
        ),
      if (target != null)
        Positioned.fill(child: _TargetIndicator(isCapture: target.isCapture)),
    ];

    if (piece != null) {
      children.add(Center(
        child: Text(
          _pieceGlyph(piece),
          style: TextStyle(
            fontSize: size * 0.78,
            height: 1.0,
            shadows: const [
              Shadow(offset: Offset(0.6, 0.9), blurRadius: 1.2, color: Colors.black45),
            ],
          ),
        ),
      ));
    }

    // Coordinates on the board edges.
    if (row == 7) {
      children.add(Positioned(
        right: 2,
        bottom: 1,
        child: _coordinate(square[0], isLight),
      ));
    }
    if (col == 0) {
      children.add(Positioned(
        left: 2,
        top: 1,
        child: _coordinate(square[1], isLight),
      ));
    }

    return Expanded(
      child: GestureDetector(
        key: ValueKey<String>('square-$square'),
        behavior: HitTestBehavior.opaque,
        onTap: () => controller.applyTouch(square),
        // A Row hands Expanded children unbounded height; the square Stack
        // (all children positioned) needs an explicit size to survive that.
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(children: children),
        ),
      ),
    );
  }

  Widget _coordinate(String value, bool isLight) => Text(
        value,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: isLight ? darkSquare : lightSquare,
        ),
      );

  static const Map<String, String> _whiteGlyphs = {
    'k': '♔',
    'q': '♕',
    'r': '♖',
    'b': '♗',
    'n': '♘',
    'p': '♙',
  };
  static const Map<String, String> _blackGlyphs = {
    'k': '♚',
    'q': '♛',
    'r': '♜',
    'b': '♝',
    'n': '♞',
    'p': '♟',
  };

  static String _pieceGlyph(Piece piece) {
    String? letter;
    for (final entry in Chess.PIECE_TYPES.entries) {
      if (entry.value == piece.type) {
        letter = entry.key;
        break;
      }
    }
    if (letter == null) return '';
    final map = piece.color == Chess.WHITE ? _whiteGlyphs : _blackGlyphs;
    return map[letter] ?? '';
  }
}

/// Dot on empty legal targets, ring on capture targets.
class _TargetIndicator extends StatelessWidget {
  const _TargetIndicator({required this.isCapture});

  final bool isCapture;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: isCapture
            ? Container(
                width: double.infinity,
                height: double.infinity,
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black.withValues(alpha: 0.28), width: 5),
                ),
              )
            : Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.25),
                ),
              ),
      ),
    );
  }
}

/// Convenience accessor used by screens: the move source of the newest move.
extension MoveSourceLabel on MoveSource {
  String get label => switch (this) {
        MoveSource.human => 'You',
        MoveSource.engine => 'Stockfish',
        MoveSource.network => 'Opponent',
      };
}
