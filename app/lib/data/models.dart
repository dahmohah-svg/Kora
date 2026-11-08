// Data shapes returned by the Kora backend (see supabase/migrations).

enum Position { goalkeeper, defender, midfielder, forward }

enum MatchFormat { fiveASide, sixASide }

enum CostSplit { equal, hostPays }

enum PaymentMethod { online, cash }

enum ReportKind { late, noShow }

Position positionFromDb(String v) => Position.values.byName(v);

String positionToDb(Position p) => p.name;

MatchFormat formatFromDb(String v) =>
    v == '5v5' ? MatchFormat.fiveASide : MatchFormat.sixASide;

String formatToDb(MatchFormat f) => f == MatchFormat.fiveASide ? '5v5' : '6v6';

String costSplitToDb(CostSplit c) => c == CostSplit.equal ? 'equal' : 'host_pays';

String reportKindToDb(ReportKind k) => k == ReportKind.late ? 'late' : 'no_show';

int capacityOf(MatchFormat f) => f == MatchFormat.fiveASide ? 10 : 12;

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

double? _num(Object? v) => v == null ? null : (v as num).toDouble();

class Profile {
  const Profile({
    required this.id,
    required this.displayName,
    required this.favoritePosition,
    required this.otherPositions,
    required this.points,
    required this.language,
    this.photoUrl,
    this.pausedUntil,
    this.isAdmin = false,
  });

  final String id;
  final String displayName;
  final String? photoUrl;
  final Position favoritePosition;
  final List<Position> otherPositions;
  final int points;
  final String language;
  final DateTime? pausedUntil;
  final bool isAdmin;

  bool isPausedAt(DateTime now) => pausedUntil != null && pausedUntil!.isAfter(now);

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        displayName: j['display_name'] as String,
        photoUrl: j['photo_url'] as String?,
        favoritePosition: positionFromDb(j['favorite_position'] as String),
        otherPositions: ((j['other_positions'] as List?) ?? const [])
            .map((e) => positionFromDb(e as String))
            .toList(),
        points: j['points'] as int,
        language: j['language'] as String? ?? 'ar',
        pausedUntil: _date(j['paused_until']),
        isAdmin: j['is_admin'] as bool? ?? false,
      );
}

/// Public profile numbers (the player_stats view).
class PlayerStats {
  const PlayerStats({
    required this.playerId,
    required this.displayName,
    required this.favoritePosition,
    required this.otherPositions,
    required this.points,
    required this.level,
    required this.gamesPlayed,
    required this.ratedMatches,
    this.photoUrl,
    this.onTimeRate,
    this.avgRating,
    this.ratingCount,
  });

  final String playerId;
  final String displayName;
  final String? photoUrl;
  final Position favoritePosition;
  final List<Position> otherPositions;
  final int points;
  final String level; // rookie, regular, starter, captain, legend
  final int gamesPlayed;
  final double? onTimeRate; // 0..1, null before the first match
  final int ratedMatches;
  final double? avgRating; // null until 3 rated matches
  final int? ratingCount;

  factory PlayerStats.fromJson(Map<String, dynamic> j) => PlayerStats(
        playerId: j['player_id'] as String,
        displayName: j['display_name'] as String,
        photoUrl: j['photo_url'] as String?,
        favoritePosition: positionFromDb(j['favorite_position'] as String),
        otherPositions: ((j['other_positions'] as List?) ?? const [])
            .map((e) => positionFromDb(e as String))
            .toList(),
        points: j['points'] as int,
        level: j['level'] as String,
        gamesPlayed: j['games_played'] as int,
        onTimeRate: _num(j['on_time_rate']),
        ratedMatches: j['rated_matches'] as int,
        avgRating: _num(j['avg_rating']),
        ratingCount: j['rating_count'] as int?,
      );
}

class Pitch {
  const Pitch({
    required this.id,
    required this.name,
    required this.area,
    required this.address,
    required this.lat,
    required this.lng,
    required this.pricePerHourEgp,
    this.photoUrls = const [],
  });

  final String id;
  final String name;
  final String area;
  final String address;
  final double lat;
  final double lng;
  final int pricePerHourEgp;
  final List<String> photoUrls;

  factory Pitch.fromJson(Map<String, dynamic> j) => Pitch(
        id: j['id'] as String,
        name: j['name'] as String,
        area: j['area'] as String,
        address: j['address'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        pricePerHourEgp: j['price_per_hour_egp'] as int,
        photoUrls: ((j['photo_urls'] as List?) ?? const []).cast<String>(),
      );
}

enum MatchStatus { pendingPitch, open, cancelled, closed }

MatchStatus _status(String v) => switch (v) {
      'pending_pitch' => MatchStatus.pendingPitch,
      'open' => MatchStatus.open,
      'cancelled' => MatchStatus.cancelled,
      _ => MatchStatus.closed,
    };

/// A row of the match_list view.
class MatchSummary {
  const MatchSummary({
    required this.id,
    required this.kickoffAt,
    required this.durationMinutes,
    required this.format,
    required this.costSplit,
    required this.pricePerPlayerEgp,
    required this.allowCash,
    required this.cameAsTeam,
    required this.status,
    required this.pitchConfirmed,
    required this.hostId,
    required this.teamAColor,
    required this.teamBColor,
    required this.pitchId,
    required this.pitchName,
    required this.area,
    required this.lat,
    required this.lng,
    required this.capacity,
    required this.joined,
    this.scoreA,
    this.scoreB,
  });

