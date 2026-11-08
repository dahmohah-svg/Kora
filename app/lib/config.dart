/// Build-time settings, passed with --dart-define. See app/README.md.
class KoraConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// Base of the link shared on WhatsApp; a match id is appended.
  static const shareBaseUrl =
      String.fromEnvironment('SHARE_BASE_URL', defaultValue: 'https://kora.app/m/');

  /// Kept in step with app_config.service_fee_egp on the server; used only
  /// for the price estimate before a match is created.
  static const serviceFeeEgp = 5;

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
