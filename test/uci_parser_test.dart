import 'package:emzy_chess/engine/uci_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseInfoLine', () {
    test('parses a fully-populated depth/score/pv line', () {
      const line =
          'info depth 14 seldepth 20 multipv 1 score cp 34 nodes 123456 nps 987654 pv e2e4 e7e5 g1f3';
      final info = parseInfoLine(line);

      expect(info, isNotNull);
      expect(info!.depth, 14);
      expect(info.seldepth, 20);
      expect(info.multipv, 1);
      expect(info.score!.cp, 34);
      expect(info.score!.mate, isNull);
      expect(info.nodes, 123456);
      expect(info.nps, 987654);
      expect(info.pv, ['e2e4', 'e7e5', 'g1f3']);
      expect(info.raw, line);
    });

    test('parses mate scores with bound flags', () {
      final info = parseInfoLine('info depth 8 score mate 3 lowerbound pv d8h4');
      expect(info!.score!.mate, 3);
      expect(info.score!.lowerBound, isTrue);
      expect(info.score!.upperBound, isFalse);
      expect(info.score!.isMate, isTrue);
    });

    test('rejects lines without a depth or score', () {
      expect(parseInfoLine('info string heuristic info'), isNull);
      expect(parseInfoLine('readyok'), isNull);
      expect(parseInfoLine('bestmove e2e4'), isNull);
    });
  });

  group('parseBestMove', () {
    test('extracts bestmove and ponder', () {
      expect(parseBestMove('bestmove e2e4 ponder e7e5'), 'e2e4');
      expect(parsePonderMove('bestmove e2e4 ponder e7e5'), 'e7e5');
    });

    test('surfaces (none) as null and ignores other lines', () {
      expect(parseBestMove('bestmove (none)'), isNull);
      expect(parseBestMove('info depth 1'), isNull);
      expect(parsePonderMove('bestmove e2e4'), isNull);
    });
  });

  group('EngineScore', () {
    test('whitePov passes cp and mate through', () {
      const cp = EngineScore(cp: 42);
      expect(cp.whitePov.cp, 42);
      expect(cp.whitePov.mate, isNull);

      const mate = EngineScore(mate: -2);
      expect(mate.whitePov.mate, -2);
      expect(mate.whitePov.cp, isNull);
    });

    test('toString renders compact labels', () {
      expect(const EngineScore(cp: 30).toString(), 'cp 30');
      expect(const EngineScore(mate: 4).toString(), 'M4');
    });
  });
}
