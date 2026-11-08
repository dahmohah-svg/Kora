import 'package:flutter/widgets.dart';

import '../data/kora_api.dart';

/// Gives every screen access to the backend.
class ApiScope extends InheritedWidget {
  const ApiScope({super.key, required this.api, required super.child});

  final KoraApi api;

  static KoraApi of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ApiScope>()!.api;

  @override
  bool updateShouldNotify(ApiScope oldWidget) => api != oldWidget.api;
}

/// The app language, switchable from the profile screen.
class LocaleScope extends InheritedNotifier<ValueNotifier<Locale>> {
  const LocaleScope({super.key, required ValueNotifier<Locale> locale, required super.child})
      : super(notifier: locale);

  static ValueNotifier<Locale> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LocaleScope>()!.notifier!;
}
