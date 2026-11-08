import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../api_scope.dart';
import '../labels.dart';
import 'create_match_screen.dart';
import 'match_card.dart';
import 'match_detail_screen.dart';

/// Browse upcoming matches by area, day and format.
class MatchListScreen extends StatefulWidget {
  const MatchListScreen({super.key, required this.profile});

  final Profile profile;

  @override
  State<MatchListScreen> createState() => _MatchListScreenState();
}

class _MatchListScreenState extends State<MatchListScreen> {
  MatchFilter _filter = const MatchFilter();
  Future<List<MatchSummary>>? _matches;
  List<String> _areas = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_matches == null) {
      _reload();
      ApiScope.of(context).areas().then((a) {
        if (mounted) setState(() => _areas = a);
      }, onError: (_) {});
    }
  }

  void _reload() => setState(() { _matches = ApiScope.of(context).upcomingMatches(_filter); });

  void _setFilter(MatchFilter f) {
    _filter = f;
    _reload();
  }

  Future<void> _open(MatchSummary m) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MatchDetailScreen(matchId: m.id, profile: widget.profile),
    ));
    _reload();
  }

  Future<void> _create() async {
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => const CreateMatchScreen(),
    ));
    if (id != null && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MatchDetailScreen(matchId: id, profile: widget.profile),
      ));
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));
    bool sameDay(DateTime? a, DateTime b) =>
        a != null && a.year == b.year && a.month == b.month && a.day == b.day;

    return Scaffold(
      appBar: AppBar(title: Text(l.appTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: Text(l.createMatch),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                DropdownButton<String?>(
                  value: _filter.area,
                  hint: Text(l.allAreas),
                  underline: const SizedBox(),
                  items: [
                    DropdownMenuItem(value: null, child: Text(l.allAreas)),
                    for (final a in _areas) DropdownMenuItem(value: a, child: Text(a)),
                  ],
                  onChanged: (a) => _setFilter(_filter.copyWith(area: () => a)),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(l.anyDay),
                  selected: _filter.day == null,
                  onSelected: (_) => _setFilter(_filter.copyWith(day: () => null)),
                ),
                const SizedBox(width: 4),
                ChoiceChip(
                  label: Text(l.today),
                  selected: sameDay(_filter.day, today),
                  onSelected: (_) => _setFilter(_filter.copyWith(day: () => today)),
                ),
                const SizedBox(width: 4),
                ChoiceChip(
                  label: Text(l.tomorrow),
                  selected: sameDay(_filter.day, tomorrow),
                  onSelected: (_) => _setFilter(_filter.copyWith(day: () => tomorrow)),
                ),
                const SizedBox(width: 8),
                for (final f in MatchFormat.values) ...[
                  FilterChip(
                    label: Text(formatLabel(l, f)),
                    selected: _filter.format == f,
                    onSelected: (on) => _setFilter(_filter.copyWith(format: () => on ? f : null)),
                  ),
                  const SizedBox(width: 4),
                ],
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                _reload();
                await _matches;
              },
              child: FutureBuilder<List<MatchSummary>>(
                future: _matches,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return ListView(children: [
                      const SizedBox(height: 80),
                      Center(child: Text(errorMessage(l, snap.error!))),
                      Center(child: TextButton(onPressed: _reload, child: Text(l.retry))),
                    ]);
                  }
                  final matches = snap.data!;
                  if (matches.isEmpty) {
                    return ListView(children: [
                      const SizedBox(height: 80),
                      Center(child: Text(l.noMatches, textAlign: TextAlign.center)),
                    ]);
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                    itemCount: matches.length,
                    itemBuilder: (_, i) => MatchCard(match: matches[i], onTap: () => _open(matches[i])),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
