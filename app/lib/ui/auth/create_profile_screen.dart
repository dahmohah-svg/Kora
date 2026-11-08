import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../api_scope.dart';
import '../labels.dart';

class CreateProfileScreen extends StatefulWidget {
  const CreateProfileScreen({super.key, required this.onCreated});

  final VoidCallback onCreated;

  @override
  State<CreateProfileScreen> createState() => _CreateProfileScreenState();
}

class _CreateProfileScreenState extends State<CreateProfileScreen> {
  final _name = TextEditingController();
  Position _favorite = Position.midfielder;
  final Set<Position> _others = {};
  DateTime? _birthDate;
  String? _nameError;
  String? _dateError;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 20),
      firstDate: DateTime(now.year - 80),
      lastDate: now,
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _save() async {
    final l = context.l10n;
    setState(() {
      _nameError = _name.text.trim().length < 2 ? l.nameTooShort : null;
      _dateError = _birthDate == null ? l.birthDateRequired : null;
    });
    if (_nameError != null || _dateError != null) return;
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => ApiScope.of(context).createProfile(
        displayName: _name.text.trim(),
        favoritePosition: _favorite,
        otherPositions: _others.where((p) => p != _favorite).toList(),
        birthDate: _birthDate!,
        language: context.localeName,
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) widget.onCreated();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.createProfileTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('name'),
            controller: _name,
            maxLength: 40,
            decoration: InputDecoration(
              labelText: l.nameLabel,
              errorText: _nameError,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(l.favoritePosition, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<Position>(
            segments: [
              for (final p in Position.values)
                ButtonSegment(value: p, label: Text(positionLabel(l, p))),
            ],
            selected: {_favorite},
            onSelectionChanged: (s) => setState(() => _favorite = s.first),
          ),
          const SizedBox(height: 16),
          Text(l.otherPositions, style: Theme.of(context).textTheme.titleMedium),
          Wrap(
            spacing: 8,
            children: [
              for (final p in Position.values.where((p) => p != _favorite))
                FilterChip(
                  label: Text(positionLabel(l, p)),
                  selected: _others.contains(p),
                  onSelected: (on) => setState(() => on ? _others.add(p) : _others.remove(p)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.birthDate),
            subtitle: Text(
              _birthDate == null ? (_dateError ?? l.chooseDate) : formatDay(context, _birthDate!),
              style: _dateError != null && _birthDate == null
                  ? TextStyle(color: Theme.of(context).colorScheme.error)
                  : null,
            ),
            trailing: const Icon(Icons.calendar_month),
            onTap: _pickDate,
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _busy ? null : _save, child: Text(l.save)),
        ],
      ),
    );
  }
}
