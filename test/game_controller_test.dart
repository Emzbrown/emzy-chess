import 'package:chess/chess.dart';
import 'package:emzy_chess/game/game_controller.dart';
import 'package:emzy_chess/game/models.dart';
import 'package:emzy_chess/network/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('human touch input', () {
    test('selects a piece, highlights targets, then commits the move', () {
      final game = GameController();

      expect(game.applyTouch('e2'), isFalse);
      expect(game.selectedSquare, 'e2');
      expect(game.targets.keys, containsAll(['e3', 'e4']));

      expect(game.applyTouch('e4'), isTrue);
      expect(game.history, hasLength(1));
      expect(game.history.single.san, 'e4');
      expect(game.history.single.source, MoveSource.human);
      expect(game.turn, 'b');
      expect(game.selectedSquare, isNull);
    });

    test('tapping an illegal target just deselects', () {
      final game = GameController();
      game.applyTouch('e2');
      expect(game.applyTouch('e5'), isFalse);
      expect(game.selectedSquare, isNull);
      expect(game.history, isEmpty);
    });

    test('a non-interactive board ignores touches', () {
      final game = GameController(interactive: false);
      expect(game.applyTouch('e2'), isFalse);
      expect(game.selectedSquare, isNull);
    });

    test('touch-promotion defaults to queen', () {
      final game = GameController(fen: '4k3/P7/8/8/8/8/8/4K3 w - - 0 1');
      game.applyTouch('a7');
      expect(game.applyTouch('a8'), isTrue);
      expect(game.history.single.promotion, 'q');
      expect(game.history.single.san, 'a8=Q+');
    });
  });

  group('engine input (UCI bestmove)', () {
    test('applies a legal engine move as MoveSource.engine', () {
      final game = GameController(mode: GameMode.engine);
      expect(game.applyEngineMove('e2e4'), isTrue);
      expect(game.history.single.san, 'e4');
      expect(game.history.single.source, MoveSource.engine);
    });

    test('honours the promotion piece from the engine', () {
      final game =
          GameController(fen: '4k3/P7/8/8/8/8/8/4K3 w - - 0 1');
      expect(game.applyEngineMove('a7a8q'), isTrue);
      expect(game.history.single.san, 'a8=Q+');
      expect(game.history.single.promotion, 'q');
    });

    test('rejects an illegal engine move', () {
      final game = GameController();
      expect(game.applyEngineMove('e2e5'), isFalse);
      expect(game.history, isEmpty);
    });
  });

  group('network input (JSON over TCP)', () {
    test('applies a MOVE payload as MoveSource.network', () {
      final game = GameController(mode: GameMode.network, playerColor: 'b');
      final message = NetworkMessage.move(
        san: 'e4',
        fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 1 1',
      );

      expect(game.applyNetworkMove(message), isTrue);
      expect(game.history.single.san, 'e4');
      expect(game.history.single.source, MoveSource.network);
    });

    test('resyncs to the reported FEN when the SAN does not fit', () {
      final game = GameController(mode: GameMode.network, playerColor: 'b');
      final drifted = NetworkMessage.move(
        san: 'Qd8h4',
        fen: 'rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3',
      );

      expect(game.applyNetworkMove(drifted), isTrue);
      expect(game.fen, drifted.fen);
      expect(game.history, isEmpty);
    });

    test('NEW_GAME resets and RESIGN ends the game for the opponent', () {
      final game = GameController(mode: GameMode.network, playerColor: 'b');
      game.applyNetworkMove(NetworkMessage.move(san: 'e4', fen: 'x'));

      game.applyNetworkMove(NetworkMessage.newGame());
      expect(game.history, isEmpty);
      expect(game.status, GameStatus.playing);

      game.applyNetworkMove(NetworkMessage.resign());
      expect(game.status, GameStatus.resigned);
      expect(game.winner, 'b'); // White resigned while it is White's turn.
      expect(game.result, '0-1');
    });
  });

  group('turn gating', () {
    test('a network player cannot move on the opponent turn', () {
      final game = GameController(mode: GameMode.network, playerColor: 'b');
      expect(game.turn, 'w');
      expect(game.canHumanMove, isFalse);
      expect(game.applyTouch('e2'), isFalse);
    });
  });

  gameEndings() {
    // Fool's mate: 1. f3 e5 2. g4 Qh4#
    final game = GameController();
    for (final uci in ['f2f3', 'e7e5', 'g2g4', 'd8h4']) {
      expect(game.applyEngineMove(uci), isTrue, reason: 'failed at $uci');
    }
    return game;
  }

  group('game endings', () {
    test('detects checkmate with result and winner', () {
      final game = gameEndings();
      expect(game.status, GameStatus.checkmate);
      expect(game.winner, 'b');
      expect(game.result, '0-1');
      expect(game.gameOver, isTrue);
      expect(game.applyEngineMove('a2a4'), isFalse);
    });

    test('resign() awards the win to the opponent', () {
      final game = GameController(mode: GameMode.engine, playerColor: 'w');
      game.applyEngineMove('e2e4');
      game.resign();
      expect(game.status, GameStatus.resigned);
      expect(game.winner, 'b');
      expect(game.endReason, 'You resigned');
    });

    test('reset restores the initial position', () {
      final game = gameEndings();
      game.reset();
      expect(game.history, isEmpty);
      expect(game.status, GameStatus.playing);
      expect(game.fen, Chess.DEFAULT_POSITION);
      expect(game.result, '*');
    });
  });

  group('replay', () {
    test('rebuilds the position after N plies', () {
      final game = GameController();
      for (final uci in ['e2e4', 'e7e5', 'g1f3']) {
        game.applyEngineMove(uci);
      }
      final fullFen = game.fen;

      game.replay('', [], ply: 0);
      game.replay(
        'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        ['e4', 'e5', 'Nf3'],
        ply: 3,
      );
      expect(game.fen, fullFen);
      expect(game.sans, ['e4', 'e5', 'Nf3']);

      game.replay(
        'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        ['e4', 'e5', 'Nf3'],
        ply: 1,
      );
      expect(game.sans, ['e4']);
      expect(game.turn, 'b');
    });
  });
}
