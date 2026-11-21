import 'dart:convert';

import 'package:http/http.dart' as http;

import 'remote_source.dart';

/// Where to look in a GitHub repository.
class GitHubLocation {
  const GitHubLocation({
    required this.owner,
    required this.repo,
    this.ref,
    this.path = '',
  });

  final String owner;
  final String repo;

  /// Branch, tag or commit SHA. `null` means the repository's default branch.
  final String? ref;

  /// Folder or file path inside the repository, without leading/trailing `/`.
  final String path;

  GitHubLocation copyWith({String? ref, String? path}) => GitHubLocation(
        owner: owner,
        repo: repo,
        ref: ref ?? this.ref,
        path: path ?? this.path,
      );

  /// Parses what a user is likely to paste:
  ///
  /// * `owner/repo` or `owner/repo/some/folder`
  /// * `https://github.com/owner/repo[.git]`
  /// * `https://github.com/owner/repo/tree/<ref>/<path>`
  /// * `https://github.com/owner/repo/blob/<ref>/<path>`
  /// * `https://raw.githubusercontent.com/owner/repo/[refs/heads/]<ref>/<path>`
  ///
  /// For `tree`/`blob`/raw URLs the first segment after the marker is taken as
  /// the ref; branches containing `/` should be entered in the separate branch
  /// field instead.
  static GitHubLocation? parse(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;

    var isRaw = false;
    final uri = Uri.tryParse(text);
    if (uri != null && uri.hasScheme) {
      final host = uri.host.toLowerCase();
      if (host == 'raw.githubusercontent.com') {
        isRaw = true;
      } else if (host != 'github.com' && host != 'www.github.com') {
        return null;
      }
      text = uri.path;
    } else if (text.toLowerCase().startsWith('github.com/')) {
      text = text.substring('github.com/'.length);
    }

    final segs = text.split('/').where((s) => s.isNotEmpty).toList();
    if (segs.length < 2) return null;
    final owner = segs[0];
    var repo = segs[1];
    if (repo.endsWith('.git')) repo = repo.substring(0, repo.length - 4);
    var rest = segs.sublist(2);

    String? ref;
    if (isRaw) {
      if (rest.length >= 3 && rest[0] == 'refs' && (rest[1] == 'heads' || rest[1] == 'tags')) {
        ref = rest[2];
        rest = rest.sublist(3);
      } else if (rest.isNotEmpty) {
        ref = rest[0];
        rest = rest.sublist(1);
      }
    } else if (rest.isNotEmpty && (rest[0] == 'tree' || rest[0] == 'blob')) {
      if (rest.length >= 2) ref = rest[1];
      rest = rest.length > 2 ? rest.sublist(2) : const [];
    }

    return GitHubLocation(
      owner: owner,
      repo: repo,
      ref: ref,
      path: rest.map(Uri.decodeComponent).join('/'),
    );
  }

  @override
  String toString() => [
        '$owner/$repo',
        if (ref != null) '@$ref',
        if (path.isNotEmpty) ':$path',
      ].join();
}

/// Loads xLights show files from a (possibly private) GitHub repository using
/// the REST API. A personal access token is needed for private repositories;
/// a fine-grained token with read-only "Contents" access to the repo is enough.
///
/// The API sends CORS headers, so this works from the web build too, and the
/// token only ever goes to api.github.com.
class GitHubSource {
  GitHubSource({http.Client? client, this.token}) : _client = client ?? http.Client();

  static const _api = 'https://api.github.com';

  final http.Client _client;
  final String? token;

