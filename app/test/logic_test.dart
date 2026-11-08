import 'package:flutter_test/flutter_test.dart';
import 'package:kora/data/kora_api.dart';
import 'package:kora/data/models.dart';
import 'package:kora/data/phone.dart';
import 'package:kora/ui/labels.dart';
import 'package:kora/ui/matches/create_match_screen.dart';

import 'fake_api.dart';

void main() {
  group('Egyptian phone numbers', () {
    test('accepts the ways people type them', () {
      expect(normalizeEgyptianMobile('01012345678'), '+201012345678');
      expect(normalizeEgyptianMobile('+20 101 234 5678'), '+201012345678');
      expect(normalizeEgyptianMobile('00201112345678'), '+201112345678');
      expect(normalizeEgyptianMobile('1512345678'), '+201512345678');
      expect(normalizeEgyptianMobile('٠١٢٢٣٤٥٦٧٨٩'), '+201223456789');
    });

    test('rejects landlines and wrong lengths', () {
      expect(normalizeEgyptianMobile('0223456789'), isNull);
      expect(normalizeEgyptianMobile('0101234567'), isNull);
      expect(normalizeEgyptianMobile('01312345678'), isNull);
      expect(normalizeEgyptianMobile(''), isNull);
    });
  });

  test('price estimate matches the server (600 EGP/hour, 60 min, 5v5 = 65)', () {
    expect(
      estimatePricePerPlayer(
          pricePerHourEgp: 600, durationMinutes: 60, format: MatchFormat.fiveASide, costSplit: CostSplit.equal),
      65,
    );
    expect(
      estimatePricePerPlayer(
          pricePerHourEgp: 500, durationMinutes: 90, format: MatchFormat.sixASide, costSplit: CostSplit.equal),
      68, // 750 / 12 = 62.5 -> 63, + 5
    );
    expect(
      estimatePricePerPlayer(
          pricePerHourEgp: 600, durationMinutes: 60, format: MatchFormat.fiveASide, costSplit: CostSplit.hostPays),
      0,
    );
  });

  test('points to next level follow the plan thresholds', () {
    expect(pointsToNextLevel(0), 50);
    expect(pointsToNextLevel(120), 30);
    expect(pointsToNextLevel(300), 300);
    expect(pointsToNextLevel(600), isNull);
  });

  test('server error codes are read from the start of the message', () {
    expect(KoraException.fromMessage('match_full').code, 'match_full');
    expect(KoraException.fromMessage('account_paused_until 2026-12-04 00:00:00+00').code, 'account_paused_until');
    expect(KoraException.fromMessage('host_or_admin_only').code, 'host_or_admin_only');
    expect(KoraException.fromMessage('duplicate key value').code, 'unknown');
  });

  group('match windows', () {
    final kickoff = DateTime(2026, 12, 5, 20);
    final m = testMatch(kickoff: kickoff);

    test('rating opens at the end of the match and closes 24h after kickoff', () {
      expect(m.isRatingOpen(kickoff.add(const Duration(minutes: 30))), isFalse);
      expect(m.isRatingOpen(kickoff.add(const Duration(minutes: 61))), isTrue);
      expect(m.isRatingOpen(kickoff.add(const Duration(hours: 24, minutes: 1))), isFalse);
    });

    test('attendance reporting opens at kickoff', () {
      expect(m.isReportingOpen(kickoff.subtract(const Duration(minutes: 1))), isFalse);
      expect(m.isReportingOpen(kickoff.add(const Duration(minutes: 1))), isTrue);
    });

    test('joinable only before kickoff with spots left', () {
      expect(m.isJoinable(kickoff.subtract(const Duration(hours: 1))), isTrue);
      expect(m.isJoinable(kickoff.add(const Duration(minutes: 1))), isFalse);
      expect(testMatch(kickoff: kickoff, joined: 10).isJoinable(DateTime(2026)), isFalse);
    });
  });

  test('models parse server rows', () {
    final m = MatchSummary.fromJson({
      'id': 'x', 'kickoff_at': '2026-12-05T18:00:00+00:00', 'duration_minutes': 60, 'format': '6v6',
      'cost_split': 'host_pays', 'price_per_player_egp': 0, 'allow_cash': false, 'came_as_team': true,
      'status': 'pending_pitch', 'pitch_confirmed': false, 'host_id': 'h', 'team_a_color': 'white',
      'team_b_color': 'black', 'score_a': null, 'score_b': null, 'pitch_id': 'p', 'pitch_name': 'P',
      'area': 'Maadi', 'lat': 29.9, 'lng': 31.2, 'capacity': 12, 'joined': 3,
    });
    expect(m.format, MatchFormat.sixASide);
    expect(m.costSplit, CostSplit.hostPays);
    expect(m.status, MatchStatus.pendingPitch);
    expect(m.spotsLeft, 9);

    final s = PlayerStats.fromJson({
      'player_id': 'p', 'display_name': 'Mido', 'photo_url': null, 'favorite_position': 'goalkeeper',
      'other_positions': ['defender'], 'points': 75, 'level': 'regular', 'games_played': 4,
      'on_time_rate': 0.75, 'rated_matches': 2, 'avg_rating': null, 'rating_count': null,
    });
    expect(s.favoritePosition, Position.goalkeeper);
    expect(s.avgRating, isNull);
    expect(s.onTimeRate, 0.75);
  });
}
