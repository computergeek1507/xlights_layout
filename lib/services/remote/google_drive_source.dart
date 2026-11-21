import 'dart:convert';

import 'package:http/http.dart' as http;

import 'remote_source.dart';

/// Thrown when the Drive access token is missing, expired or revoked, so the
/// caller can ask the user to sign in again.
class DriveAuthException extends RemoteSourceException {
  const DriveAuthException()
      : super('Google Drive access expired or was revoked. Sign in again.');
}

/// Finds and downloads xLights show files from Google Drive (My Drive,
/// "Shared with me" and shared drives) with the Drive v3 REST API, given an
/// OAuth access token with the `drive.readonly` scope.
class GoogleDriveSource {
  GoogleDriveSource({required this.accessToken, http.Client? client})
      : _client = client ?? http.Client();

  static const _api = 'https://www.googleapis.com/drive/v3';
  static const folderMimeType = 'application/vnd.google-apps.folder';

  final String accessToken;
  final http.Client _client;

  Future<Map<String, dynamic>> _getJson(String path, Map<String, String> query) async {
    final uri = Uri.parse('$_api/$path').replace(queryParameters: {
      ...query,
      'supportsAllDrives': 'true',
    });
    final http.Response res;
    try {
      res = await _client.get(uri, headers: {'Authorization': 'Bearer $accessToken'});
    } catch (e) {
      throw RemoteSourceException('Could not reach Google Drive: $e');
    }
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  void _check(http.Response res) {
    if (res.statusCode == 200) return;
    if (res.statusCode == 401) throw const DriveAuthException();
    String? msg;
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['error'] is Map) msg = (body['error'] as Map)['message'] as String?;
    } catch (_) {}
    if (res.statusCode == 404) {
      throw const RemoteSourceException(
          'Drive file or folder not found, or your Google account has no access to it.');
    }
    throw RemoteSourceException('Google Drive returned HTTP ${res.statusCode}${msg != null ? ': $msg' : ''}');
  }

  /// Escapes a value for a Drive `q` string literal.
  static String _q(String v) => v.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  Future<List<Map<String, dynamic>>> _listFiles(String q, {int pageSize = 100}) async {
    final out = <Map<String, dynamic>>[];
    String? pageToken;
    do {
      final body = await _getJson('files', {
        'q': q,
        'fields': 'nextPageToken,files(id,name,mimeType,parents,modifiedTime)',
        'orderBy': 'modifiedTime desc',
        'pageSize': '$pageSize',
        'corpora': 'allDrives',
        'includeItemsFromAllDrives': 'true',
        'pageToken': ?pageToken,
      });
      for (final f in (body['files'] as List? ?? const [])) {
        out.add((f as Map).cast<String, dynamic>());
      }
      pageToken = body['nextPageToken'] as String?;
    } while (pageToken != null && out.length < 500);
    return out;
  }

  Future<String?> _folderName(String id) async {
    try {
      final f = await _getJson('files/$id', {'fields': 'name'});
      return f['name'] as String?;
    } on DriveAuthException {
      rethrow;
    } on RemoteSourceException {
      return null; // e.g. a parent the user can't see.
    }
  }

  /// Returns the `xlights_networks.xml` file ID in [folderId], if any.
  Future<String?> _networksIn(String folderId) async {
    final files = await _listFiles(
        "'${_q(folderId)}' in parents and name = '$networksFileName' and trashed = false",
        pageSize: 5);
    return files.isEmpty ? null : files.first['id'] as String;
  }

  Future<ShowFolderCandidate> _candidateFor(Map<String, dynamic> rgbFile) async {
    final parents = (rgbFile['parents'] as List?)?.cast<String>() ?? const <String>[];
    final parent = parents.isEmpty ? null : parents.first;
    final folder = parent == null ? null : await _folderName(parent);
    final networks = parent == null ? null : await _networksIn(parent);
    return ShowFolderCandidate(
      title: folder ?? '(unknown folder)',
      subtitle: [
        if (rgbFile['modifiedTime'] is String) 'Modified ${_fmtTime(rgbFile['modifiedTime'] as String)}',
        networks != null ? 'rgbeffects + networks' : 'rgbeffects only',
      ].join(' · '),
      rgbEffectsRef: rgbFile['id'] as String,
      networksRef: networks,
    );
  }

  static String _fmtTime(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return iso;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  /// Searches the user's whole Drive for show folders (newest first).
  Future<List<ShowFolderCandidate>> searchShowFolders({int limit = 25}) async {
    final files = await _listFiles("name = '$rgbEffectsFileName' and trashed = false", pageSize: limit);
    final top = files.take(limit).toList();
    final candidates = await Future.wait(top.map(_candidateFor));
    if (candidates.isEmpty) {
      throw const RemoteSourceException('No $rgbEffectsFileName found in your Google Drive.');
    }
    return candidates;
  }

  /// Extracts a Drive file/folder ID from a share link, or returns the input
  /// if it already looks like a bare ID.
  static String? parseId(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    final m = RegExp(r'/(?:file/d|folders|document/d|uc/d)/([A-Za-z0-9_-]{10,})').firstMatch(text) ??
        RegExp(r'[?&]id=([A-Za-z0-9_-]{10,})').firstMatch(text);
    if (m != null) return m.group(1);
    if (RegExp(r'^[A-Za-z0-9_-]{10,}$').hasMatch(text)) return text;
    return null;
  }

  /// Resolves a pasted Drive link (to a show folder or to one of its XML files).
  Future<List<ShowFolderCandidate>> fromLink(String link) async {
    final id = parseId(link);
    if (id == null) {
      throw const RemoteSourceException('That does not look like a Google Drive file or folder link.');
    }
    final meta = await _getJson('files/$id', {'fields': 'id,name,mimeType,parents,modifiedTime'});

    if (meta['mimeType'] == folderMimeType) {
      final files = await _listFiles(
          "'${_q(id)}' in parents and (name = '$rgbEffectsFileName' or name = '$networksFileName') "
          'and trashed = false',
          pageSize: 10);
      final rgb = files.where((f) => f['name'] == rgbEffectsFileName).firstOrNull;
      final net = files.where((f) => f['name'] == networksFileName).firstOrNull;
      if (rgb == null) {
        throw RemoteSourceException('No $rgbEffectsFileName in the folder "${meta['name']}".');
      }
      return [
        ShowFolderCandidate(
          title: meta['name'] as String? ?? 'Folder',
          subtitle: net != null ? 'rgbeffects + networks' : 'rgbeffects only',
          rgbEffectsRef: rgb['id'] as String,
          networksRef: net?['id'] as String?,
        ),
      ];
    }

    final name = (meta['name'] as String? ?? '').toLowerCase();
    if (name == networksFileName) {
      final parents = (meta['parents'] as List?)?.cast<String>() ?? const <String>[];
      if (parents.isNotEmpty) {
        final rgbs = await _listFiles(
            "'${_q(parents.first)}' in parents and name = '$rgbEffectsFileName' and trashed = false",
            pageSize: 5);
        if (rgbs.isNotEmpty) return [await _candidateFor(rgbs.first)];
      }
      throw const RemoteSourceException('No $rgbEffectsFileName next to that networks file.');
    }
    if (!name.endsWith('.xml')) {
      throw RemoteSourceException('"${meta['name']}" is not an xLights XML file.');
    }
    return [await _candidateFor(meta)];
  }

  /// Downloads the files for [candidate].
  Future<List<RemoteFile>> download(ShowFolderCandidate candidate) async {
    return [
      RemoteFile(rgbEffectsFileName, await downloadFile(candidate.rgbEffectsRef)),
      if (candidate.networksRef != null)
        RemoteFile(networksFileName, await downloadFile(candidate.networksRef!)),
    ];
  }

  Future<List<int>> downloadFile(String fileId) async {
    final uri = Uri.parse('$_api/files/$fileId')
        .replace(queryParameters: {'alt': 'media', 'supportsAllDrives': 'true'});
    final http.Response res;
    try {
      res = await _client.get(uri, headers: {'Authorization': 'Bearer $accessToken'});
    } catch (e) {
      throw RemoteSourceException('Could not reach Google Drive: $e');
    }
    _check(res);
    return res.bodyBytes;
  }

  void close() => _client.close();
}
