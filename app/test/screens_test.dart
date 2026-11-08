import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kora/app.dart';
import 'package:kora/data/kora_api.dart';
import 'package:kora/data/models.dart';
import 'package:kora/ui/api_scope.dart';
import 'package:kora/ui/matches/match_detail_screen.dart';
import 'package:kora/l10n/gen/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'fake_api.dart';

Widget detailScreen(FakeKoraApi api, {required DateTime now, Locale locale = const Locale('en')}) =>
    ApiScope(
      api: api,
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MatchDetailScreen(matchId: 'm1', profile: api.profile!, clock: () => now),
      ),
    );

void main() {
  setUpAll(() => initializeDateFormatting());

  testWidgets('signed out: Arabic, right-to-left phone sign-in', (tester) async {
    final api = FakeKoraApi();
    await tester.pumpWidget(KoraApp(api: api));
    await tester.pumpAndSettle();

    expect(find.text('سجّل برقم موبايلك'), findsOneWidget);
    final dir = Directionality.of(tester.element(find.byKey(const Key('phone'))));
    expect(dir, TextDirection.rtl);

    await tester.enterText(find.byKey(const Key('phone')), '0101234');
    await tester.tap(find.text('ابعت الكود'));
    await tester.pumpAndSettle();
    expect(find.text('اكتب رقم موبايل مصري صحيح'), findsOneWidget);
    expect(api.calls, isEmpty);

    await tester.enterText(find.byKey(const Key('phone')), '010 1234 5678');
    await tester.tap(find.text('ابعت الكود'));
    await tester.pumpAndSettle();
    expect(api.calls, ['sendOtp +201012345678']);

    await tester.enterText(find.byKey(const Key('code')), '123456');
    await tester.tap(find.text('تأكيد'));
    await tester.pumpAndSettle();
    // Signed in without a profile: profile creation.
    expect(find.text('اعمل ملفك'), findsOneWidget);
  });

  testWidgets('home lists matches and filters by format', (tester) async {
    final api = FakeKoraApi(userId: 'me', profile: testProfile());
    final kickoff = DateTime.now().add(const Duration(days: 1));
    api.matches['m1'] = testMatch(kickoff: kickoff, joined: 7);
    api.matches['m2'] = testMatch(id: 'm2', kickoff: kickoff, format: MatchFormat.sixASide, area: 'Nasr City');
    api.pitchList = const [];
    api.stats = testStats('me', 'Ahmed');
    await tester.pumpWidget(KoraApp(api: api, initialLocale: const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text('Maadi Club Pitch 2'), findsNWidgets(2));
    expect(find.text('3 spots left'), findsOneWidget);
    expect(find.text('65 EGP per player'), findsNWidgets(2));

    await tester.tap(find.widgetWithText(FilterChip, '6v6'));
    await tester.pumpAndSettle();
    expect(find.text('Maadi Club Pitch 2'), findsOneWidget);
    expect(api.calls.last, 'upcoming area=null format=sixASide');
  });

  testWidgets('join a match: choose position and pay cash', (tester) async {
    final api = FakeKoraApi(userId: 'me', profile: testProfile());
    final now = DateTime(2026, 12, 5, 12);
    api.matches['m1'] = testMatch(kickoff: DateTime(2026, 12, 5, 20));
    await tester.pumpWidget(detailScreen(api, now: now));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('join')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Goalkeeper'));
    await tester.tap(find.text('Cash at the pitch'));
    await tester.tap(find.byKey(const Key('confirm-join')));
    await tester.pumpAndSettle();

    expect(api.calls, contains('join m1 goalkeeper cash'));
    expect(find.byKey(const Key('leave')), findsOneWidget);
    expect(find.text('Payment: Not paid yet'), findsOneWidget);
  });

  testWidgets('leaving late shows the late-cancellation warning', (tester) async {
    final api = FakeKoraApi(userId: 'me', profile: testProfile());
    final now = DateTime(2026, 12, 5, 18);
    api.matches['m1'] = testMatch(kickoff: DateTime(2026, 12, 5, 20));
    api.spots['m1'] = const MySpot(
        id: 's', matchId: 'm1', joined: true, paymentMethod: 'online',
        paymentStatus: PaymentStatus.paid, amountEgp: 65);
    api.leave = LeaveWarning(free: false, freeUntil: DateTime(2026, 12, 5, 17));
    await tester.pumpWidget(detailScreen(api, now: now));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('leave')));
    await tester.pumpAndSettle();
    expect(find.text('Late cancellation'), findsOneWidget);
    expect(find.textContaining('refunded only if someone takes your spot'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirm-leave')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('leave m1'));
  });

  testWidgets('server refusals are shown in the player\'s language', (tester) async {
    final api = FakeKoraApi(userId: 'me', profile: testProfile());
    api.matches['m1'] = testMatch(kickoff: DateTime(2026, 12, 5, 20));
    await tester.pumpWidget(detailScreen(api, now: DateTime(2026, 12, 5, 12), locale: const Locale('ar')));
    await tester.pumpAndSettle();

    api.failNext = const KoraException('match_full');
    await tester.tap(find.byKey(const Key('join')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-join')));
    await tester.pumpAndSettle();
    expect(find.text('الماتش كمل.'), findsOneWidget);
  });

  testWidgets('after the match: rate players and report a no-show', (tester) async {
    final api = FakeKoraApi(userId: 'me', profile: testProfile());
    final kickoff = DateTime(2026, 12, 5, 20);
    api.matches['m1'] = testMatch(kickoff: kickoff, joined: 3);
    api.spots['m1'] = const MySpot(
        id: 's', matchId: 'm1', joined: true, paymentMethod: 'online',
        paymentStatus: PaymentStatus.paid, amountEgp: 65, team: Team.a);
    api.rosters['m1'] = [
      RosterEntry(spotId: '1', playerId: 'me', position: Position.forward, team: Team.a,
          stats: testStats('me', 'Ahmed')),
      RosterEntry(spotId: '2', playerId: 'p2', position: Position.defender, team: Team.b,
          stats: testStats('p2', 'Mido', avg: 4.2)),
      const RosterEntry(spotId: '3', guestName: 'Zizo', position: Position.goalkeeper, team: Team.b),
    ];
    await tester.pumpWidget(detailScreen(api, now: kickoff.add(const Duration(hours: 2))));
    await tester.pumpAndSettle();

    expect(find.text('White team'), findsOneWidget);
    expect(find.text('Black team'), findsOneWidget);
    expect(find.text('4.2'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('rate-p2-4')), 200);
    expect(find.byKey(const Key('after-match')), findsOneWidget);
    // Guests can't be rated.
    expect(find.byKey(const Key('rate-null-5')), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('rate-p2-4')));
    await tester.tap(find.byKey(const Key('rate-p2-4')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('rate p2 4'));

    await tester.scrollUntilVisible(find.text('No-show'), 200);
    await tester.tap(find.text('No-show'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('report p2 noShow'));
  });

  testWidgets('host tools: confirm the pitch booking', (tester) async {
    final api = FakeKoraApi(userId: 'me', profile: testProfile());
    api.matches['m1'] = testMatch(kickoff: DateTime(2026, 12, 5, 20), hostId: 'me', status: MatchStatus.pendingPitch);
    api.spots['m1'] = const MySpot(
        id: 's', matchId: 'm1', joined: true, paymentMethod: 'online',
        paymentStatus: PaymentStatus.unpaid, amountEgp: 65);
    await tester.pumpWidget(detailScreen(api, now: DateTime(2026, 12, 5, 12)));
    await tester.pumpAndSettle();

    expect(find.text('Payment opens once the host confirms the pitch booking'), findsOneWidget);
    expect(find.byKey(const Key('leave')), findsNothing); // the host cancels instead
    await tester.ensureVisible(find.byKey(const Key('confirm-pitch')));
    await tester.tap(find.byKey(const Key('confirm-pitch')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('confirmPitch m1'));
  });
}
