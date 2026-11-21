import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the last remote-source settings between sessions.
///
/// The GitHub token is only stored when the user opts in. On web this is the
/// browser's localStorage for this site; on other platforms it is the
/// platform's app preferences store (not an encrypted keychain).
class RemotePrefs {
  static const _ghRepo = 'remote.github.repo';
  static const _ghRef = 'remote.github.ref';
  static const _ghToken = 'remote.github.token';

  static Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null; // Storage unavailable (e.g. blocked in the browser).
    }
  }

  static Future<({String repo, String ref, String token})> loadGitHub() async {
    final p = await _prefs();
    return (
      repo: p?.getString(_ghRepo) ?? '',
      ref: p?.getString(_ghRef) ?? '',
      token: p?.getString(_ghToken) ?? '',
    );
  }

  static Future<void> saveGitHub({
    required String repo,
    required String ref,
    String? token,
  }) async {
    final p = await _prefs();
    if (p == null) return;
    await p.setString(_ghRepo, repo);
    await p.setString(_ghRef, ref);
    if (token == null || token.isEmpty) {
      await p.remove(_ghToken);
    } else {
      await p.setString(_ghToken, token);
    }
  }
}
