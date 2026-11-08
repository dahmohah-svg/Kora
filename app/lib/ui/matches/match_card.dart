import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../labels.dart';

class MatchCard extends StatelessWidget {
  const MatchCard({super.key, required this.match, required this.onTap});

  final MatchSummary match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final status = switch (match.status) {
      MatchStatus.cancelled => l.statusCancelled,
      MatchStatus.closed => l.statusClosed,
      _ => l.spotsLeft(match.spotsLeft),
    };
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(match.pitchName,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  Chip(
                    label: Text(formatLabel(l, match.format)),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              Text('${match.area} · ${formatKickoff(context, match.kickoffAt)}'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.group, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(status),
                  const Spacer(),
                  Text(
                    match.pricePerPlayerEgp == 0
                        ? l.noCharge
                        : l.pricePerPlayer(match.pricePerPlayerEgp),
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
              if (!match.pitchConfirmed && match.status == MatchStatus.pendingPitch)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(l.pitchPending,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.tertiary)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
