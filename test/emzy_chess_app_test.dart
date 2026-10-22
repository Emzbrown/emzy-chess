import 'package:chess/chess.dart';
import 'package:emzy_chess/game/game_controller.dart';
import 'package:emzy_chess/game/models.dart';
import 'package:emzy_chess/main.dart';
import 'package:emzy_chess/network/protocol.dart';
import 'package:emzy_chess/ui/widgets/chess_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EmzyChessApp', () {
    testWidgets('renders the home screen with all three modes',
        (tester) async {
      await tester.pumpWidget(const EmzyChessApp());

      expect(find.text('Emzy Chess'), findsOneWidget);
      expect(find.text('Play vs Stockfish'), findsOneWidget);
      expect(find.text('Play on Local Wi-Fi'), findsOneWidget);
      expect(find.text('Analyze a Game'), findsOneWidget);
    });
  });

  group('ChessBoard (unified input widget)', () {
    testWidgets('human touch selects and moves a piece', (tester) async {
      final game = GameController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: ChessBoard(controller: game)),
          ),
        ),
      );

      final boardRect = tester.getRect(find.byType(ChessBoard));
      final squareSize = boardRect.width / 8;

      // White orientation: e2 is file e (index 4), the 2nd rank from the
      // bottom (row 6 from the top).
      Offset squareCenter(String name) {
        final file = 'abcdefgh'.indexOf(name[0]);
        final rank = int.parse(name[1]);
        final row = 8 - rank;
        return Offset(
          boardRect.left + (file + 0.5) * squareSize,
          boardRect.top + (row + 0.5) * squareSize,
        );
      }

      await tester.tapAt(squareCenter('e2'));
      await tester.pump();
      expect(game.selectedSquare, 'e2');

      await tester.tapAt(squareCenter('e4'));
      await tester.pump();
      expect(game.history.single.san, 'e4');

      // The board still renders the new position without errors.
      expect(find.byType(ChessBoard), findsOneWidget);
    });

    testWidgets('accepts engine and network moves through one controller',
        (tester) async {
      final game = GameController(mode: GameMode.network, playerColor: 'w');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: ChessBoard(controller: game)),
          ),
        ),
      );

      // Stockfish bestmove arrives as UCI.
      expect(game.applyEngineMove('f2f3'), isTrue);
      await tester.pump();

      // The opponent's payload FEN mirrors the position after 1...e5, as a
      // healthy peer would send it.
      final afterE5 = Chess()
        ..move('f3')
        ..move('e5');
      final reply = NetworkMessage.move(san: 'e5', fen: afterE5.fen);
      expect(game.applyNetworkMove(reply), isTrue);
      await tester.pump();
      expect(game.fen, afterE5.fen); // no resync needed: payloads matched

      // Human touch continues the same game.
      game.applyTouch('g2');
      await tester.pump();
      expect(game.applyTouch('g4'), isTrue);
      await tester.pump();

      // The opponent delivers checkmate over the network.
      final afterMate = Chess()
        ..move('f3')
        ..move('e5')
        ..move('g4')
        ..move('Qh4#');
      expect(
        game.applyNetworkMove(NetworkMessage.move(
          san: 'Qh4#',
          fen: afterMate.fen,
        )),
        isTrue,
      );
      await tester.pump();

      expect(game.status, GameStatus.checkmate);
      expect(game.winner, 'b');
      expect(game.sans, ['f3', 'e5', 'g4', 'Qh4#']);
      expect(find.byType(ChessBoard), findsOneWidget);
    });

    testWidgets('a non-interactive board ignores touches', (tester) async {
      final game = GameController(interactive: false);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: ChessBoard(controller: game)),
          ),
        ),
      );

      final boardRect = tester.getRect(find.byType(ChessBoard));
      await tester.tapAt(
        Offset(boardRect.left + 4.5 * boardRect.width / 8,
            boardRect.top + 6.5 * boardRect.height / 8),
      );
      await tester.pump();

      expect(game.selectedSquare, isNull);
      expect(game.history, isEmpty);
    });
  });
}
