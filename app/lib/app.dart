import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/kora_api.dart';
import 'data/models.dart';
import 'l10n/gen/app_localizations.dart';
import 'ui/api_scope.dart';
import 'ui/auth/create_profile_screen.dart';
import 'ui/auth/phone_screen.dart';
import 'ui/home_screen.dart';
import 'ui/labels.dart';

class KoraApp extends StatefulWidget {
  const KoraApp({super.key, required this.api, this.initialLocale = const Locale('ar')});

  final KoraApi api;
  final Locale initialLocale;

  @override
  State<KoraApp> createState() => _KoraAppState();
}

class _KoraAppState extends State<KoraApp> {
  late final ValueNotifier<Locale> _locale = ValueNotifier(widget.initialLocale);

  @override
  void dispose() {
    _locale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ApiScope(
      api: widget.api,
      child: LocaleScope(
        locale: _locale,
        child: ValueListenableBuilder<Locale>(
          valueListenable: _locale,
          builder: (context, locale, _) => MaterialApp(
            onGenerateTitle: (c) => c.l10n.appTitle,
            debugShowCheckedModeBanner: false,
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B7F3B)),
              useMaterial3: true,
            ),
            home: const AuthGate(),
          ),
        ),
      ),
    );
  }
}

/// Shows sign-in, then profile creation, then the app.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<String?>? _sub;
  String? _userId;
  Future<Profile?>? _profile;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub != null) return;
    final api = ApiScope.of(context);
    _setUser(api.currentUserId);
    _sub = api.authChanges.listen((id) {
      if (id != _userId) setState(() => _setUser(id));
    });
  }

  void _setUser(String? id) {
    _userId = id;
    _profile = id == null ? null : ApiScope.of(context).myProfile();
  }

  void _reloadProfile() => setState(() { _profile = ApiScope.of(context).myProfile(); });

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_userId == null) return const PhoneScreen();
    return FutureBuilder<Profile?>(
      future: _profile,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: FilledButton(onPressed: _reloadProfile, child: Text(context.l10n.retry)),
            ),
          );
        }
        final profile = snap.data;
        if (profile == null) return CreateProfileScreen(onCreated: _reloadProfile);
        return HomeScreen(profile: profile, onProfileChanged: _reloadProfile);
      },
    );
  }
}
