import 'package:supabase_flutter/supabase_flutter.dart';

import 'kora_api.dart';
import 'models.dart';

class SupabaseKoraApi implements KoraApi {
  SupabaseKoraApi(this._db);

  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      throw KoraException.fromMessage(e.message);
    } on AuthException catch (e) {
      throw KoraException('auth:${e.message}');
    }
  }

  Future<dynamic> _rpc(String fn, [Map<String, dynamic>? params]) =>
      _guard(() => _db.rpc(fn, params: params));

  String _date(DateTime d) => d.toUtc().toIso8601String();

  @override
  String? get currentUserId => _db.auth.currentUser?.id;

  @override
  Stream<String?> get authChanges =>
      _db.auth.onAuthStateChange.map((s) => s.session?.user.id);

  @override
  Future<void> sendOtp(String phone) => _guard(() => _db.auth.signInWithOtp(phone: phone));

  @override
  Future<void> verifyOtp(String phone, String code) =>
      _guard(() => _db.auth.verifyOTP(type: OtpType.sms, phone: phone, token: code));

  @override
  Future<void> signOut() => _db.auth.signOut();

  @override
  Future<Profile?> myProfile() => _guard(() async {
        final id = currentUserId;
        if (id == null) return null;
        final row = await _db.from('profiles').select().eq('id', id).maybeSingle();
        return row == null ? null : Profile.fromJson(row);
      });

  @override
  Future<void> createProfile({
    required String displayName,
    required Position favoritePosition,
    required List<Position> otherPositions,
    required DateTime birthDate,
    required String language,
  }) =>
      _rpc('create_profile', {
        'p_display_name': displayName,
        'p_favorite_position': positionToDb(favoritePosition),
        'p_other_positions': otherPositions.map(positionToDb).toList(),
        'p_birth_date': birthDate.toIso8601String().substring(0, 10),
        'p_language': language,
      });

  @override
  Future<List<Pitch>> pitches() => _guard(() async {
        final rows = await _db
            .from('pitches')
            .select('id, name, area, address, lat, lng, price_per_hour_egp, photo_urls')
            .eq('is_active', true)
            .order('name');
        return rows.map(Pitch.fromJson).toList();
      });

  @override
  Future<List<String>> areas() async =>
      (await pitches()).map((p) => p.area).toSet().toList()..sort();

  @override
  Future<List<MatchSummary>> upcomingMatches(MatchFilter filter) => _guard(() async {
        var q = _db
            .from('match_list')
            .select()
            .inFilter('status', ['open', 'pending_pitch']);
        if (filter.day != null) {
          final start = DateTime(filter.day!.year, filter.day!.month, filter.day!.day);
          q = q
              .gte('kickoff_at', _date(start))
              .lt('kickoff_at', _date(start.add(const Duration(days: 1))));
        } else {
          q = q.gte('kickoff_at', _date(DateTime.now()));
        }
        if (filter.area != null) q = q.eq('area', filter.area!);
        if (filter.format != null) q = q.eq('format', formatToDb(filter.format!));
        if (filter.maxPriceEgp != null) q = q.lte('price_per_player_egp', filter.maxPriceEgp!);
        final rows = await q.order('kickoff_at');
        return rows.map(MatchSummary.fromJson).toList();
      });

  @override
  Future<List<MatchSummary>> myMatches() => _guard(() async {
        final spots = await _db.from('my_spots').select('match_id').eq('status', 'joined');
        final ids = spots.map((r) => r['match_id'] as String).toList();
        if (ids.isEmpty) return [];
        final rows = await _db
            .from('match_list')
            .select()
            .inFilter('id', ids)
            .order('kickoff_at', ascending: false);
        return rows.map(MatchSummary.fromJson).toList();
      });

  @override
  Future<MatchSummary> match(String matchId) => _guard(() async =>
      MatchSummary.fromJson(await _db.from('match_list').select().eq('id', matchId).single()));

  @override
  Future<List<RosterEntry>> roster(String matchId) => _guard(() async {
        final spots = await _db
            .from('match_players')
            .select('id, player_id, guest_name, position, team')
            .eq('match_id', matchId)
            .eq('status', 'joined')
            .order('joined_at');
        final ids = spots.map((s) => s['player_id']).whereType<String>().toList();
        final stats = ids.isEmpty
            ? <String, PlayerStats>{}
            : {
                for (final r in await _db.from('player_stats').select().inFilter('player_id', ids))
                  r['player_id'] as String: PlayerStats.fromJson(r),
              };
        return [
          for (final s in spots)
            RosterEntry(
              spotId: s['id'] as String,
              playerId: s['player_id'] as String?,
              guestName: s['guest_name'] as String?,
              position: positionFromDb(s['position'] as String),
              team: switch (s['team']) { 'A' => Team.a, 'B' => Team.b, _ => null },
              stats: stats[s['player_id']],
            ),
        ];
      });

  @override
  Future<MySpot?> mySpot(String matchId) => _guard(() async {
        final row = await _db.from('my_spots').select().eq('match_id', matchId).maybeSingle();
        return row == null ? null : MySpot.fromJson(row);
      });

  @override
  Future<PlayerStats> playerStats(String playerId) => _guard(() async =>
      PlayerStats.fromJson(await _db.from('player_stats').select().eq('player_id', playerId).single()));

  @override
  Future<String> createMatch({
    required String pitchId,
    required DateTime kickoffAt,
    required int durationMinutes,
    required MatchFormat format,
    required CostSplit costSplit,
    required bool allowCash,
    required bool cameAsTeam,
    required Position hostPosition,
  }) async {
    final row = await _rpc('create_match', {
      'p_pitch_id': pitchId,
      'p_kickoff_at': _date(kickoffAt),
      'p_duration_minutes': durationMinutes,
      'p_format': formatToDb(format),
      'p_cost_split': costSplitToDb(costSplit),
      'p_allow_cash': allowCash,
      'p_came_as_team': cameAsTeam,
      'p_host_position': positionToDb(hostPosition),
    });
    return (row as Map<String, dynamic>)['id'] as String;
  }

  @override
  Future<void> confirmPitch(String matchId) => _rpc('confirm_pitch', {'p_match': matchId});

  @override
  Future<void> joinMatch(String matchId, Position position, PaymentMethod method) =>
      _rpc('join_match', {
        'p_match': matchId,
        'p_position': positionToDb(position),
        'p_payment_method': method.name,
      });

  @override
  Future<LeaveWarning> leaveWarning(String matchId) async =>
      LeaveWarning.fromJson(await _rpc('leave_warning', {'p_match': matchId}) as Map<String, dynamic>);

  @override
  Future<void> leaveMatch(String matchId) => _rpc('leave_match', {'p_match': matchId});

  @override
  Future<void> cancelMatch(String matchId) =>
      _rpc('cancel_match', {'p_match': matchId, 'p_reason': 'host_cancelled'});

  @override
  Future<void> splitTeams(String matchId) => _rpc('split_teams', {'p_match': matchId});

  @override
  Future<void> hostAddPlayer(String matchId, String phone, Position position) => _rpc(
      'host_add_player', {'p_match': matchId, 'p_phone': phone, 'p_position': positionToDb(position)});

  @override
  Future<void> hostAddGuest(String matchId, String name, Position position) => _rpc(
      'host_add_guest', {'p_match': matchId, 'p_guest_name': name, 'p_position': positionToDb(position)});

  @override
  Future<Map<String, int>> myRatings(String matchId) => _guard(() async {
        final rows = await _db
            .from('ratings')
            .select('rated_id, stars')
            .eq('match_id', matchId)
            .eq('rater_id', currentUserId ?? '');
        return {for (final r in rows) r['rated_id'] as String: r['stars'] as int};
      });

  @override
  Future<void> ratePlayer(String matchId, String playerId, int stars) =>
      _rpc('rate_player', {'p_match': matchId, 'p_rated': playerId, 'p_stars': stars});

  @override
  Future<void> reportAttendance(String matchId, String playerId, ReportKind kind) =>
      _rpc('report_attendance', {'p_match': matchId, 'p_reported': playerId, 'p_kind': reportKindToDb(kind)});

  @override
  Future<void> disputeAttendance(String matchId, String reason) =>
      _rpc('dispute_attendance', {'p_match': matchId, 'p_reason': reason});

  @override
  Future<bool> reportScore(String matchId, int scoreA, int scoreB) async {
    final res = await _rpc('report_score', {'p_match': matchId, 'p_score_a': scoreA, 'p_score_b': scoreB});
    return (res as Map<String, dynamic>)['confirmed'] as bool;
  }
}
