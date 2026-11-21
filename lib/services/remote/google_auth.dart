import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// OAuth client IDs are supplied at build time so none are committed:
///
/// ```sh
/// flutter build web --dart-define=GOOGLE_CLIENT_ID=1234-abc.apps.googleusercontent.com
/// ```
///
/// * `GOOGLE_CLIENT_ID` — "Web application" client (web build).
/// * `GOOGLE_APPLE_CLIENT_ID` — "iOS" client for iOS/macOS (or set
///   `GIDClientID` in Info.plist instead).
/// * `GOOGLE_SERVER_CLIENT_ID` — optional on Android; Android identifies the
///   app by package name + signing SHA-1 registered in Google Cloud.
const _webClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
const _appleClientId = String.fromEnvironment('GOOGLE_APPLE_CLIENT_ID');
const _serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

/// Read-only access to the user's Drive files. This is a "restricted" scope:
/// fine for personal/test-user use, but a public OAuth app needs Google's
/// verification before arbitrary users can grant it.
const driveReadonlyScope = 'https://www.googleapis.com/auth/drive.readonly';

/// Thin wrapper around `google_sign_in` that hands out a Drive access token.
class GoogleDriveAuth {
  GoogleDriveAuth._();

  static final GoogleDriveAuth instance = GoogleDriveAuth._();

  Future<void>? _init;
  String? _accessToken;

  /// Whether Google sign-in exists on this platform (no Windows/Linux plugin).
  static bool get platformSupported {
    if (kIsWeb) return true;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.macOS => true,
      _ => false,
    };
  }

  /// Whether this build was given the client ID the platform needs.
  static bool get configured {
    if (!platformSupported) return false;
    if (kIsWeb) return _webClientId.isNotEmpty;
    // iOS/macOS may carry GIDClientID in Info.plist and Android needs no
    // client ID in code, so assume configured and let sign-in report errors.
    return true;
  }

  /// Why Drive is unavailable, or `null` if it can be used.
  static String? get unavailableReason {
    if (!platformSupported) {
      return 'Google Drive sign-in is not available in the desktop app on this '
          'platform. Use the web version, or download the files from Drive first.';
    }
    if (!configured) {
      return 'Google Drive is not set up in this build (no GOOGLE_CLIENT_ID).';
    }
    return null;
  }

  /// Starts initializing early (call when the Drive dialog opens) so the
  /// sign-in popup can open straight from the button press on web.
  Future<void> ensureInitialized() => _init ??= GoogleSignIn.instance.initialize(
        clientId: kIsWeb
            ? _webClientId
            : (_appleClientId.isEmpty ? null : _appleClientId),
        serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
      );

  /// The last token handed out, if still believed valid.
  String? get cachedToken => _accessToken;

  /// Gets a Drive access token, prompting the user if needed. On web this
  /// opens a popup, so call it directly from a button handler.
  Future<String> accessToken({bool forcePrompt = false}) async {
    if (!forcePrompt && _accessToken != null) return _accessToken!;
    await ensureInitialized();
    final client = GoogleSignIn.instance.authorizationClient;
    const scopes = [driveReadonlyScope];
    GoogleSignInClientAuthorization? auth;
    if (!forcePrompt && !kIsWeb) {
      auth = await client.authorizationForScopes(scopes);
    }
    auth ??= await client.authorizeScopes(scopes);
    return _accessToken = auth.accessToken;
  }

  /// Forgets the cached token (e.g. after a 401).
  void invalidate() => _accessToken = null;

  Future<void> signOut() async {
    _accessToken = null;
    if (_init != null) await GoogleSignIn.instance.signOut();
  }
}
