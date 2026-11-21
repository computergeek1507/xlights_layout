import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's GitHub personal access token locally (browser
/// localStorage on web) so they don't have to re-paste it every visit.
///
/// This is local, unencrypted storage — adequate for a personal-use tool,
/// but the token should be scoped to read-only repo access.
class GitHubTokenStore {
  static const _key = 'github_pat';

  static Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  static Future<void> save(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, token);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
