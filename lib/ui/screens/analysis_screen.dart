import 'package:chess/chess.dart' show Chess;
import 'package:flutter/material.dart';

import '../../engine/engine_manager.dart';
import '../../game/analysis_controller.dart';
import '../../game/game_controller.dart';
import '../../game/models.dart';
import '../widgets/chess_board.dart';
import '../widgets/eval_bar.dart';
import '../widgets/eval_graph.dart';
import '../widgets/move_list.dart';

/// Game analysis: board + Stockfish eval bar + move-by-move evaluation graph.
class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({
    super.key,
    required this.sans,
    this.startFen,
    this.title = 'Analysis',
  });

  /// Half-moves of the game to analyse.
  final List<String> sans;

  /// Starting FEN; null means the standard initial position.
  final String? startFen;
  final String title;

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  final GameController _board = GameController(interactive: false);
  AnalysisController? _analysis;
  String _engineError = '';
  bool _starting = true;

  static const List<int> _depths = [8, 12, 16, 20];
  int _depthIndex = 1;

  @override
  void initState() {
    super.initState();
    _startEngine();
  }

  String get _startFen =>
      (widget.startFen == null || widget.startFen!.trim().isEmpty)
          ? Chess.DEFAULT_POSITION
          : widget.startFen!;

  Future<void> _startEngine() async {
    setState(() {
      _starting = true;
      _engineError = '';
    });
    try {
      final engine = await EngineManager.instance.ensureStarted();
      if (!mounted) return;
      final analysis = AnalysisController(engine: engine)
        ..load(startFen: _startFen, sans: widget.sans);
      analysis.addListener(() {
        if (mounted) setState(() {});
        _syncBoard();
      });
      setState(() {
        _analysis = analysis;
        _starting = false;
      });
      _syncBoard();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _engineError = '$error';
        _starting = false;
      });
    }
  }

  void _syncBoard() {
    final analysis = _analysis;
    if (analysis == null) return;
    _board.replay(_startFen, widget.sans, ply: analysis.focusPly);
  }

  Future<void> _toggleAnalysis() async {
    final analysis = _analysis;
    if (analysis == null) return;
    if (analysis.analyzing) {
      await analysis.cancel();
    } else {
      await analysis.analyzeAll(depth: _depths[_depthIndex]);
    }
  }

  @override
  void dispose() {
    unawaitedStop();
    _board.dispose();
    super.dispose();
  }

  Future<void> unawaitedStop() async {
    final analysis = _analysis;
    if (analysis != null && analysis.analyzing) {
      await analysis.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final analysis = _analysis;
    final evals = analysis?.evals ?? const <PlyEvaluation?>[];
    final focusPly = analysis?.focusPly ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (analysis != null)
            PopupMenuButton<int>(
              icon: const Icon(Icons.speed),
              tooltip: 'Engine depth',
              initialValue: _depthIndex,
              onSelected: (value) => setState(() => _depthIndex = value),
              itemBuilder: (context) => [
                for (var i = 0; i < _depths.length; i++)
                  PopupMenuItem(
                    value: i,
                    child: Text('Depth ${_depths[i]}'),
                  ),
              ],
            ),
          IconButton(
            tooltip: 'Analyse current position only',
            icon: const Icon(Icons.bolt),
            onPressed: analysis == null || analysis.analyzing
                ? null
                : () => analysis.analyzeFocus(depth: _depths[_depthIndex] + 4),
          ),
        ],
      ),
      body: SafeArea(
        child: _starting
            ? const Center(child: CircularProgressIndicator())
            : analysis == null
                ? _EngineFailed(error: _engineError, onRetry: _startEngine)
                : _buildBody(context, analysis, evals, focusPly),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AnalysisController analysis,
    List<PlyEvaluation?> evals,
    int focusPly,
  ) {
    final focusEval = analysis.focusEval;
    final wide = MediaQuery.sizeOf(context).width >= 720;

    final boardArea = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EvalBar(evaluation: focusEval),
        const SizedBox(width: 8),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: ChessBoard(controller: _board),
            ),
          ),
        ),
      ],
    );

    final sidePanel = Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            focusEval == null
                ? 'No evaluation yet — press Analyze'
                : 'Ply $focusPly · ${focusEval.label} · depth ${focusEval.depth}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        if (focusEval != null && focusEval.pvSan.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              focusEval.pvSan.join(' '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
        if (analysis.error != null)
          Text(
            analysis.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (analysis.analyzing)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: LinearProgressIndicator(value: analysis.progress),
          ),
        Expanded(
          child: MoveList(
            sans: widget.sans,
            focusPly: focusPly,
            onSelect: (ply) => analysis.focus(ply),
          ),
        ),
        SizedBox(
          height: 150,
          child: EvalGraph(
            evals: evals,
            focusPly: focusPly,
            onFocus: (ply) => analysis.focus(ply),
          ),
        ),
      ],
    );

    return Column(
      children: [
        if (wide)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: boardArea),
                Expanded(flex: 4, child: sidePanel),
              ],
            ),
          )
        else
          Expanded(
            child: Column(
              children: [
                Expanded(flex: 5, child: boardArea),
                Expanded(flex: 4, child: sidePanel),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: FilledButton.icon(
            onPressed: _toggleAnalysis,
            icon: Icon(analysis.analyzing ? Icons.stop : Icons.play_arrow),
            label: Text(analysis.analyzing
                ? 'Stop analysis'
                : 'Analyze (depth ${_depths[_depthIndex]})'),
          ),
        ),
      ],
    );
  }
}

class _EngineFailed extends StatelessWidget {
  const _EngineFailed({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 42, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(
              'Stockfish could not start on this device.\n$error',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
