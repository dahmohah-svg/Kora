import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config.dart';
import 'data/supabase_kora_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  if (!KoraConfig.isConfigured) {
    runApp(const _MissingConfig());
    return;
  }
  await Supabase.initialize(url: KoraConfig.supabaseUrl, publishableKey: KoraConfig.supabasePublishableKey);
  runApp(KoraApp(api: SupabaseKoraApi(Supabase.instance.client)));
}

class _MissingConfig extends StatelessWidget {
  const _MissingConfig();

  @override
  Widget build(BuildContext context) => const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Run with --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=... '
                '(see app/README.md).',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
}
