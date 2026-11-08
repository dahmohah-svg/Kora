import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../api_scope.dart';
import '../labels.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.profile, required this.onChanged});

  final Profile profile;
  final VoidCallback onChanged;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<PlayerStats>? _stats;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stats ??= ApiScope.of(context).playerStats(widget.profile.id);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final locale = LocaleScope.of(context);
    final p = widget.profile;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.tabProfile),
        actions: [
          TextButton(
            onPressed: () => locale.value = Locale(locale.value.languageCode == 'ar' ? 'en' : 'ar'),
            child: Text(l.language),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() { _stats = ApiScope.of(context).playerStats(p.id); });
          widget.onChanged();
          await _stats;
        },
        child: FutureBuilder<PlayerStats>(
          future: _stats,
          builder: (context, snap) {
            final s = snap.data;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 40,
                    child: Text(p.displayName.characters.first, style: theme.textTheme.headlineMedium),
                  ),
                ),
                const SizedBox(height: 8),
                Text(p.displayName, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                Text(
                  [p.favoritePosition, ...p.otherPositions].map((x) => positionLabel(l, x)).join(' · '),
                  textAlign: TextAlign.center,
                ),
                if (p.isPausedAt(DateTime.now()))
                  Card(
                    color: theme.colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(l.pausedUntil(formatKickoff(context, p.pausedUntil!))),
                    ),
                  ),
                const SizedBox(height: 16),
                if (snap.hasError)
                  Center(
                    child: TextButton(
                      onPressed: () => setState(() {
                        _stats = ApiScope.of(context).playerStats(p.id);
                      }),
                      child: Text(l.retry),
                    ),
                  )
                else if (s == null)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.military_tech, size: 36),
                      title: Text(levelLabel(l, s.level), style: theme.textTheme.titleLarge),
                      subtitle: Text([
                        l.points(s.points),
                        if (pointsToNextLevel(s.points) != null) l.nextLevel(pointsToNextLevel(s.points)!),
                      ].join(' · ')),
                    ),
                  ),
                  Row(children: [
                    _stat(context, l.gamesPlayed, '${s.gamesPlayed}'),
                    _stat(context, l.onTimeRate,
                        s.onTimeRate == null ? '-' : '${(s.onTimeRate! * 100).round()}%'),
                    _stat(context, l.avgRating,
                        s.avgRating == null ? l.ratingHidden : '★ ${s.avgRating!.toStringAsFixed(1)}'),
                  ]),
                ],
                const SizedBox(height: 32),
                OutlinedButton.icon(
                  onPressed: () => ApiScope.of(context).signOut(),
                  icon: const Icon(Icons.logout),
                  label: Text(l.signOut),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Column(children: [
              Text(value,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ),
      );
}