  Map<String, String> _headers({bool raw = false}) => {
        'Accept': raw ? 'application/vnd.github.raw+json' : 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  String _encodePath(String path) =>
      path.split('/').where((s) => s.isNotEmpty).map(Uri.encodeComponent).join('/');

  Future<http.Response> _get(String url, {bool raw = false}) async {
    final http.Response res;
    try {
      res = await _client.get(Uri.parse(url), headers: _headers(raw: raw));
    } catch (e) {
      throw RemoteSourceException('Could not reach GitHub: $e');
    }
    if (res.statusCode == 200) return res;
    throw _errorFor(res);
  }

  RemoteSourceException _errorFor(http.Response res) {
    String? apiMessage;
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['message'] is String) apiMessage = body['message'] as String;
    } catch (_) {}
    final hasToken = token != null && token!.isNotEmpty;
    switch (res.statusCode) {
      case 401:
        return const RemoteSourceException(
            'GitHub rejected the access token. Check that it is correct and has not expired.');
      case 403:
      case 429:
        if (res.headers['x-ratelimit-remaining'] == '0') {
          return RemoteSourceException(hasToken
              ? 'GitHub API rate limit reached. Try again later.'
              : 'GitHub API rate limit reached. Add an access token to raise the limit.');
        }
        return RemoteSourceException(
            'GitHub denied access${apiMessage != null ? ': $apiMessage' : '.'} '
            'Make sure the token has read access to this repository\'s contents.');
      case 404:
        return RemoteSourceException(hasToken
            ? 'Not found. Check the repository, branch and path, and that the token can access this repository.'
            : 'Not found. If this is a private repository, add an access token.');
      default:
        return RemoteSourceException(
            'GitHub returned HTTP ${res.statusCode}${apiMessage != null ? ': $apiMessage' : ''}');
    }
  }

  /// Finds every folder under [loc] that holds an `xlights_rgbeffects.xml`.
  ///
  /// If [loc.path] points straight at an `.xml` file, that file is used and
  /// its folder is checked for `xlights_networks.xml`.
  Future<List<ShowFolderCandidate>> findShowFolders(GitHubLocation loc) async {
    final repoUrl = '$_api/repos/${Uri.encodeComponent(loc.owner)}/${Uri.encodeComponent(loc.repo)}';
    final ref = (loc.ref == null || loc.ref!.isEmpty)
        ? (jsonDecode((await _get(repoUrl)).body) as Map)['default_branch'] as String
        : loc.ref!;

    final res = await _get('$repoUrl/git/trees/${Uri.encodeComponent(ref)}?recursive=1');
    final tree = jsonDecode(res.body) as Map;
    final blobs = <String>{
      for (final e in (tree['tree'] as List? ?? const []))
        if (e is Map && e['type'] == 'blob' && e['path'] is String) e['path'] as String,
    };

    if (tree['truncated'] == true && blobs.isEmpty) {
      throw const RemoteSourceException(
          'This repository is too large to scan. Enter the path to the show folder.');
    }

    return candidatesFromPaths(blobs, loc.path, ref: ref);
  }

  /// Pure helper (exposed for tests): picks show folders out of a set of
  /// repository file paths, restricted to [basePath].
  static List<ShowFolderCandidate> candidatesFromPaths(
    Set<String> paths,
    String basePath, {
    String? ref,
  }) {
    final base = basePath.replaceAll(RegExp(r'^/+|/+$'), '');
    final lowerToActual = {for (final p in paths) p.toLowerCase(): p};

    String dirOf(String p) {
      final i = p.lastIndexOf('/');
      return i < 0 ? '' : p.substring(0, i);
    }

    String join(String dir, String name) => dir.isEmpty ? name : '$dir/$name';

    String? networksIn(String dir) => lowerToActual[join(dir, networksFileName).toLowerCase()];

    // A direct link to a file.
    if (base.toLowerCase().endsWith('.xml')) {
      final actual = lowerToActual[base.toLowerCase()];
      if (actual == null) {
        throw RemoteSourceException('$base was not found${ref != null ? ' on $ref' : ''}.');
      }
      final dir = dirOf(actual);
      final isNetworks = actual.toLowerCase().endsWith(networksFileName);
      final rgb = isNetworks ? lowerToActual[join(dir, rgbEffectsFileName).toLowerCase()] : actual;
      if (rgb == null) {
        throw RemoteSourceException('No $rgbEffectsFileName next to $actual.');
      }
      return [
        ShowFolderCandidate(
          title: dir.isEmpty ? '/' : dir,
          rgbEffectsRef: rgb,
          networksRef: networksIn(dir),
          subtitle: _subtitle(networksIn(dir) != null, ref),
        ),
      ];
    }

    final prefix = base.isEmpty ? '' : '${base.toLowerCase()}/';
    final out = <ShowFolderCandidate>[];
    for (final p in paths) {
      final lower = p.toLowerCase();
      if (!lower.endsWith(rgbEffectsFileName)) continue;
      if (lower != rgbEffectsFileName && !lower.endsWith('/$rgbEffectsFileName')) continue;
      if (prefix.isNotEmpty && !lower.startsWith(prefix)) continue;
      final dir = dirOf(p);
      final net = networksIn(dir);
      out.add(ShowFolderCandidate(
        title: dir.isEmpty ? '/' : dir,
        rgbEffectsRef: p,
        networksRef: net,
        subtitle: _subtitle(net != null, ref),
      ));
    }

    if (out.isEmpty) {
      throw RemoteSourceException(
          'No $rgbEffectsFileName found${base.isEmpty ? '' : ' under $base'}${ref != null ? ' on $ref' : ''}.');
    }

    // Shallowest folders first (the live show folder rather than backups),
    // then alphabetically.
    int depth(String s) => '/'.allMatches(s).length;
    out.sort((a, b) {
      final d = depth(a.rgbEffectsRef).compareTo(depth(b.rgbEffectsRef));
      return d != 0 ? d : a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return out;
  }

  static String _subtitle(bool hasNetworks, String? ref) => [
        if (ref != null) ref,
        hasNetworks ? 'rgbeffects + networks' : 'rgbeffects only',
      ].join(' · ');

  /// Downloads the files for [candidate].
  Future<List<RemoteFile>> download(GitHubLocation loc, ShowFolderCandidate candidate) async {
    final files = <RemoteFile>[];
    for (final path in [candidate.rgbEffectsRef, ?candidate.networksRef]) {
      files.add(RemoteFile(path.split('/').last, await downloadFile(loc, path)));
    }
    return files;
  }

  /// Downloads one file's raw bytes (the contents API serves up to 100 MB).
  Future<List<int>> downloadFile(GitHubLocation loc, String path) async {
    final url = StringBuffer(
        '$_api/repos/${Uri.encodeComponent(loc.owner)}/${Uri.encodeComponent(loc.repo)}'
        '/contents/${_encodePath(path)}');
    if (loc.ref != null && loc.ref!.isNotEmpty) {
      url.write('?ref=${Uri.encodeQueryComponent(loc.ref!)}');
    }
    final res = await _get(url.toString(), raw: true);
    return res.bodyBytes;
  }

  void close() => _client.close();
}
