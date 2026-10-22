import 'package:flutter/material.dart';

/// Tappable list of SAN moves. Tap chip i to focus ply i + 1.
class MoveList extends StatelessWidget {
  const MoveList({
    super.key,
    required this.sans,
    this.focusPly = 0,
    this.onSelect,
  });

  final List<String> sans;
  final int focusPly;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    if (sans.isEmpty) {
      return const Center(
        child: Text('No moves yet', style: TextStyle(color: Colors.black45)),
      );
    }
    return Align(
      alignment: Alignment.topLeft,
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (var i = 0; i < sans.length; i++) ...[
            if (i.isEven)
              Text(
                '${i ~/ 2 + 1}.',
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            _MoveChip(
              san: sans[i],
              highlighted: focusPly == i + 1,
              onTap: onSelect == null ? null : () => onSelect!(i + 1),
            ),
          ],
        ],
      ),
    );
  }
}

class _MoveChip extends StatelessWidget {
  const _MoveChip({required this.san, required this.highlighted, this.onTap});

  final String san;
  final bool highlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: highlighted ? Theme.of(context).colorScheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          san,
          style: TextStyle(
            fontSize: 14,
            fontWeight: highlighted ? FontWeight.bold : FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
