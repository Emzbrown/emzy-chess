import 'package:chess/chess.dart';
import 'package:flutter/material.dart';

import 'analysis_screen.dart';
import 'engine_game_screen.dart';
import 'lobby_screen.dart';

/// Entry point: pick between Stockfish, local Wi-Fi, or analysis.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emzy Chess'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ModeCard(
            icon: Icons.smart_toy_outlined,
            title: 'Play vs Stockfish',
            subtitle: 'Offline engine game with adjustable strength',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const EngineGameScreen()),
            ),
          ),
          _ModeCard(
            icon: Icons.wifi_tethering,
            title: 'Play on Local Wi-Fi',
            subtitle: 'Host a table or join a friend over mDNS discovery',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const LobbyScreen()),
            ),
          ),
          _ModeCard(
            icon: Icons.insights,
            title: 'Analyze a Game',
            subtitle: 'Stockfish evaluation bar and move-by-move graph',
            onTap: () => _openAnalysis(context),
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text(
              'Games run fully offline — the engine never touches the network.',
              style: TextStyle(fontSize: 12, color: Colors.black45),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAnalysis(BuildContext context) async {
    final controller = TextEditingController(text: Chess.DEFAULT_POSITION);
    final fen = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Analyse from a position'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'FEN',
            border: OutlineInputBorder(),
            helperText: 'Leave as-is to start from the initial position.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    if (fen == null || !context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AnalysisScreen(
          startFen: fen.isEmpty ? Chess.DEFAULT_POSITION : fen,
          sans: const [],
          title: 'Position analysis',
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
