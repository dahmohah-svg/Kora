import 'package:flutter/material.dart';

import '../../config.dart';
import '../../data/models.dart';
import '../api_scope.dart';
import '../labels.dart';

/// Estimated price per player before the match exists. The server computes
/// the real price the same way (see create_match).
int estimatePricePerPlayer({
  required int pricePerHourEgp,
  required int durationMinutes,
  required MatchFormat format,
  required CostSplit costSplit,
}) {
  if (costSplit == CostSplit.hostPays) return 0;
  final total = (pricePerHourEgp * durationMinutes / 60).ceil();
  return (total / capacityOf(format)).ceil() + KoraConfig.serviceFeeEgp;
}

/// Pops with the new match id.
class CreateMatchScreen extends StatefulWidget {
  const CreateMatchScreen({super.key});

  @override
  State<CreateMatchScreen> createState() => _CreateMatchScreenState();
}

class _CreateMatchScreenState extends State<CreateMatchScreen> {
  Future<List<Pitch>>? _pitches;
  Pitch? _pitch;
  late DateTime _day;
  TimeOfDay _time = const TimeOfDay(hour: 21, minute: 0);
  int _duration = 60;
  MatchFormat _format = MatchFormat.fiveASide;
  CostSplit _split = CostSplit.equal;
  bool _allowCash = false;
  bool _cameAsTeam = false;
  Position _position = Position.midfielder;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _day = DateTime(now.year, now.month, now.day);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pitches ??= ApiScope.of(context).pitches();
  }

  DateTime get _kickoff => DateTime(_day.year, _day.month, _day.day, _time.hour, _time.minute);

  Future<void> _create() async {
    if (_pitch == null) return;
    setState(() => _busy = true);
    String? id;
    await runAction(context, () async {
      id = await ApiScope.of(context).createMatch(
        pitchId: _pitch!.id,
        kickoffAt: _kickoff,
        durationMinutes: _duration,
        format: _format,
        costSplit: _split,
        allowCash: _allowCash,
        cameAsTeam: _cameAsTeam,
        hostPosition: _position,
      );
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (id != null) Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.createMatchTitle)),
      body: FutureBuilder<List<Pitch>>(
        future: _pitches,
        builder: (context, snap) {
          if (!snap.hasData) {
            return snap.hasError
                ? Center(child: Text(errorMessage(l, snap.error!)))
                : const Center(child: CircularProgressIndicator());
          }
          final pitches = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<Pitch>(
                key: const Key('pitch'),
                initialValue: _pitch,
                isExpanded: true,
                decoration: InputDecoration(labelText: l.pitchLabel, border: const OutlineInputBorder()),
                hint: Text(l.choosePitch),
                items: [
                  for (final p in pitches)
                    DropdownMenuItem(
                      value: p,
                      child: Text('${p.name} · ${p.area} · ${l.pitchPrice(p.pricePerHourEgp)}',
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (p) => setState(() => _pitch = p),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_month),
                title: Text(l.dateLabel),
                subtitle: Text(formatDay(context, _day)),
                onTap: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _day,
                    firstDate: DateTime(now.year, now.month, now.day),
                    lastDate: now.add(const Duration(days: 30)),
                  );
                  if (d != null) setState(() => _day = d);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: Text(l.timeLabel),
                subtitle: Text(_time.format(context)),
                onTap: () async {
                  final t = await showTimePicker(context: context, initialTime: _time);
                  if (t != null) setState(() => _time = t);
                },
              ),
              Text(l.durationLabel, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              SegmentedButton<int>(
                segments: [
                  for (final m in const [60, 90, 120])
                    ButtonSegment(value: m, label: Text(l.minutes(m))),
                ],
                selected: {_duration},
                onSelectionChanged: (s) => setState(() => _duration = s.first),
              ),
              const SizedBox(height: 16),
              Text(l.formatLabel, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              SegmentedButton<MatchFormat>(
                segments: [
                  for (final f in MatchFormat.values) ButtonSegment(value: f, label: Text(formatLabel(l, f))),
                ],
                selected: {_format},
                onSelectionChanged: (s) => setState(() => _format = s.first),
              ),
              const SizedBox(height: 16),
              Text(l.costSplitLabel, style: Theme.of(context).textTheme.titleSmall),
              RadioGroup<CostSplit>(
                groupValue: _split,
                onChanged: (v) => setState(() => _split = v!),
                child: Column(children: [
                  RadioListTile(value: CostSplit.equal, title: Text(l.splitEqual)),
                  RadioListTile(value: CostSplit.hostPays, title: Text(l.splitHost)),
                ]),
              ),
              if (_split == CostSplit.equal)
                SwitchListTile(
                  value: _allowCash,
                  title: Text(l.allowCashLabel),
                  onChanged: (v) => setState(() => _allowCash = v),
                ),
              SwitchListTile(
                value: _cameAsTeam,
                title: Text(l.cameAsTeamLabel),
                subtitle: Text(l.cameAsTeamHelp),
                onChanged: (v) => setState(() => _cameAsTeam = v),
              ),
              const SizedBox(height: 8),
              Text(l.yourPosition, style: Theme.of(context).textTheme.titleSmall),
              Wrap(spacing: 8, children: [
                for (final p in Position.values)
                  ChoiceChip(
                    label: Text(positionLabel(l, p)),
                    selected: _position == p,
                    onSelected: (_) => setState(() => _position = p),
                  ),
              ]),
              const SizedBox(height: 16),
              if (_pitch != null)
                Text(
                  _split == CostSplit.hostPays
                      ? l.noCharge
                      : l.estimatedPrice(estimatePricePerPlayer(
                          pricePerHourEgp: _pitch!.pricePerHourEgp,
                          durationMinutes: _duration,
                          format: _format,
                          costSplit: _split,
                        )),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('create'),
                onPressed: _busy || _pitch == null ? null : _create,
                child: Text(l.createAction),
              ),
            ],
          );
        },
      ),
    );
  }
}
