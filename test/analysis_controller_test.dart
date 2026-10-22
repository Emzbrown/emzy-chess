import 'package:chess/chess.dart';
import 'package:emzy_chess/engine/uci_engine.dart';
import 'package:emzy_chess/engine/uci_parser.dart';
import 'package:emzy_chess/game/analysis_controller.dart';
import 'package:emzy_chess/game/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scripted engine: answers each FEN with one canned info line.
class _FakeSearcher implements EngineSearcher {
  _FakeSearcher(this.script);

  final Map<String, EngineInfoLine> script;
  final List<String> requestedFens = [];

  @override
  Stream<EngineInfoLine> analyze({required String fen, required int depth}) {
    requestedFens.add(fen);
    final line = script[fen];
    if (line == null) return const Stream.empty();
    return Stream.fromIterable([line]);
  }

  @override
  Future<void> requestStop() async {}
}

EngineInfoLine _cp(int cp, {int depth = 12, List<String> pv = const []}) =>
    EngineInfoLine(depth: depth, score: EngineScore(cp: cp), pv: pv, raw: '');

EngineInfoLine _mate(int mate) =>
    EngineInfoLine(depth: 20, score: EngineScore(mate: mate), raw: '');

void main() {
  group('scoreToWhitePov', () {
    test('negates side-to-move scores for Black', () {
      expect(scoreToWhitePov(cp: 30, mate: null, whiteToMove: true).cp, 30);
      expect(scoreToWhitePov(cp: 30, mate: null, whiteToMove: false).cp, -30);
      expect(scoreToWhitePov(cp: null, mate: 2, whiteToMove: true).mate, 2);
      expect(scoreToWhitePov(cp: null, mate: 2, whiteToMove: false).mate, -2);
    });
  });

  group('PlyEvaluation display mapping', () {
    test('maps centipawns to a clamped display value and sigmoid bar', () {
      const even = PlyEvaluation(
          positionIndex: 0, cpWhite: 0, mateWhite: null, pvUci: [], pvSan: [], depth: 1);
      expect(even.displayValue, 0);
      expect(even.barFraction, closeTo(0, 0.001));
      expect(even.label, '+0.00');

      const winning = PlyEvaluation(
          positionIndex: 1, cpWhite: 250, mateWhite: null, pvUci: [], pvSan: [], depth: 1);
      expect(winning.displayValue, 250);
      expect(winning.barFraction, greaterThan(0));
      expect(winning.label, '+2.50');

      const huge = PlyEvaluation(
          positionIndex: 2, cpWhite: 5000, mateWhite: null, pvUci: [], pvSan: [], depth: 1);
      expect(huge.displayValue, 1000); // clamped
    });

    test('parks mate scores just inside the graph limits', () {
      const mateIn3 = PlyEvaluation(
          positionIndex: 0, cpWhite: 0, mateWhite: 3, pvUci: [], pvSan: [], depth: 1);
      expect(mateIn3.isMate, isTrue);
      expect(mateIn3.displayValue, 970); // 1000 - 3*10
      expect(mateIn3.barFraction, 1);
      expect(mateIn3.label, 'M3');

      const matedIn2 = PlyEvaluation(
          positionIndex: 0, cpWhite: 0, mateWhite: -2, pvUci: [], pvSan: [], depth: 1);
      expect(matedIn2.displayValue, -980);
      expect(matedIn2.barFraction, -1);
      expect(matedIn2.label, '-M2');
    });
  });

  group('AnalysisController', () {
    test('load() derives one FEN per position and stops at illegal SANs', () {
      final controller = AnalysisController(engine: _FakeSearcher({}));
      controller.load(startFen: Chess.DEFAULT_POSITION, sans: ['e4', 'e5', 'Nf3']);

      expect(controller.fens, hasLength(4)); // start + 3 plies
      expect(controller.sans, ['e4', 'e5', 'Nf3']);
      expect(controller.evals, hasLength(4));
      expect(controller.focusPly, 0);

      controller.load(startFen: Chess.DEFAULT_POSITION, sans: ['e4', 'zzz']);
      expect(controller.fens, hasLength(2)); // truncated at the illegal move
    });

    test('analyzeAll records White-POV evaluations for every position',
        () async {
      // Build the real FENs by playing the moves with the chess package.
      final board = Chess();
      final fens = <String>[board.fen];
      for (final san in ['e4', 'e5']) {
        board.move(san);
        fens.add(board.fen);
      }

      final engine = _FakeSearcher({
        fens[0]: _cp(25), // White to move: +25 stays +25.
        fens[1]: _cp(20), // Black to move: +20 flips to -20.
        fens[2]: _cp(-40), // White to move after 1.e4 e5: -40 stays -40.
      });
      final controller = AnalysisController(engine: engine)
        ..load(startFen: Chess.DEFAULT_POSITION, sans: ['e4', 'e5']);

      await controller.analyzeAll(depth: 10);

      expect(controller.analyzing, isFalse);
      expect(controller.error, isNull);
      expect(controller.evals.map((e) => e!.cpWhite).toList(), [25, -20, -40]);
      expect(engine.requestedFens, fens);
    });

    test('mate scores flip sign for the Black-to-move side', () async {
      // After 1. f3 e5 2. g4 it is Black to move and Qh4# mates in 1.
      final board = Chess();
      final fens = <String>[board.fen];
      for (final san in ['f3', 'e5', 'g4']) {
        board.move(san);
        fens.add(board.fen);
      }

      // The engine reports "mate 1" for the side to move (Black mates in one);
      // from White's point of view that is mate against White.
      final engine = _FakeSearcher({fens[3]: _mate(1)});
      final controller = AnalysisController(engine: engine)
        ..load(startFen: Chess.DEFAULT_POSITION, sans: ['f3', 'e5', 'g4']);

      await controller.analyzeAll();

      expect(controller.evals[0], isNull); // start position was not scripted
      expect(controller.evals[3]!.mateWhite, -1);
      expect(controller.evals[3]!.isMate, isTrue);
      expect(controller.evals[3]!.label, '-M1');

      // The same engine score from White to move stays positive.
      final whiteEngine = _FakeSearcher({Chess.DEFAULT_POSITION: _mate(1)});
      final whiteController = AnalysisController(engine: whiteEngine)
        ..load(startFen: Chess.DEFAULT_POSITION, sans: []);
      await whiteController.analyzeAll();
      expect(whiteController.evals[0]!.mateWhite, 1);
    });

    test('focus() clamps to the valid ply range', () {
      final controller = AnalysisController(engine: _FakeSearcher({}))
        ..load(startFen: Chess.DEFAULT_POSITION, sans: ['e4', 'e5']);
      controller.focus(99);
      expect(controller.focusPly, 2);
      controller.focus(-5);
      expect(controller.focusPly, 0);
      expect(controller.focusFen, Chess.DEFAULT_POSITION);
    });

    test('parsing a real engine line end-to-end', () {
      final info = parseInfoLine(
          'info depth 15 multipv 1 score cp -18 pv e7e5 g1f3');
      expect(info!.score!.cp, -18);
      expect(info.pv, ['e7e5', 'g1f3']);
    });
  });
}
