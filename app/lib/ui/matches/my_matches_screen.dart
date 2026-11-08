import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../api_scope.dart';
import '../labels.dart';
import 'match_card.dart';
import 'match_detail_screen.dart';

class MyMatchesScreen extends StatefulWidget {
  const MyMatchesScreen({super.key, required this.profile});

  final Profile profile;

  @override
  State<MyMatchesScreen> createState() => _MyMatchesScreenState();
}

class _MyMatchesScreenState extends State<MyMatchesScreen> {
  Future<List<MatchSummary>>? _matches;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _matches ??= ApiScope.of(context).myMatches();
  }

  void _reload() => setState(() { _matches = ApiScope.of(context).myMatches(); });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.tabMyMatches)),
      body: RefreshIndicator(
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
                Center(child: TextButton(onPressed: _reload, child: Text(l.retry))),
              ]);
            }
            final matches = snap.data!;
            if (matches.isEmpty) {
              return ListView(children: [
                const SizedBox(height: 80),
                Center(child: Text(l.noMyMatches)),
              ]);
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: matches.length,
              itemBuilder: (_, i) => MatchCard(
                match: matches[i],
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => MatchDetailScreen(matchId: matches[i].id, profile: widget.profile),
                  ));
                  _reload();
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
