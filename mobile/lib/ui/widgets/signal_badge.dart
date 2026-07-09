import 'package:flutter/material.dart';

import '../../config/theme.dart';

/// Lencana arah sinyal (BUY/SELL/NEUTRAL) dengan warna sesuai.
class SignalBadge extends StatelessWidget {
  const SignalBadge({super.key, required this.direction, this.compact = false});

  final String direction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forDirection(direction);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 3 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        direction,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: compact ? 11 : 13,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Bar keyakinan 0..100 dengan gradasi warna arah.
class ConfidenceBar extends StatelessWidget {
  const ConfidenceBar({
    super.key,
    required this.confidence,
    required this.direction,
    this.showLabel = true,
  });

  final double confidence;
  final String direction;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forDirection(direction);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLabel)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Keyakinan ${confidence.toStringAsFixed(0)}%',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (confidence / 100).clamp(0, 1),
            minHeight: 8,
            backgroundColor: AppColors.surfaceAlt,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
