import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/kora_api.dart';
import '../data/models.dart';
import '../l10n/gen/app_localizations.dart';

extension KoraL10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
  String get localeName => Localizations.localeOf(this).languageCode;
}

String positionLabel(AppLocalizations l, Position p) => switch (p) {
      Position.goalkeeper => l.positionGoalkeeper,
      Position.defender => l.positionDefender,
      Position.midfielder => l.positionMidfielder,
      Position.forward => l.positionForward,
    };

String levelLabel(AppLocalizations l, String level) => switch (level) {
      'legend' => l.levelLegend,
      'captain' => l.levelCaptain,
      'starter' => l.levelStarter,
      'regular' => l.levelRegular,
      _ => l.levelRookie,
    };

/// Level thresholds from the plan; returns points needed for the next level.
int? pointsToNextLevel(int points) {
  for (final t in const [50, 150, 300, 600]) {
    if (points < t) return t - points;
  }
  return null;
}

String formatLabel(AppLocalizations l, MatchFormat f) =>
    f == MatchFormat.fiveASide ? l.format5 : l.format6;

String colorLabel(AppLocalizations l, String color) => switch (color) {
      'white' => l.colorWhite,
      'black' => l.colorBlack,
      _ => color,
    };

Color shirtColor(String color) => switch (color) {
      'white' => Colors.white,
      'black' => const Color(0xFF222222),
      _ => Colors.grey,
    };

String paymentLabel(AppLocalizations l, PaymentStatus s) => switch (s) {
      PaymentStatus.unpaid => l.paymentUnpaid,
      PaymentStatus.paid => l.paymentPaid,
      PaymentStatus.refundDue => l.paymentRefundDue,
      PaymentStatus.refunded => l.paymentRefunded,
      PaymentStatus.notRequired => l.paymentNotRequired,
      PaymentStatus.forfeited => l.paymentForfeited,
    };

String errorMessage(AppLocalizations l, Object error) {
  final code = error is KoraException ? error.code : 'unknown';
  return switch (code) {
    'match_full' => l.errMatchFull,
    'already_joined' => l.errAlreadyJoined,
    'cash_not_allowed' => l.errCashNotAllowed,
    'account_paused_until' => l.errPaused,
    'account_banned' => l.errBanned,
    'too_young' => l.errTooYoung,
    'player_not_on_app' => l.errPlayerNotOnApp,
    'rating_closed' || 'reporting_closed' => l.errRatingClosed,
    'rating_not_open_yet' => l.errRatingNotOpen,
    'match_started' => l.errMatchStarted,
    'match_not_open' || 'match_not_found' || 'match_not_played' => l.errMatchNotOpen,
    'kickoff_in_past' => l.errKickoffInPast,
    'dispute_closed' => l.errDisputeClosed,
    'nothing_to_dispute' => l.errNothingToDispute,
    'host_only' || 'host_or_admin_only' || 'admin_only' || 'not_in_same_match' => l.errNotAllowed,
    _ => l.errGeneric,
  };
}

String formatKickoff(BuildContext context, DateTime t) =>
    DateFormat('EEEE d MMMM · h:mm a', context.localeName).format(t);

String formatTime(BuildContext context, DateTime t) =>
    DateFormat('h:mm a', context.localeName).format(t);

String formatDay(BuildContext context, DateTime t) =>
    DateFormat('EEEE d MMMM', context.localeName).format(t);

void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(errorMessage(context.l10n, error))));
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Runs an action, showing the server's refusal as a message. Returns true
/// when it succeeded.
Future<bool> runAction(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
    return true;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}
