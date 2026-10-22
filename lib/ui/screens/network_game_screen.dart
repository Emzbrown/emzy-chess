import 'dart:async';

import 'package:flutter/material.dart';

import '../../network/p2p_service.dart';
import '../../network/protocol.dart';
import '../../game/game_controller.dart';
import '../../game/models.dart';
import '../widgets/chess_board.dart';
import '../widgets/move_list.dart';

/// The P2P game screen.
///
/// Every local move becomes `{"type": "MOVE", "san": "...", "fen": "..."}`
/// on the TCP socket; every incoming MOVE payload is fed through the same
/// [GameController.applyNetworkMove] input the board uses for touches and
/// engine moves.
class NetworkGameScreen extends StatefulWidget {
  const NetworkGameScreen({
    super.key,
    required this.p2p,
    required this.playerName,
    required this.playerColor,
    required this.isHost,
  });

  final P2pService p2p;
  final String playerName;

  /// `w`/`b` — the host always plays White.
  final String playerColor;
  final bool isHost;

  @override
  State<NetworkGameScreen> createState() => _NetworkGameScreenState();
}

class _NetworkGameScreenState extends State<NetworkGameScreen> {
  late final GameController _game;
  StreamSubscription<NetworkMessage>? _messageSub;
  String? _opponentName;

  /// History length already reflected on the wire.
  int _sentPly = 0;

  @override
  void initState() {
    super.initState();
    _game = GameController(
      mode: GameMode.network,
      playerColor: widget.playerColor,
    );
    _game.addListener(_onGameChanged);
    _messageSub = widget.p2p.messages.listen(_onMessage);

    // HELLO handshake: the host assigns colors, both sides share names.
    widget.p2p.send(NetworkMessage.hello(
      name: widget.playerName,
      color: widget.playerColor,
    ));
  }

  void _onMessage(NetworkMessage message) {
    switch (message.type) {
      case NetworkMessageType.hello:
        setState(() => _opponentName = message.name);
      case NetworkMessageType.move:
      case NetworkMessageType.resign:
      case NetworkMessageType.newGame:
        _sentPly = _game.ply; // incoming move: do not echo it back
        _game.applyNetworkMove(message);
        if (message.type == NetworkMessageType.newGame) _sentPly = 0;
      case NetworkMessageType.sync:
        _game.applyNetworkMove(message);
      default:
        break;
    }
  }

  void _onGameChanged() {
    if (!mounted) return;
    setState(() {});

    final lastMove = _game.lastMove;
    if (lastMove != null &&
        lastMove.source == MoveSource.human &&
        _game.ply > _sentPly) {
      _sentPly = _game.ply;
      widget.p2p.sendMove(san: lastMove.san, fen: lastMove.fenAfter);
    }
  }

  void _newGame() {
    widget.p2p.send(NetworkMessage.newGame());
    _game.reset();
    _sentPly = 0;
  }

  void _resign() {
    widget.p2p.send(NetworkMessage.resign());
    _game.resign();
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _game.removeListener(_onGameChanged);
    _game.dispose();
    unawaited(widget.p2p.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myTurn = _game.canHumanMove && !_game.gameOver;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _opponentName == null
              ? 'Local game'
              : '${widget.playerName} vs $_opponentName',
        ),
        actions: [
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
            if (_game.status == GameStatus.disconnected || widget.p2p.error != null)
              MaterialBanner(
                content: Text(widget.p2p.error ?? _game.endReason ?? 'Connection lost'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Back to lobby'),
                  ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                _game.statusText,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(
              'You play ${widget.playerColor == 'w' ? 'White' : 'Black'}'
              '${myTurn ? ' — your move' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: ChessBoard(
                      controller: _game,
                      orientation: widget.playerColor,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 76,
              child: MoveList(sans: _game.sans, focusPly: _game.ply),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: _game.gameOver ? null : _resign,
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
