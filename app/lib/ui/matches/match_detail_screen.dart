import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config.dart';
import '../../data/models.dart';
import '../../data/phone.dart';
import '../api_scope.dart';
import '../labels.dart';

class _Detail {
  const _Detail(this.match, this.roster, this.mySpot, this.myRatings);
  final MatchSummary match;
  final List<RosterEntry> roster;
  final MySpot? mySpot;
  final Map<String, int> myRatings;
}

class MatchDetailScreen extends StatefulWidget {
  const MatchDetailScreen({
    super.key,
    required this.matchId,
    required this.profile,
    this.clock = DateTime.now,
  });

  final String matchId;
  final Profile profile;
  final DateTime Function() clock;

  @override
  State<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends State<MatchDetailScreen> {
  Future<_Detail>? _detail;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _detail ??= _load();
  }

  Future<_Detail> _load() async {
    final api = ApiScope.of(context);
    final results = await Future.wait([
      api.match(widget.matchId),
      api.roster(widget.matchId),
      api.mySpot(widget.matchId),
    ]);
    final match = results[0] as MatchSummary;
    final ratings = match.isRatingOpen(widget.clock())
        ? await api.myRatings(widget.matchId)
        : const <String, int>{};
    return _Detail(match, results[1] as List<RosterEntry>, results[2] as MySpot?, ratings);
  }

  void _reload() => setState(() { _detail = _load(); });

