/// Runtime configuration. Values come from --dart-define so no secret is
/// ever committed. See .env.example / README.
class AppConfig {
  static void validate() {
    final uri = Uri.parse(apiBaseUrl);
    if (uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        !['https', 'http'].contains(uri.scheme) ||
        (environment == 'production' && uri.scheme != 'https')) {
      throw StateError('API_BASE_URL must use HTTPS in production');
    }
  }

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000/api/v1',
  );
  static const String environment = String.fromEnvironment(
    'ENVIRONMENT',
    defaultValue: 'development',
  );
}
