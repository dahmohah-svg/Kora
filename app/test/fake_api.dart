import 'dart:async';

import 'package:kora/data/kora_api.dart';
import 'package:kora/data/models.dart';

/// In-memory backend for widget tests. Records calls and keeps just enough
/// state for the screens to behave.
class FakeKoraApi implements KoraApi {
  FakeKoraApi({this.userId, this.profile});

  String? userId;
  Profile? profile;
  final _auth = StreamController<String?>.broadcast();
  final calls = <String>[];

  List<Pitch> pitchList = [];
  final Map<String, MatchSummary> matches = {};
  final Map<String, List<RosterEntry>> rosters = {};
  final Map<String, MySpot> spots = {};
  final Map<String, Map<String, int>> ratings = {};
  PlayerStats? stats;
  LeaveWarning leave = LeaveWarning(free: true, freeUntil: DateTime(2030));
  KoraException? failNext;

  void _maybeFail() {
    final f = failNext;
    failNext = null;
    if (f != null) throw f;
  }

  @override
  String? get currentUserId => userId;

  @override
  Stream<String?> get authChanges => _auth.stream;

  @override
  Future<void> sendOtp(String phone) async {
    calls.add('sendOtp $phone');
    _maybeFail();
  }

  @override
  Future<void> verifyOtp(String phone, String code) async {
    calls.add('verifyOtp $phone $code');
    _maybeFail();
    userId = 'me';
    _auth.add('me');
  }

  @override
  Future<void> signOut() async {
    userId = null;
    _auth.add(null);
  }

  @override
  Future<Profile?> myProfile() async => profile;

  @override
  Future<void> createProfile({
    required String displayName,
    required Position favoritePosition,
    required List<Position> otherPositions,
    required DateTime birthDate,
    required String language,
  }) async {
    calls.add('createProfile $displayName ${favoritePosition.name}');
    _maybeFail();
    profile = Profile(
      id: userId!,
      displayName: displayName,
      favoritePosition: favoritePosition,
      otherPositions: otherPositions,
      points: 0,
      language: language,
    );
  }

  @override
  Future<List<Pitch>> pitches() async => pitchList;

  @override
  Future<List<String>> areas() async => pitchList.map((p) => p.area).toSet().toList();

  @override
  Future<List<MatchSummary>> upcomingMatches(MatchFilter filter) async {
    calls.add('upcoming area=${filter.area} format=${filter.format?.name}');
    return matches.values
        .where((m) => filter.area == null || m.area == filter.area)
        .where((m) => filter.format == null || m.format == filter.format)
        .toList();
  }

  @override
  Future<List<MatchSummary>> myMatches() async =>
      matches.values.where((m) => spots[m.id]?.joined ?? false).toList();

  @override
  Future<MatchSummary> match(String matchId) async => matches[matchId]!;

  @override
  Future<List<RosterEntry>> roster(String matchId) async => rosters[matchId] ?? [];

  @override
  Future<MySpot?> mySpot(String matchId) async => spots[matchId];

  @override
  Future<PlayerStats> playerStats(String playerId) async => stats!;

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
    calls.add('createMatch $pitchId ${format.name} ${costSplit.name} $durationMinutes');
    _maybeFail();
    return 'new-match';
  }

  @override
  Future<void> confirmPitch(String matchId) async => calls.add('confirmPitch $matchId');

  @override
  Future<void> joinMatch(String matchId, Position position, PaymentMethod method) async {
    calls.add('join $matchId ${position.name} ${method.name}');
    _maybeFail();
    spots[matchId] = MySpot(
      id: 'spot',
      matchId: matchId,
      joined: true,
      paymentMethod: method.name,
      paymentStatus: PaymentStatus.unpaid,
      amountEgp: matches[matchId]!.pricePerPlayerEgp,
    );
  }

  @override
  Future<LeaveWarning> leaveWarning(String matchId) async => leave;

  @override
  Future<void> leaveMatch(String matchId) async {
    calls.add('leave $matchId');
    spots.remove(matchId);
  }

  @override
  Future<void> cancelMatch(String matchId) async => calls.add('cancel $matchId');

  @override
  Future<void> splitTeams(String matchId) async => calls.add('split $matchId');

  @override
  Future<void> hostAddPlayer(String matchId, String phone, Position position) async =>
      calls.add('addPlayer $matchId $phone');

  @override
  Future<void> hostAddGuest(String matchId, String name, Position position) async =>
      calls.add('addGuest $matchId $name');

  @override
  Future<Map<String, int>> myRatings(String matchId) async => ratings[matchId] ?? {};

  @override
  Future<void> ratePlayer(String matchId, String playerId, int stars) async {
    calls.add('rate $playerId $stars');
    (ratings[matchId] ??= {})[playerId] = stars;
  }

  @override
  Future<void> reportAttendance(String matchId, String playerId, ReportKind kind) async =>
      calls.add('report $playerId ${kind.name}');

  @override
  Future<void> disputeAttendance(String matchId, String reason) async => calls.add('dispute $reason');

  @override
  Future<bool> reportScore(String matchId, int scoreA, int scoreB) async {
    calls.add('score $scoreA-$scoreB');
    return false;
  }
}

Profile testProfile({String id = 'me'}) => Profile(
      id: id,
      displayName: 'Ahmed',
      favoritePosition: Position.forward,
      otherPositions: const [Position.midfielder],
      points: 120,
      language: 'ar',
    );

MatchSummary testMatch({
  String id = 'm1',
  required DateTime kickoff,
  String hostId = 'host',
  int joined = 6,
  MatchStatus status = MatchStatus.open,
  bool allowCash = true,
  String area = 'Maadi',
  MatchFormat format = MatchFormat.fiveASide,
}) =>
    MatchSummary(
      id: id,
      kickoffAt: kickoff,
      durationMinutes: 60,
      format: format,
      costSplit: CostSplit.equal,
      pricePerPlayerEgp: 65,
      allowCash: allowCash,
      cameAsTeam: false,
      status: status,
      pitchConfirmed: status == MatchStatus.open,
      hostId: hostId,
      teamAColor: 'white',
      teamBColor: 'black',
      pitchId: 'p1',
      pitchName: 'Maadi Club Pitch 2',
      area: area,
      lat: 29.96,
      lng: 31.25,
      capacity: capacityOf(format),
      joined: joined,
    );

PlayerStats testStats(String id, String name, {double? avg}) => PlayerStats(
      playerId: id,
      displayName: name,
      favoritePosition: Position.midfielder,
      otherPositions: const [],
      points: 60,
      level: 'regular',
      gamesPlayed: 5,
      ratedMatches: avg == null ? 1 : 4,
      onTimeRate: 0.8,
      avgRating: avg,
    );