  Future<void> _act(Future<void> Function() action, {String? success}) async {
    final ok = await runAction(context, action);
    if (!mounted) return;
    if (ok && success != null) showMessage(context, success);
    if (ok) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.appTitle)),
      body: FutureBuilder<_Detail>(
        future: _detail,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: TextButton(onPressed: _reload, child: Text(l.retry)));
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: _body(context, snap.data!),
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, _Detail d) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final m = d.match;
    final now = widget.clock();
    final me = widget.profile.id;
    final inMatch = d.mySpot?.joined ?? false;
    final isHost = m.hostId == me;
    final beforeKickoff = m.kickoffAt.isAfter(now);
    final active = m.status == MatchStatus.open || m.status == MatchStatus.pendingPitch;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(m.pitchName, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        Text('${m.area} · ${formatKickoff(context, m.kickoffAt)}'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          Chip(label: Text(formatLabel(l, m.format))),
          Chip(label: Text(l.minutes(m.durationMinutes))),
          Chip(label: Text(m.pricePerPlayerEgp == 0 ? l.noCharge : l.pricePerPlayer(m.pricePerPlayerEgp))),
          if (active)
            Chip(
              avatar: Icon(m.pitchConfirmed ? Icons.verified : Icons.hourglass_top, size: 18),
              label: Text(m.pitchConfirmed ? l.pitchConfirmed : l.pitchPending),
            ),
        ]),
        Row(children: [
          TextButton.icon(
            onPressed: () => launchUrl(
              Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${m.lat},${m.lng}'),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.directions),
            label: Text(l.directions),
          ),
          if (active && beforeKickoff)
            TextButton.icon(
              key: const Key('share'),
              onPressed: () => _shareOnWhatsApp(m),
              icon: const Icon(Icons.share),
              label: Text(l.shareWhatsApp),
            ),
        ]),
        if (m.status == MatchStatus.cancelled) _banner(context, l.statusCancelled, theme.colorScheme.errorContainer),
        if (m.status == MatchStatus.closed)
          _banner(
            context,
            m.scoreA != null ? '${l.statusClosed} · ${m.scoreA} - ${m.scoreB}' : l.statusClosed,
            theme.colorScheme.secondaryContainer,
          ),
        if (d.mySpot != null && (inMatch || d.mySpot!.paymentStatus == PaymentStatus.refundDue))
          _paymentCard(context, m, d.mySpot!),
        const SizedBox(height: 8),
        _rosterSection(context, d),
        const SizedBox(height: 16),
        if (active && beforeKickoff && !inMatch && !m.isFull)
          FilledButton.icon(
            key: const Key('join'),
            onPressed: () => _join(m),
            icon: const Icon(Icons.sports_soccer),
            label: Text(l.join),
          ),
        if (active && beforeKickoff && inMatch && !isHost)
          OutlinedButton.icon(
            key: const Key('leave'),
            onPressed: () => _leave(m),
            icon: const Icon(Icons.logout),
            label: Text(l.leave),
          ),
        if (isHost && active && beforeKickoff) _hostTools(context, m),
        if (inMatch && (m.isReportingOpen(now) || m.isRatingOpen(now))) _afterMatch(context, d, now),
      ],
    );
  }

  Widget _banner(BuildContext context, String text, Color color) => Card(
        color: color,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(text, style: Theme.of(context).textTheme.titleMedium),
        ),
      );

  Widget _paymentCard(BuildContext context, MatchSummary m, MySpot spot) {
    final l = context.l10n;
    String? note;
    if (spot.paymentStatus == PaymentStatus.unpaid) {
      note = !m.pitchConfirmed ? l.payAfterConfirm : (spot.paymentMethod == 'online' ? l.payOnlineSoon : null);
    }
    return Card(
      child: ListTile(
        leading: const Icon(Icons.payments_outlined),
        title: Text(l.yourPayment(paymentLabel(l, spot.paymentStatus))),
        subtitle: note == null ? null : Text(note),
        trailing: spot.amountEgp > 0 ? Text(l.pricePerPlayer(spot.amountEgp)) : null,
      ),
    );
  }

  Widget _rosterSection(BuildContext context, _Detail d) {
    final l = context.l10n;
    final m = d.match;
    final split = d.roster.any((r) => r.team != null);
    if (!split) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.playersSoFar(m.joined, m.capacity), style: Theme.of(context).textTheme.titleMedium),
          if (!m.cameAsTeam)
            Text(l.teamsWaiting, style: Theme.of(context).textTheme.bodySmall),
          for (final r in d.roster) _playerTile(context, r, m),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (team, color) in [(Team.a, m.teamAColor), (Team.b, m.teamBColor)]) ...[
          Row(children: [
            Icon(Icons.checkroom, color: shirtColor(color), shadows: const [Shadow(blurRadius: 2)]),
            const SizedBox(width: 8),
            Text(l.teamColor(colorLabel(l, color)), style: Theme.of(context).textTheme.titleMedium),
          ]),
          for (final r in d.roster.where((r) => r.team == team)) _playerTile(context, r, m),
          const SizedBox(height: 8),
        ],
        for (final r in d.roster.where((r) => r.team == null)) _playerTile(context, r, m),
      ],
    );
  }

  Widget _playerTile(BuildContext context, RosterEntry r, MatchSummary m) {
    final l = context.l10n;
    final s = r.stats;
    final tags = [
      positionLabel(l, r.position),
      if (s != null) levelLabel(l, s.level),
      if (r.isGuest) l.guestTag,
      if (r.playerId == m.hostId) l.hostTag,
    ];
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Text(r.name.isEmpty ? '?' : r.name.characters.first)),
      title: Text(r.name),
      subtitle: Text(tags.join(' · ')),
      trailing: s?.avgRating != null
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.star, size: 16, color: Colors.amber),
              Text(s!.avgRating!.toStringAsFixed(1)),
            ])
          : null,
    );
  }

  // ---------------------------------------------------------------- actions

  Future<void> _shareOnWhatsApp(MatchSummary m) async {
    final l = context.l10n;
    final text = l.shareText(
      formatLabel(l, m.format),
      m.pitchName,
      formatKickoff(context, m.kickoffAt),
      '${KoraConfig.shareBaseUrl}${m.id}',
    );
    await launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'),
        mode: LaunchMode.externalApplication);
  }

  Future<void> _join(MatchSummary m) async {
    final l = context.l10n;
    var position = widget.profile.favoritePosition;
    var method = PaymentMethod.online;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.choosePosition, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (final p in Position.values)
                  ChoiceChip(
                    label: Text(positionLabel(l, p)),
                    selected: position == p,
                    onSelected: (_) => setSheet(() => position = p),
                  ),
              ]),
              if (m.allowCash && m.costSplit == CostSplit.equal) ...[
                const SizedBox(height: 16),
                Text(l.howToPay, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<PaymentMethod>(
                  segments: [
                    ButtonSegment(value: PaymentMethod.online, label: Text(l.payOnline)),
                    ButtonSegment(value: PaymentMethod.cash, label: Text(l.payCash)),
                  ],
                  selected: {method},
                  onSelectionChanged: (s) => setSheet(() => method = s.first),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('confirm-join'),
                onPressed: () => Navigator.pop(context, true),
                child: Text(l.join),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true) {
      await _act(() => ApiScope.of(context).joinMatch(m.id, position, method));
    }
  }

  Future<void> _leave(MatchSummary m) async {
    final l = context.l10n;
    final api = ApiScope.of(context);
    final ok = await runAction(context, () async {
      final warning = await api.leaveWarning(m.id);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(warning.free ? l.leaveFreeTitle : l.leaveLateTitle),
          content: Text(warning.free ? l.leaveFreeBody : l.leaveLateBody),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.back)),
            FilledButton(
              key: const Key('confirm-leave'),
              style: warning.free
                  ? null
                  : FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.confirmLeave),
            ),
          ],
        ),
      );
      if (confirmed == true) await api.leaveMatch(m.id);
    });
    if (ok && mounted) _reload();
  }

  Widget _hostTools(BuildContext context, MatchSummary m) {
    final l = context.l10n;
    final api = ApiScope.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(l.hostTools, style: Theme.of(context).textTheme.titleMedium),
            ),
            if (m.status == MatchStatus.pendingPitch)
              ListTile(
                key: const Key('confirm-pitch'),
                leading: const Icon(Icons.verified),
                title: Text(l.confirmPitchAction),
                onTap: () => _act(() => api.confirmPitch(m.id)),
              ),
            if (!m.isFull) ...[
              ListTile(
                leading: const Icon(Icons.person_add),
                title: Text(l.addByPhone),
                onTap: () => _addPlayer(m, byPhone: true),
              ),
              ListTile(
                leading: const Icon(Icons.person_add_alt),
                title: Text(l.addGuest),
                onTap: () => _addPlayer(m, byPhone: false),
              ),
            ],
            if (!m.cameAsTeam)
              ListTile(
                leading: const Icon(Icons.shuffle),
                title: Text(l.splitTeamsAction),
                onTap: () => _act(() => api.splitTeams(m.id)),
              ),
            ListTile(
              leading: Icon(Icons.cancel, color: Theme.of(context).colorScheme.error),
              title: Text(l.cancelMatchAction),
              onTap: () async {
                final yes = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    content: Text(l.cancelMatchConfirm),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.back)),
                      FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(l.cancelMatchAction)),
                    ],
                  ),
                );
                if (yes == true) await _act(() => api.cancelMatch(m.id));
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addPlayer(MatchSummary m, {required bool byPhone}) async {
    final l = context.l10n;
    final controller = TextEditingController();
    var position = Position.midfielder;
    String? error;
    final api = ApiScope.of(context);
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(byPhone ? l.addByPhone : l.addGuest),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: controller,
              keyboardType: byPhone ? TextInputType.phone : TextInputType.name,
              textDirection: byPhone ? TextDirection.ltr : null,
              decoration: InputDecoration(
                labelText: byPhone ? l.phoneLabel : l.guestName,
                errorText: error,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButton<Position>(
              value: position,
              isExpanded: true,
              items: [
                for (final p in Position.values)
                  DropdownMenuItem(value: p, child: Text(positionLabel(l, p))),
              ],
              onChanged: (p) => setDialog(() => position = p!),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(l.back)),
            FilledButton(
              onPressed: () async {
                if (byPhone) {
                  final phone = normalizeEgyptianMobile(controller.text);
                  if (phone == null) {
                    setDialog(() => error = l.invalidPhone);
                    return;
                  }
                  final ok = await runAction(context, () => api.hostAddPlayer(m.id, phone, position));
                  if (ok && context.mounted) Navigator.pop(context);
                } else {
                  final ok = await runAction(context, () => api.hostAddGuest(m.id, controller.text.trim(), position));
                  if (ok && context.mounted) Navigator.pop(context);
                }
              },
              child: Text(l.add),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (mounted) _reload();
  }

  Widget _afterMatch(BuildContext context, _Detail d, DateTime now) {
    final l = context.l10n;
    final m = d.match;
    final api = ApiScope.of(context);
    final others = d.roster.where((r) => !r.isGuest && r.playerId != widget.profile.id).toList();
    final ratingOpen = m.isRatingOpen(now);
    final reportingOpen = m.isReportingOpen(now);

    return Card(
      key: const Key('after-match'),
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.afterMatch, style: Theme.of(context).textTheme.titleMedium),
            Text(l.rateHint, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            for (final r in others)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name, style: Theme.of(context).textTheme.titleSmall),
                    Row(children: [
                      if (ratingOpen)
                        for (var star = 1; star <= 5; star++)
                          IconButton(
                            key: Key('rate-${r.playerId}-$star'),
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              star <= (d.myRatings[r.playerId] ?? 0) ? Icons.star : Icons.star_border,
                              color: Colors.amber,
                            ),
                            onPressed: () => _act(() => api.ratePlayer(m.id, r.playerId!, star)),
                          ),
                      const Spacer(),
                      if (reportingOpen) ...[
                        TextButton(
                          onPressed: () => _act(() => api.reportAttendance(m.id, r.playerId!, ReportKind.late),
                              success: l.reportSaved),
                          child: Text(l.reportLate),
                        ),
                        TextButton(
                          onPressed: () => _act(() => api.reportAttendance(m.id, r.playerId!, ReportKind.noShow),
                              success: l.reportSaved),
                          child: Text(l.reportNoShow),
                        ),
                      ],
                    ]),
                  ],
                ),
              ),
            const Divider(),
            if (ratingOpen && d.mySpot?.team != null)
              TextButton.icon(
                onPressed: () => _reportScore(m),
                icon: const Icon(Icons.scoreboard),
                label: Text(l.reportScoreAction),
              ),
            TextButton.icon(
              onPressed: () => _dispute(m),
              icon: const Icon(Icons.gavel),
              label: Text(l.disputeAction),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reportScore(MatchSummary m) async {
    final l = context.l10n;
    final a = TextEditingController();
    final b = TextEditingController();
    final api = ApiScope.of(context);
    final send = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.scoreTitle),
        content: Row(children: [
          Expanded(
            child: TextField(
              controller: a,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l.teamColor(colorLabel(l, m.teamAColor))),
            ),
          ),
          const Padding(padding: EdgeInsets.all(8), child: Text('-')),
          Expanded(
            child: TextField(
              controller: b,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l.teamColor(colorLabel(l, m.teamBColor))),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.back)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(l.send)),
        ],
      ),
    );
    final sa = int.tryParse(a.text);
    final sb = int.tryParse(b.text);
    a.dispose();
    b.dispose();
    if (send != true || sa == null || sb == null || !mounted) return;
    var confirmed = false;
    final ok = await runAction(context, () async => confirmed = await api.reportScore(m.id, sa, sb));
    if (ok && mounted) {
      showMessage(context, confirmed ? l.scoreConfirmed : l.scoreWaiting);
      _reload();
    }
  }

  Future<void> _dispute(MatchSummary m) async {
    final l = context.l10n;
    final reason = TextEditingController();
    final api = ApiScope.of(context);
    final send = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.disputeAction),
        content: TextField(
          controller: reason,
          maxLines: 3,
          decoration: InputDecoration(labelText: l.disputeReason),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.back)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(l.send)),
        ],
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (send == true && mounted) {
      await _act(() => api.disputeAttendance(m.id, text), success: l.disputeSent);
    }
  }
}
