import 'dart:async';

import 'package:flutter/material.dart';

import '../services/remote/github_source.dart';
import '../services/remote/google_auth.dart';
import '../services/remote/google_drive_source.dart';
import '../services/remote/remote_prefs.dart';
import '../services/remote/remote_source.dart';

/// Shows the GitHub loader; resolves to the downloaded files, or `null` if
/// the user cancelled.
Future<List<RemoteFile>?> showGitHubLoadDialog(BuildContext context) =>
    showDialog<List<RemoteFile>>(context: context, builder: (_) => const GitHubLoadDialog());

/// Shows the Google Drive loader; resolves to the downloaded files, or `null`
/// if the user cancelled.
Future<List<RemoteFile>?> showDriveLoadDialog(BuildContext context) =>
    showDialog<List<RemoteFile>>(context: context, builder: (_) => const DriveLoadDialog());

class GitHubLoadDialog extends StatefulWidget {
  const GitHubLoadDialog({super.key});

  @override
  State<GitHubLoadDialog> createState() => _GitHubLoadDialogState();
}

class _GitHubLoadDialogState extends State<GitHubLoadDialog> {
  final _repo = TextEditingController();
  final _ref = TextEditingController();
  final _token = TextEditingController();
  bool _remember = false;
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  List<ShowFolderCandidate>? _candidates;
  GitHubLocation? _loc;

  @override
  void initState() {
    super.initState();
    RemotePrefs.loadGitHub().then((saved) {
      if (!mounted) return;
      setState(() {
        if (_repo.text.isEmpty) _repo.text = saved.repo;
        if (_ref.text.isEmpty) _ref.text = saved.ref;
        if (_token.text.isEmpty) _token.text = saved.token;
        _remember = saved.token.isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    _repo.dispose();
    _ref.dispose();
    _token.dispose();
    super.dispose();
  }

  GitHubSource _source() => GitHubSource(token: _token.text.trim());

  Future<void> _find() async {
    final parsed = GitHubLocation.parse(_repo.text);
    if (parsed == null) {
      setState(() => _error = 'Enter a repository as owner/repo or a github.com link.');
      return;
    }
    final ref = _ref.text.trim();
    final loc = ref.isEmpty ? parsed : parsed.copyWith(ref: ref);
    setState(() {
      _busy = true;
      _error = null;
      _candidates = null;
    });
    final source = _source();
    try {
      final found = await source.findShowFolders(loc);
      await RemotePrefs.saveGitHub(
        repo: _repo.text.trim(),
        ref: ref,
        token: _remember ? _token.text.trim() : null,
      );
      _loc = loc;
      if (found.length == 1) {
        await _download(found.single, source);
        return;
      }
      if (mounted) setState(() => _candidates = found);
    } on RemoteSourceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      source.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download(ShowFolderCandidate c, [GitHubSource? existing]) async {
    final source = existing ?? _source();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final files = await source.download(_loc!, c);
      if (mounted) Navigator.of(context).pop(files);
    } on RemoteSourceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (existing == null) source.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.code),
        SizedBox(width: 12),
        Text('Load from GitHub'),
      ]),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_candidates == null) ...[
                TextField(
                  controller: _repo,
                  enabled: !_busy,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Repository',
                    hintText: 'owner/repo, owner/repo/show-folder, or a github.com link',
                  ),
                  onSubmitted: (_) => _find(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ref,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Branch or tag (optional)',
                    hintText: 'Default branch',
                  ),
                  onSubmitted: (_) => _find(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _token,
                  enabled: !_busy,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Access token (needed for private repos)',
                    hintText: 'github_pat_…',
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show' : 'Hide',
                      icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  onSubmitted: (_) => _find(),
                ),
                const SizedBox(height: 6),
                Text(
                  'Use a fine-grained personal access token limited to this repository '
                  'with read-only "Contents" permission. It is sent only to api.github.com.',
                  style: theme.textTheme.bodySmall,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _remember,
                  onChanged: _busy ? null : (v) => setState(() => _remember = v ?? false),
                  title: const Text('Remember token on this device'),
                ),
              ] else ...[
                Text('Several show folders were found. Pick one:', style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                _CandidateList(candidates: _candidates!, enabled: !_busy, onPick: _download),
              ],
              if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
              if (_error != null) _ErrorText(_error!),
            ],
          ),
        ),
      ),
      actions: [
        if (_candidates != null)
          TextButton(
            onPressed: _busy ? null : () => setState(() => _candidates = null),
            child: const Text('Back'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (_candidates == null)
          FilledButton(
            onPressed: _busy ? null : _find,
            child: const Text('Load'),
          ),
      ],
    );
  }
}

class DriveLoadDialog extends StatefulWidget {
  const DriveLoadDialog({super.key});

