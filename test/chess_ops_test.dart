import 'package:chess/chess.dart';
import 'package:emzy_chess/game/chess_ops.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('legalMovesFrom', () {
    test('lists the opening moves of a pawn', () {
      final entries = legalMovesFrom(Chess(), 'e2');
      final targets = entries.map((e) => e.to).toSet();
      expect(targets, {'e3', 'e4'});
      expect(entries.map((e) => e.san), containsAll(['e3', 'e4']));
    });

    test('empty or opponent squares yield no moves', () {
      expect(legalMovesFrom(Chess(), 'e4'), isEmpty);
      expect(legalMovesFrom(Chess(), 'e7'), isEmpty);
    });

    test('filters moves that would leave the king in check', () {
      // White king on e1, black rook on e8: the king may not step onto e2.
      final board = Chess.fromFEN('4k3/4r3/8/8/8/8/8/4K3 w - - 0 1');
      final targets = legalMovesFrom(board, 'e1').map((e) => e.to).toSet();
      expect(targets, isNot(contains('e2')));
      expect(targets, containsAll(['d1', 'f1', 'd2', 'f2']));
    });
  });

  group('findMove / moveEntryFromUci', () {
    test('resolves coordinate moves to SAN', () {
      final entry = moveEntryFromUci(Chess(), 'e2e4');
      expect(entry, isNotNull);
      expect(entry!.san, 'e4');
      expect(entry.from, 'e2');
      expect(entry.to, 'e4');
    });

    test('rejects illegal coordinate moves', () {
      expect(moveEntryFromUci(Chess(), 'e2e5'), isNull);
      expect(moveEntryFromUci(Chess(), 'a1a3'), isNull);
      expect(moveEntryFromUci(Chess(), 'junk'), isNull);
    });

    test('handles promotion piece letters', () {
      final board = Chess.fromFEN('4k3/P7/8/8/8/8/8/4K3 w - - 0 1');
      final entry = moveEntryFromUci(board, 'a7a8q');
      expect(entry, isNotNull);
      expect(entry!.promotion, 'q');
      expect(entry.san, 'a8=Q+');

      // Underpromotion is its own legal move and resolves correctly.
      final knight = moveEntryFromUci(board, 'a7a8n');
      expect(knight, isNotNull);
      expect(knight!.promotion, 'n');
      expect(knight.san, 'a8=N');
    });
  });

  group('findMoveBySan', () {
    test('matches castling and captures by SAN', () {
      final board = Chess.fromFEN(
          'r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1');
      expect(findMoveBySan(board, 'O-O')!.to, 'g1');
      expect(findMoveBySan(board, 'O-O-O')!.to, 'c1');
      expect(findMoveBySan(board, 'Qd1xh5'), isNull);

      final middlegame = Chess.fromFEN('4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1');
      expect(findMoveBySan(middlegame, 'exd5'), isNotNull);
    });
  });

  group('pvToSan', () {
    test('converts a UCI principal variation to SAN', () {
      final sans = pvToSan(Chess(), ['e2e4', 'e7e5', 'g1f3']);
      expect(sans, ['e4', 'e5', 'Nf3']);
    });

    test('stops at the first illegal move', () {
      final sans = pvToSan(Chess(), ['e2e4', 'e7e5', 'd1d7']);
      expect(sans, ['e4', 'e5']);
    });
  });

  group('FEN helpers', () {
    test('boardFromFen falls back to the start position on bad input', () {
      expect(boardFromFen(null).fen, Chess.DEFAULT_POSITION);
      expect(boardFromFen('nonsense').fen, Chess.DEFAULT_POSITION);
    });

    test('turnOfFen reads the side to move', () {
      expect(turnOfFen(Chess.DEFAULT_POSITION), 'w');
      expect(
          turnOfFen('4k3/8/8/8/8/8/8/4K3 b - - 0 1'), 'b');
    });

    test('colorToWire maps package colors to w/b', () {
      expect(colorToWire(Chess.WHITE), 'w');
      expect(colorToWire(Chess.BLACK), 'b');
    });
  });
}
