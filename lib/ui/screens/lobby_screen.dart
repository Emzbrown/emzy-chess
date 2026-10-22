import 'package:flutter/material.dart';

import '../../network/p2p_service.dart';
import 'network_game_screen.dart';

/// Host or join a game over local Wi-Fi.
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final P2pService _p2p = P2pService();
  final TextEditingController _nameController =
      TextEditingController(text: 'Player');

  bool _hosting = false;
  bool _browsing = false;
  int? _hostPort;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    _p2p.addListener(_onP2pChanged);
  }

  void _onP2pChanged() {
    if (!mounted) return;
    setState(() {});

    if (_p2p.status == P2pStatus.connected) {
      final color = _hosting ? 'w' : 'b';
      final name = _nameController.text.trim();
      Navigator.of(context)
          .push(
            MaterialPageRoute<void>(
              builder: (_) => NetworkGameScreen(
                p2p: _p2p,
                playerName: name.isEmpty ? 'Player' : name,
                playerColor: color,
                isHost: _hosting,
              ),
            ),
          )
          .then((_) => _resetToIdle());
    }
  }

  Future<void> _host() async {
    final name = _nameController.text.trim();
    setState(() => _hosting = true);
    try {
      final port = await _p2p.host(playerName: name.isEmpty ? 'Chess host' : name);
      if (!mounted) return;
      setState(() => _hostPort = port);
    } catch (_) {
      if (!mounted) return;
      setState(() => _hosting = false);
    }
  }

  Future<void> _browse() async {
    setState(() => _browsing = true);
    try {
      await _p2p.browse();
    } catch (_) {
      if (!mounted) return;
      setState(() => _browsing = false);
    }
  }

  Future<void> _join(PeerDevice peer) async {
    setState(() => _joining = true);
    try {
      await _p2p.connectTo(peer);
    } catch (_) {
      if (!mounted) return;
      setState(() => _joining = false);
    }
  }

  Future<void> _resetToIdle() async {
    await _p2p.close();
    if (!mounted) return;
    setState(() {
      _hosting = false;
      _browsing = false;
      _hostPort = null;
      _joining = false;
    });
  }

  @override
  void dispose() {
    _p2p.removeListener(_onP2pChanged);
    _p2p.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _p2p.error;
    return PopScope(
      canPop: !_hosting && !_browsing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _resetToIdle();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Local Wi-Fi Game')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Your name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.campaign),
                        SizedBox(width: 8),
                        Text('Host a table',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (!_hosting) ...[
                      const Text(
                          'Advertises _chess-game._tcp so friends on the same '
                          'Wi-Fi can find you. You play White.'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _host,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Host game'),
                      ),
                    ] else if (_p2p.status == P2pStatus.hosting) ...[
                      Text(
                        _hostPort == null
                            ? 'Starting table…'
                            : 'Waiting for an opponent on port $_hostPort…',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Keep this screen open — the game starts as soon as '
                        'someone joins.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.wifi),
                        SizedBox(width: 8),
                        Text('Join a table',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (!_browsing)
                      FilledButton.icon(
                        onPressed: _browse,
                        icon: const Icon(Icons.search),
                        label: const Text('Find games'),
                      )
                    else ...[
                      if (_p2p.peers.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 12),
                              Text('Scanning the local network…'),
                            ],
                          ),
                        ),
                      for (final peer in _p2p.peers)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.lan),
                          title: Text(peer.name),
                          subtitle: Text('${peer.address.address}:${peer.port}'),
                          trailing: FilledButton(
                            onPressed:
                                _joining ? null : () => _join(peer),
                            child: const Text('Join'),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