  @override
  State<DriveLoadDialog> createState() => _DriveLoadDialogState();
}

class _DriveLoadDialogState extends State<DriveLoadDialog> {
  final _link = TextEditingController();
  final _auth = GoogleDriveAuth.instance;
  bool _busy = false;
  String? _error;
  List<ShowFolderCandidate>? _candidates;

  String? get _unavailable => GoogleDriveAuth.unavailableReason;

  @override
  void initState() {
    super.initState();
    if (_unavailable == null) {
      // Initialize now so the button press can open the consent popup
      // without an intervening await (browsers block delayed popups).
      unawaited(_auth.ensureInitialized().catchError((Object e) {
        if (mounted) setState(() => _error = 'Google sign-in failed to start: $e');
      }));
    }
  }

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  /// Runs [action] with a Drive client, prompting for sign-in when needed and
  /// retrying once if the cached token turns out to be stale.
  Future<T?> _withDrive<T>(Future<T> Function(GoogleDriveSource drive) action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        final token = await _auth.accessToken(forcePrompt: attempt > 0);
        final drive = GoogleDriveSource(accessToken: token);
        try {
          return await action(drive);
        } on DriveAuthException {
          _auth.invalidate();
          if (attempt > 0) rethrow;
        } finally {
          drive.close();
        }
      }
    } on RemoteSourceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      // GoogleSignInException (cancelled popup, misconfigured client, ...).
      if (mounted) setState(() => _error = 'Google sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return null;
  }

  Future<void> _search() async {
    final found = await _withDrive((d) => d.searchShowFolders());
    if (found != null && mounted) setState(() => _candidates = found);
  }

  Future<void> _openLink() async {
    if (GoogleDriveSource.parseId(_link.text) == null) {
      setState(() => _error = 'Paste a Google Drive folder or file link.');
      return;
    }
    final found = await _withDrive((d) => d.fromLink(_link.text));
    if (found == null || !mounted) return;
    if (found.length == 1) {
      await _download(found.single);
    } else {
      setState(() => _candidates = found);
    }
  }

  Future<void> _download(ShowFolderCandidate c) async {
    final files = await _withDrive((d) => d.download(c));
    if (files != null && mounted) Navigator.of(context).pop(files);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unavailable = _unavailable;
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.add_to_drive),
        SizedBox(width: 12),
        Text('Load from Google Drive'),
      ]),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (unavailable != null)
                Text(unavailable)
              else if (_candidates == null) ...[
                Text(
                  'Sign in with Google to find xlights_rgbeffects.xml in your Drive, '
                  'including files shared with you and shared drives. Access is read-only '
                  'and files are downloaded straight to this app.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _search,
                  icon: const Icon(Icons.search),
                  label: Text(_auth.cachedToken == null ? 'Sign in and search Drive' : 'Search Drive'),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('or', style: theme.textTheme.bodySmall),
                  ),
                  const Expanded(child: Divider()),
                ]),
                const SizedBox(height: 8),
                TextField(
                  controller: _link,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    labelText: 'Drive link to the show folder or XML file',
                    hintText: 'https://drive.google.com/drive/folders/…',
                    suffixIcon: IconButton(
                      tooltip: 'Open link',
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: _busy ? null : _openLink,
                    ),
                  ),
                  onSubmitted: (_) => _openLink(),
                ),
              ] else ...[
                Text(
                  _candidates!.length == 1 ? 'Show folder found:' : 'Pick a show folder (newest first):',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                _CandidateList(candidates: _candidates!, enabled: !_busy, onPick: _download),
              ],
              if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
              if (_error != null) _ErrorText(_error!),
            ],
          ),
        ),
      ),
      actions: [
        if (unavailable == null && _auth.cachedToken != null && _candidates == null)
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    await _auth.signOut();
                    if (mounted) setState(() {});
                  },
            child: const Text('Sign out'),
          ),
        if (_candidates != null)
          TextButton(
            onPressed: _busy ? null : () => setState(() => _candidates = null),
            child: const Text('Back'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(unavailable != null ? 'Close' : 'Cancel'),
        ),
      ],
    );
  }
}

class _CandidateList extends StatelessWidget {
  const _CandidateList({required this.candidates, required this.enabled, required this.onPick});

  final List<ShowFolderCandidate> candidates;
  final bool enabled;
  final void Function(ShowFolderCandidate) onPick;

  @override
  Widget build(BuildContext context) {
    // A plain Column (not a ListView): AlertDialog measures intrinsic width,
    // which lazy viewports can't report. The dialog content already scrolls.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final c in candidates)
          ListTile(
            enabled: enabled,
            leading: const Icon(Icons.folder),
            title: Text(c.title),
            subtitle: c.subtitle == null ? null : Text(c.subtitle!),
            onTap: () => onPick(c),
          ),
      ],
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
    );
  }
}
