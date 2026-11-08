import 'models.dart';

/// Everything the app asks of the backend. The real implementation talks to
/// Supabase; tests use a fake.
abstract class KoraApi {
  /// The signed-in user's id, or null when signed out.
  String? get currentUserId;

  /// Emits whenever the user signs in or out.
  Stream<String?> get authChanges;

  Future<void> sendOtp(String phone);
  Future<void> verifyOtp(String phone, String code);
  Future<void> signOut();

  /// Null until the player has created a profile.
  Future<Profile?> myProfile();
  Future<void> createProfile({
    required String displayName,
    required Position favoritePosition,
    required List<Position> otherPositions,
    required DateTime birthDate,
    required String language,
  });

  Future<List<Pitch>> pitches();
  Future<List<String>> areas();
  Future<List<MatchSummary>> upcomingMatches(MatchFilter filter);
  Future<List<MatchSummary>> myMatches();
  Future<MatchSummary> match(String matchId);
  Future<List<RosterEntry>> roster(String matchId);
  Future<MySpot?> mySpot(String matchId);
  Future<PlayerStats> playerStats(String playerId);

  Future<String> createMatch({
    required String pitchId,
    required DateTime kickoffAt,
    required int durationMinutes,
    required MatchFormat format,
    required CostSplit costSplit,
    required bool allowCash,
    required bool cameAsTeam,
    required Position hostPosition,
  });
  Future<void> confirmPitch(String matchId);
  Future<void> joinMatch(String matchId, Position position, PaymentMethod method);
  Future<LeaveWarning> leaveWarning(String matchId);
  Future<void> leaveMatch(String matchId);
  Future<void> cancelMatch(String matchId);
  Future<void> splitTeams(String matchId);
  Future<void> hostAddPlayer(String matchId, String phone, Position position);
  Future<void> hostAddGuest(String matchId, String name, Position position);

  /// Ids of players the signed-in user already rated in this match.
  Future<Map<String, int>> myRatings(String matchId);
  Future<void> ratePlayer(String matchId, String playerId, int stars);
  Future<void> reportAttendance(String matchId, String playerId, ReportKind kind);
  Future<void> disputeAttendance(String matchId, String reason);
  Future<bool> reportScore(String matchId, int scoreA, int scoreB);
}

/// A rule the server refused, with its code (e.g. `match_full`).
class KoraException implements Exception {
  const KoraException(this.code);
  final String code;

  static const known = {
    'not_signed_in', 'no_profile', 'account_banned', 'account_paused_until',
    'admin_only', 'match_not_found', 'match_not_open', 'match_started',
    'match_full', 'already_joined', 'cash_not_allowed', 'kickoff_in_past',
    'host_must_cancel', 'not_in_match', 'too_young', 'player_not_on_app',
    'rating_not_open_yet', 'rating_closed', 'reporting_closed',
    'not_in_same_match', 'nothing_to_dispute', 'dispute_closed',
    'came_as_team_no_split', 'host_only', 'host_or_admin_only', 'match_not_played',
    'not_on_a_team', 'pitch_not_found', 'guest_name_required',
  };

  /// The server raises errors whose message starts with the rule code,
  /// e.g. `match_full` or `account_paused_until 2026-12-04 ...`.
  static KoraException fromMessage(String message) {
    final code = message.trim().split(RegExp(r'\s')).first;
    return KoraException(known.contains(code) ? code : 'unknown');
  }

  @override
  String toString() => 'KoraException($code)';
}
