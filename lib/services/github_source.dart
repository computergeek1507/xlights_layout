import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thrown when the GitHub API rejects a request (bad token, 404, rate limit).
class GitHubException implements Exception {
  GitHubException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A repository visible to the authenticated user.
class GitHubRepo {
  GitHubRepo({required this.fullName, required this.defaultBranch});

  final String fullName; // "owner/repo"
  final String defaultBranch;
}

/// One entry (file or directory) in a repo tree listing.
class GitHubEntry {
  GitHubEntry({required this.name, required this.path, required this.isDir});

  final String name;
  final String path;
  final bool isDir;
}

/// Minimal client for the parts of the GitHub REST API this app needs:
/// listing the user's repos, browsing a repo's file tree, and downloading a
/// file's contents. Authenticates with a personal access token.
class GitHubSource {
  GitHubSource(this.token, {http.Client? client})
      : _client = client ?? http.Client();

  final String token;
  final http.Client _client;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  /// Verifies the token works by fetching the authenticated user's login.
  Future<String> verifyToken() async {
    final res = await _client.get(
      Uri.https('api.github.com', '/user'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw GitHubException(_errorFor(res));
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['login'] as String? ?? '';
  }

  /// Lists repositories visible to the authenticated user (owned,
  /// collaborator, and org member repos), most recently updated first.
  Future<List<GitHubRepo>> listRepos() async {
    final repos = <GitHubRepo>[];
    var page = 1;
    while (true) {
      final res = await _client.get(
        Uri.https('api.github.com', '/user/repos', {
          'per_page': '100',
          'page': '$page',
          'sort': 'updated',
          'affiliation': 'owner,collaborator,organization_member',
        }),
        headers: _headers,
      );
      if (res.statusCode != 200) {
        throw GitHubException(_errorFor(res));
      }
      final items = jsonDecode(res.body) as List<dynamic>;
      for (final item in items) {
        final map = item as Map<String, dynamic>;
        repos.add(GitHubRepo(
          fullName: map['full_name'] as String,
          defaultBranch: map['default_branch'] as String? ?? 'main',
        ));
      }
      if (items.length < 100) break;
      page++;
    }
    return repos;
  }

  /// Lists the contents of [path] (empty string for repo root) within
  /// [fullName] ("owner/repo") at [ref] (branch/tag/sha).
  Future<List<GitHubEntry>> listContents(
    String fullName,
    String path,
    String ref,
  ) async {
    final res = await _client.get(
      Uri.https('api.github.com', '/repos/$fullName/contents/$path', {
        'ref': ref,
      }),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw GitHubException(_errorFor(res));
    }
    final decoded = jsonDecode(res.body);
    final items = decoded is List ? decoded : [decoded];
    final entries = [
      for (final item in items)
        GitHubEntry(
          name: (item as Map<String, dynamic>)['name'] as String,
          path: item['path'] as String,
          isDir: item['type'] == 'dir',
        ),
    ];
    entries.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  /// Downloads the raw bytes of a file at [path] within [fullName] at [ref].
  Future<List<int>> downloadFile(
    String fullName,
    String path,
    String ref,
  ) async {
    final res = await _client.get(
      Uri.https('api.github.com', '/repos/$fullName/contents/$path', {
        'ref': ref,
      }),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw GitHubException(_errorFor(res));
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final encoding = body['encoding'] as String?;
    final content = (body['content'] as String? ?? '').replaceAll('\n', '');
    if (encoding == 'base64') {
      return base64.decode(content);
    }
    throw GitHubException('Unexpected encoding "$encoding" for $path');
  }

  String _errorFor(http.Response res) {
    if (res.statusCode == 401) return 'GitHub rejected that token (401 Unauthorized).';
    if (res.statusCode == 403) {
      return 'GitHub denied access (403) — check token scopes or rate limits.';
    }
    if (res.statusCode == 404) return 'Not found on GitHub (404).';
    return 'GitHub API error ${res.statusCode}: ${res.body}';
  }
}
