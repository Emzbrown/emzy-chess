import 'dart:async';

import 'package:flutter/material.dart';

import '../../engine/engine_manager.dart';
import '../../engine/uci_engine.dart';
import '../../game/game_controller.dart';
import '../../game/models.dart';
import '../widgets/chess_board.dart';
import '../widgets/move_list.dart';
import 'analysis_screen.dart';

/// Offline game against Stockfish.
///
/// The human (White) plays by touching the board; every engine `bestmove`
/// arrives through [GameController.applyEngineMove], the same unified input
/// used for network moves.
class EngineGameScreen extends StatefulWidget {
  const EngineGameScreen({super.key});

  @override
  State<EngineGameScreen> createState() => _EngineGameScreenState();
}

class _EngineGameScreenState extends State<EngineGameScreen> {
  final GameController _game = GameController(mode: GameMode.engine, playerColor: 'w');
  final ScrollController _moveScroll = ScrollController();

  UciEngine? _engine;
  String? _engineError;
  bool _thinking = false;

  /// Engine search budget per strength level.
  static const List<int> _movetimes = [200, 500, 1000, 2500, 5000];
  int _level = 2;

  /// Highest history length the engine has already answered.
  int _answeredPly = 0;

  @override
  void initState() {
    super.initState();
    _game.addListener(_onGameChanged);
    _startEngine();
  }

  Future<void> _startEngine() async {
    setState(() {
      _engineError = null;
      _thinking = true;
    });
    try {
      final engine = await EngineManager.instance.ensureStarted();
      if (!mounted) return;
      setState(() {
        _engine = engine;
        _thinking = false;
      });
      await engine.newGame();
      unawaited(_maybeEngineMove());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _engineError = '$error';
        _thinking = false;
      });
    }
  }

  void _onGameChanged() {
    _maybeEngineMove();
    if (_game.ply > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_moveScroll.hasClients) {
          _moveScroll.animateTo(
            _moveScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _maybeEngineMove() async {
    final engine = _engine;
    if (engine == null || _thinking || _game.gameOver) return;
    final lastMove = _game.lastMove;
    if (lastMove == null || lastMove.source != MoveSource.human) return;
    if (_game.ply <= _answeredPly) return;
    _answeredPly = _game.ply;

    setState(() => _thinking = true);
    try {
      final uci = await engine.bestMove(
        fen: _game.fen,
        movetimeMs: _movetimes[_level],
      );
      if (!mounted) return;
      _game.applyEngineMove(uci);
    } on EngineException catch (error) {
      if (!mounted) return;
      setState(() => _engineError = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _engineError = 'Engine error: $error');
    } finally {
      if (mounted) setState(() => _thinking = false);
    }
  }

  void _newGame() {
    _game.reset();
    _answeredPly = 0;
    _engine?.newGame();
    _maybeEngineMove();
  }

  @override
  void dispose() {
    _game.removeListener(_onGameChanged);
    _game.dispose();
    _moveScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engineError = _engineError;
    return Scaffold(
      appBar: AppBar(
        title: const Text('vs Stockfish'),
        actions: [
          IconButton(
            tooltip: 'Analyse this game',
            icon: const Icon(Icons.insights),
            onPressed: _game.ply == 0
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AnalysisScreen(
                          startFen: null,
                          sans: List.of(_game.sans),
                          title: 'Engine game analysis',
                        ),
                      ),
                    ),
          ),
          IconButton(
            tooltip: 'New game',
            icon: const Icon(Icons.refresh),
            onPressed: _newGame,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (engineError != null)
              MaterialBanner(
                content: Text('Engine unavailable: $engineError', maxLines: 2),
                actions: [
                  TextButton(
                    onPressed: _startEngine,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                _thinking ? 'Stockfish is thinking…' : _game.statusText,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: ChessBoard(controller: _game),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 76,
              child: MoveList(sans: _game.sans, focusPly: _game.ply),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.speed, size: 18),
                  Expanded(
                    child: Slider(
                      value: _level.toDouble(),
                      min: 0,
                      max: (_movetimes.length - 1).toDouble(),
                      divisions: _movetimes.length - 1,
                      label: 'Level ${_level + 1}',
                      onChanged: (value) =>
                          setState(() => _level = value.round()),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _game.gameOver ? null : _game.resign,
                    icon: const Icon(Icons.flag),
                    label: const Text('Resign'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
