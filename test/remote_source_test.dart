import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xlights_layout/services/remote/github_source.dart';
import 'package:xlights_layout/services/remote/google_drive_source.dart';
import 'package:xlights_layout/services/remote/remote_source.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  group('GitHubLocation.parse', () {
    test('owner/repo', () {
      final l = GitHubLocation.parse('scott/show')!;
      expect([l.owner, l.repo, l.ref, l.path], ['scott', 'show', null, '']);
    });

    test('owner/repo/path', () {
      final l = GitHubLocation.parse('scott/show/2025 Show/')!;
      expect(l.path, '2025 Show');
      expect(l.ref, isNull);
    });

    test('github.com repo URL with .git', () {
      final l = GitHubLocation.parse('https://github.com/scott/show.git')!;
      expect([l.owner, l.repo, l.path], ['scott', 'show', '']);
    });

    test('tree URL with ref and encoded path', () {
      final l = GitHubLocation.parse('https://github.com/scott/show/tree/main/Shows/My%20House')!;
      expect([l.ref, l.path], ['main', 'Shows/My House']);
    });

    test('blob URL to a file', () {
      final l = GitHubLocation.parse('github.com/scott/show/blob/v2/xlights_rgbeffects.xml')!;
      expect([l.ref, l.path], ['v2', 'xlights_rgbeffects.xml']);
    });

    test('raw URL with refs/heads', () {
      final l = GitHubLocation.parse(
          'https://raw.githubusercontent.com/scott/show/refs/heads/dev/a/xlights_networks.xml')!;
      expect([l.ref, l.path], ['dev', 'a/xlights_networks.xml']);
    });

    test('rejects other hosts and junk', () {
      expect(GitHubLocation.parse('https://gitlab.com/a/b'), isNull);
      expect(GitHubLocation.parse('justone'), isNull);
      expect(GitHubLocation.parse('  '), isNull);
    });
  });

  group('GitHubSource.candidatesFromPaths', () {
    final paths = {
      'README.md',
      'xlights_rgbeffects.xml',
      'xlights_networks.xml',
      'Backup/2025-01-01/xlights_rgbeffects.xml',
      'Halloween/xLights_RGBEffects.xml',
      'Halloween/not_xlights_rgbeffects.xml',
    };

    test('finds all folders, shallowest first, case-insensitive', () {
      final c = GitHubSource.candidatesFromPaths(paths, '');
      expect(c.map((e) => e.title), ['/', 'Halloween', 'Backup/2025-01-01']);
      expect(c.first.networksRef, 'xlights_networks.xml');
      expect(c[1].rgbEffectsRef, 'Halloween/xLights_RGBEffects.xml');
      expect(c[1].hasNetworks, isFalse);
    });

    test('restricts to base path', () {
      final c = GitHubSource.candidatesFromPaths(paths, '/Backup/');
      expect(c.single.title, 'Backup/2025-01-01');
    });

    test('direct link to networks file resolves sibling rgbeffects', () {
      final c = GitHubSource.candidatesFromPaths(paths, 'xlights_networks.xml');
      expect(c.single.rgbEffectsRef, 'xlights_rgbeffects.xml');
      expect(c.single.networksRef, 'xlights_networks.xml');
    });

    test('throws when nothing matches', () {
      expect(() => GitHubSource.candidatesFromPaths({'a.txt'}, ''),
          throwsA(isA<RemoteSourceException>()));
    });
  });

  group('GitHubSource over HTTP', () {
    test('resolves default branch, scans tree and downloads with token', () async {
      final seen = <String>[];
      final client = MockClient((req) async {
        seen.add(req.url.toString());
        expect(req.headers['Authorization'], 'Bearer tok');
        final path = req.url.path;
        if (path == '/repos/o/r') return _json({'default_branch': 'main'});
        if (path == '/repos/o/r/git/trees/main') {
          return _json({
            'truncated': false,
            'tree': [
              {'type': 'blob', 'path': 'show/xlights_rgbeffects.xml'},
              {'type': 'blob', 'path': 'show/xlights_networks.xml'},
              {'type': 'tree', 'path': 'show'},
            ],
          });
        }
        if (path.startsWith('/repos/o/r/contents/')) {
          expect(req.headers['Accept'], 'application/vnd.github.raw+json');
          return http.Response('<xml>${path.split('/').last}</xml>', 200);
        }
        return http.Response('nope', 404);
      });
      final gh = GitHubSource(client: client, token: 'tok');
      const loc = GitHubLocation(owner: 'o', repo: 'r');
      final c = await gh.findShowFolders(loc);
      expect(c.single.title, 'show');
      final files = await gh.download(loc, c.single);
      expect(files.map((f) => f.name), ['xlights_rgbeffects.xml', 'xlights_networks.xml']);
      expect(utf8.decode(files.last.bytes), '<xml>xlights_networks.xml</xml>');
    });

    test('404 without a token hints at private repos', () async {
      final gh = GitHubSource(client: MockClient((_) async => _json({'message': 'Not Found'}, 404)));
      expect(
        () => gh.findShowFolders(const GitHubLocation(owner: 'o', repo: 'r')),
        throwsA(isA<RemoteSourceException>()
            .having((e) => e.message, 'message', contains('private'))),
      );
    });
  });

  group('GoogleDriveSource', () {
    test('parseId handles share links and bare IDs', () {
      expect(GoogleDriveSource.parseId('https://drive.google.com/drive/folders/1AbCdEfGhIjK?usp=sharing'),
          '1AbCdEfGhIjK');
      expect(GoogleDriveSource.parseId('https://drive.google.com/file/d/1ZyXwVuTsRq/view'), '1ZyXwVuTsRq');
      expect(GoogleDriveSource.parseId('https://drive.google.com/open?id=1ZyXwVuTsRq'), '1ZyXwVuTsRq');
      expect(GoogleDriveSource.parseId('1ZyXwVuTsRq_-x'), '1ZyXwVuTsRq_-x');
      expect(GoogleDriveSource.parseId('hello world'), isNull);
    });

    test('search finds rgbeffects and sibling networks', () async {
      final client = MockClient((req) async {
        expect(req.headers['Authorization'], 'Bearer at');
        final q = req.url.queryParameters['q'] ?? '';
        if (req.url.path == '/drive/v3/files' && q.startsWith("name = 'xlights_rgbeffects.xml'")) {
          return _json({
            'files': [
              {'id': 'rgb1', 'name': 'xlights_rgbeffects.xml', 'parents': ['fold1'], 'modifiedTime': '2026-01-02T03:04:05Z'},
            ],
          });
        }
        if (req.url.path == '/drive/v3/files' && q.contains("'fold1' in parents")) {
          return _json({
            'files': [
              {'id': 'net1', 'name': 'xlights_networks.xml'},
            ],
          });
        }
        if (req.url.path == '/drive/v3/files/fold1') return _json({'name': '2026 Show'});
        if (req.url.path == '/drive/v3/files/rgb1' && req.url.queryParameters['alt'] == 'media') {
          return http.Response('<xrgb/>', 200);
        }
        if (req.url.path == '/drive/v3/files/net1' && req.url.queryParameters['alt'] == 'media') {
          return http.Response('<Networks/>', 200);
        }
        return http.Response('?', 500);
      });
      final drive = GoogleDriveSource(accessToken: 'at', client: client);
      final c = await drive.searchShowFolders();
      expect(c.single.title, '2026 Show');
      expect(c.single.networksRef, 'net1');
      final files = await drive.download(c.single);
      expect(files.map((f) => utf8.decode(f.bytes)), ['<xrgb/>', '<Networks/>']);
    });

    test('folder link lists its XML files', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/drive/v3/files/folderXYZ123') {
          return _json({'id': 'folderXYZ123', 'name': 'Show', 'mimeType': GoogleDriveSource.folderMimeType});
        }
        if (req.url.path == '/drive/v3/files') {
          return _json({
            'files': [
              {'id': 'r', 'name': 'xlights_rgbeffects.xml'},
            ],
          });
        }
        return http.Response('?', 500);
      });
      final drive = GoogleDriveSource(accessToken: 'at', client: client);
      final c = await drive.fromLink('https://drive.google.com/drive/folders/folderXYZ123');
      expect(c.single.rgbEffectsRef, 'r');
      expect(c.single.hasNetworks, isFalse);
    });

    test('401 becomes DriveAuthException', () async {
      final drive = GoogleDriveSource(
          accessToken: 'old', client: MockClient((_) async => http.Response('', 401)));
      expect(drive.searchShowFolders, throwsA(isA<DriveAuthException>()));
    });
  });
}
