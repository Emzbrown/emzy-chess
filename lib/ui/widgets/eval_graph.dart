import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../game/models.dart';

/// Move-by-move evaluation graph (fl_chart).
///
/// X axis = half-move index (0 = start position), Y axis = evaluation in
/// centipawns from White's POV. Tapping the graph seeks the focused ply.
class EvalGraph extends StatelessWidget {
  const EvalGraph({
    super.key,
    required this.evals,
    required this.focusPly,
    this.onFocus,
  });

  final List<PlyEvaluation?> evals;
  final int focusPly;
  final ValueChanged<int>? onFocus;

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    for (var i = 0; i < evals.length; i++) {
      final evaluation = evals[i];
      if (evaluation == null) continue;
      spots.add(FlSpot(i.toDouble(), evaluation.displayValue));
    }

    final maxX = math.max(evals.length - 1, 1).toDouble();

    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 8, bottom: 2),
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: maxX,
          minY: -1050,
          maxY: 1050,
          clipData: const FlClipData.none(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 500,
            getDrawingHorizontalLine: (value) => FlLine(
              color: value == 0 ? Colors.black45 : Colors.black12,
              strokeWidth: value == 0 ? 1.2 : 0.8,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 2,
                getTitlesWidget: (value, meta) {
                  final ply = value.round();
                  if (ply.isEven) return const SizedBox.shrink();
                  return Text(
                    '${(ply + 1) ~/ 2}',
                    style: const TextStyle(fontSize: 9, color: Colors.black54),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 500,
                reservedSize: 34,
                getTitlesWidget: (value, meta) => Text(
                  _cpLabel(value),
                  style: const TextStyle(fontSize: 9, color: Colors.black54),
                ),
              ),
            ),
          ),
          extraLinesData: ExtraLinesData(
            verticalLines: [
              VerticalLine(
                x: focusPly.toDouble().clamp(0, maxX),
                color: Colors.blueGrey.withValues(alpha: 0.6),
                strokeWidth: 1,
                dashArray: [3, 3],
              ),
            ],
          ),
          lineBarsData: [
            if (spots.length >= 2)
              LineChartBarData(
                spots: spots,
                isCurved: false,
                barWidth: 2.2,
                color: Colors.indigo,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.indigo.withValues(alpha: 0.18),
                      Colors.indigo.withValues(alpha: 0.02),
                    ],
                  ),
                ),
              ),
          ],
          lineTouchData: LineTouchData(
            enabled: onFocus != null,
            touchCallback: (event, response) {
              if (event is! FlTapUpEvent && event is! FlPanEndEvent) return;
              // TouchLineBarSpot extends FlSpot in fl_chart 1.x.
              final spot = response?.lineBarSpots?.firstOrNull;
              if (spot == null || onFocus == null) return;
              onFocus!(spot.x.round().clamp(0, evals.length - 1));
            },
            touchTooltipData: const LineTouchTooltipData(),
            getTouchedSpotIndicator: (barData, indexes) => indexes
                .map(
                  (index) => TouchedSpotIndicatorData(
                    const FlLine(color: Colors.indigo, strokeWidth: 1),
                    FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) =>
                          FlDotCirclePainter(radius: 3.5, color: Colors.indigo),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        duration: Duration.zero,
      ),
    );
  }

  static String _cpLabel(double value) {
    if (value == 0) return '0.0';
    final pawns = value / 100;
    return pawns > 0 ? '+${pawns.toStringAsFixed(1)}' : pawns.toStringAsFixed(1);
  }
}
