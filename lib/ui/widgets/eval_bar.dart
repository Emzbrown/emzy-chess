import 'package:flutter/material.dart';

import '../../game/models.dart';

/// Vertical evaluation bar (White's advantage fills upward from the bottom).
class EvalBar extends StatelessWidget {
  const EvalBar({
    super.key,
    required this.evaluation,
    this.orientation = 'w',
  });

  /// Evaluation to display; null shows an empty, neutral bar.
  final PlyEvaluation? evaluation;

  /// `w` puts White at the bottom of the bar, matching the board.
  final String orientation;

  @override
  Widget build(BuildContext context) {
    final fraction = (evaluation?.barFraction ?? 0) * 0.5 + 0.5; // 0..1, White share
    final whiteShare = (fraction * 1000).round();
    final blackShare = 1000 - whiteShare;

    final whiteFirst = orientation == 'w';
    final children = whiteFirst
        ? [
            Expanded(flex: blackShare, child: Container(color: const Color(0xFF2E2E2E))),
            Expanded(flex: whiteShare, child: Container(color: const Color(0xFFF5F5F5))),
          ]
        : [
            Expanded(flex: whiteShare, child: Container(color: const Color(0xFFF5F5F5))),
            Expanded(flex: blackShare, child: Container(color: const Color(0xFF2E2E2E))),
          ];

    return Container(
      width: 28,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Column(children: children),
          if (evaluation != null)
            Positioned(
              top: whiteFirst ? 3 : null,
              bottom: whiteFirst ? null : 3,
              left: 0,
              right: 0,
              child: Text(
                evaluation!.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.bold,
                  color: whiteFirst ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