  final String id;
  final DateTime kickoffAt;
  final int durationMinutes;
  final MatchFormat format;
  final CostSplit costSplit;
  final int pricePerPlayerEgp;
  final bool allowCash;
  final bool cameAsTeam;
  final MatchStatus status;
  final bool pitchConfirmed;
  final String hostId;
  final String teamAColor;
  final String teamBColor;
  final String pitchId;
  final String pitchName;
  final String area;
  final double lat;
  final double lng;
  final int capacity;
  final int joined;
  final int? scoreA;
  final int? scoreB;

  int get spotsLeft => capacity - joined;
  bool get isFull => spotsLeft <= 0;
  DateTime get endsAt => kickoffAt.add(Duration(minutes: durationMinutes));
  DateTime get ratingClosesAt => kickoffAt.add(const Duration(hours: 24));

  bool isJoinable(DateTime now) =>
      (status == MatchStatus.open || status == MatchStatus.pendingPitch) &&
      kickoffAt.isAfter(now) &&
      !isFull;

  /// Ratings and attendance reports are open from the end of the match
  /// (reports: from kickoff) until 24 hours after kickoff.
  bool isRatingOpen(DateTime now) =>
      status == MatchStatus.open && now.isAfter(endsAt) && now.isBefore(ratingClosesAt);

  bool isReportingOpen(DateTime now) =>
      status == MatchStatus.open && now.isAfter(kickoffAt) && now.isBefore(ratingClosesAt);

  factory MatchSummary.fromJson(Map<String, dynamic> j) => MatchSummary(
        id: j['id'] as String,
        kickoffAt: _date(j['kickoff_at'])!,
        durationMinutes: j['duration_minutes'] as int,
        format: formatFromDb(j['format'] as String),
        costSplit: j['cost_split'] == 'equal' ? CostSplit.equal : CostSplit.hostPays,
        pricePerPlayerEgp: j['price_per_player_egp'] as int,
        allowCash: j['allow_cash'] as bool,
        cameAsTeam: j['came_as_team'] as bool,
        status: _status(j['status'] as String),
        pitchConfirmed: j['pitch_confirmed'] as bool,
        hostId: j['host_id'] as String,
        teamAColor: j['team_a_color'] as String,
        teamBColor: j['team_b_color'] as String,
        pitchId: j['pitch_id'] as String,
        pitchName: j['pitch_name'] as String,
        area: j['area'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        capacity: j['capacity'] as int,
        joined: j['joined'] as int,
        scoreA: j['score_a'] as int?,
        scoreB: j['score_b'] as int?,
      );
}

enum Team { a, b }

/// One spot on a match roster: an app player or a guest.
class RosterEntry {
  const RosterEntry({
    required this.spotId,
    required this.position,
    this.playerId,
    this.guestName,
    this.team,
    this.stats,
  });

  final String spotId;
  final String? playerId;
  final String? guestName;
  final Position position;
  final Team? team;
  final PlayerStats? stats;

  bool get isGuest => playerId == null;
  String get name => stats?.displayName ?? guestName ?? '';
}

enum PaymentStatus { notRequired, unpaid, paid, refundDue, refunded, forfeited }

PaymentStatus _payment(String v) => switch (v) {
      'not_required' => PaymentStatus.notRequired,
      'unpaid' => PaymentStatus.unpaid,
      'paid' => PaymentStatus.paid,
      'refund_due' => PaymentStatus.refundDue,
      'refunded' => PaymentStatus.refunded,
      _ => PaymentStatus.forfeited,
    };

/// The signed-in player's own spot in a match, with payment details.
class MySpot {
  const MySpot({
    required this.id,
    required this.matchId,
    required this.joined,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.amountEgp,
    this.team,
  });

  final String id;
  final String matchId;
  final bool joined;
  final String paymentMethod;
  final PaymentStatus paymentStatus;
  final int amountEgp;
  final Team? team;

  factory MySpot.fromJson(Map<String, dynamic> j) => MySpot(
        id: j['id'] as String,
        matchId: j['match_id'] as String,
        joined: j['status'] == 'joined',
        paymentMethod: j['payment_method'] as String,
        paymentStatus: _payment(j['payment_status'] as String),
        amountEgp: j['amount_egp'] as int,
        team: switch (j['team']) { 'A' => Team.a, 'B' => Team.b, _ => null },
      );
}

class LeaveWarning {
  const LeaveWarning({required this.free, required this.freeUntil});

  /// Leaving now is free and fully refunded. Otherwise it is a late
  /// cancellation: refunded only if someone takes the spot, and it lowers the
  /// on-time rate.
  final bool free;
  final DateTime freeUntil;

  factory LeaveWarning.fromJson(Map<String, dynamic> j) => LeaveWarning(
        free: j['free'] as bool,
        freeUntil: _date(j['free_until'])!,
      );
}

class MatchFilter {
  const MatchFilter({this.area, this.format, this.day, this.maxPriceEgp});

  final String? area;
  final MatchFormat? format;
  final DateTime? day;
  final int? maxPriceEgp;

  MatchFilter copyWith({
    String? Function()? area,
    MatchFormat? Function()? format,
    DateTime? Function()? day,
    int? Function()? maxPriceEgp,
  }) =>
      MatchFilter(
        area: area != null ? area() : this.area,
        format: format != null ? format() : this.format,
        day: day != null ? day() : this.day,
        maxPriceEgp: maxPriceEgp != null ? maxPriceEgp() : this.maxPriceEgp,
      );
}
