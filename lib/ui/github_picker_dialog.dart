import 'package:flutter/material.dart';

import '../services/github_source.dart';
import '../services/github_token_store.dart';

/// A file fetched from GitHub, ready to hand to [LayoutStore].
class GitHubPickerResult {
  GitHubPickerResult(this.bytes, this.name);

  final List<int> bytes;
  final String name;
}

/// Shows the GitHub browse picker and returns the chosen file, or null if
/// the user cancelled.
Future<GitHubPickerResult?> showGitHubPickerDialog(BuildContext context) {
  return showDialog<GitHubPickerResult>(
    context: context,
    builder: (_) => const GitHubPickerDialog(),
  );
}

enum _Stage { token, repos, browsing }

/// Walks the user through: paste a PAT -> pick a repo -> browse folders ->
/// pick a file. Reused for both the rgbeffects and networks file.
class GitHubPickerDialog extends StatefulWidget {
  const GitHubPickerDialog({super.key});

  @override
  State<GitHubPickerDialog> createState() => _GitHubPickerDialogState();
}

class _GitHubPickerDialogState extends State<GitHubPickerDialog> {
  final _tokenController = TextEditingController();
  final _searchController = TextEditingController();

  GitHubSource? _source;
  _Stage _stage = _Stage.token;
  bool _busy = false;
  bool _obscureToken = true;
  bool _remember = true;
  String? _error;

  List<GitHubRepo> _repos = [];
  String _repoFilter = '';

  GitHubRepo? _repo;
  List<GitHubEntry> _entries = [];
  final List<String> _pathStack = [];

  @override
  void initState() {
    super.initState();
    _loadSavedToken();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedToken() async {
    final saved = await GitHubTokenStore.read();
    if (saved != null && saved.isNotEmpty && mounted) {
      _tokenController.text = saved;
      await _connect();
    }
  }

  Future<void> _connect() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _error = 'Enter a personal access token.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final source = GitHubSource(token);
    try {
      await source.verifyToken();
      final repos = await source.listRepos();
      if (_remember) await GitHubTokenStore.save(token);
      if (!mounted) return;
      setState(() {
        _source = source;
        _repos = repos;
        _stage = _Stage.repos;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  Future<void> _forgetToken() async {
    await GitHubTokenStore.clear();
    setState(() {
      _tokenController.clear();
      _error = null;
    });
  }

  Future<void> _openRepo(GitHubRepo repo) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final entries =
          await _source!.listContents(repo.fullName, '', repo.defaultBranch);
      if (!mounted) return;
      setState(() {
        _repo = repo;
        _pathStack.clear();
        _entries = entries;
        _stage = _Stage.browsing;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  Future<void> _openEntry(GitHubEntry entry) async {
    if (entry.isDir) {
      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        final entries = await _source!
            .listContents(_repo!.fullName, entry.path, _repo!.defaultBranch);
        if (!mounted) return;
        setState(() {
          _pathStack.add(entry.name);
          _entries = entries;
          _busy = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = '$e';
          _busy = false;
        });
      }
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await _source!
          .downloadFile(_repo!.fullName, entry.path, _repo!.defaultBranch);
      if (!mounted) return;
      Navigator.of(context).pop(GitHubPickerResult(bytes, entry.name));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  Future<void> _goUp() async {
    if (_pathStack.isEmpty) {
      setState(() {
        _repo = null;
        _stage = _Stage.repos;
        _error = null;
      });
      return;
    }
    _pathStack.removeLast();
    final newPath = _pathStack.join('/');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final entries =
          await _source!.listContents(_repo!.fullName, newPath, _repo!.defaultBranch);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  String get _title => switch (_stage) {
        _Stage.token => 'Connect to GitHub',
        _Stage.repos => 'Choose a repository',
        _Stage.browsing => _repo == null
            ? 'Browse'
            : '${_repo!.fullName}${_pathStack.isEmpty ? '' : '/${_pathStack.join('/')}'}',
      };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_title, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            Expanded(
              child: _busy
                  ? const Center(child: CircularProgressIndicator())
                  : switch (_stage) {
                      _Stage.token => _buildTokenStage(),
                      _Stage.repos => _buildReposStage(),
                      _Stage.browsing => _buildBrowsingStage(),
                    },
            ),
          ],
        ),
      ),
      actions: [
        if (_stage == _Stage.repos || _stage == _Stage.browsing)
          TextButton(
            onPressed: _busy
                ? null
                : () {
                    if (_stage == _Stage.browsing) {
                      _goUp();
                    } else {
                      setState(() {
                        _stage = _Stage.token;
                        _error = null;
                      });
                    }
                  },
            child: const Text('Back'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildTokenStage() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Create a token with read-only access to the repo(s) you need '
            '(Settings → Developer settings → Personal access tokens on '
            'github.com) and paste it below. It is stored only in this '
            'browser.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _tokenController,
            obscureText: _obscureToken,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Personal access token',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscureToken ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscureToken = !_obscureToken),
              ),
            ),
            onSubmitted: (_) => _connect(),
          ),
          Row(
            children: [
              Checkbox(
                value: _remember,
                onChanged: (v) => setState(() => _remember = v ?? true),
              ),
              const Text('Remember this token on this device'),
            ],
          ),
          TextButton(
            onPressed: _forgetToken,
            child: const Text('Forget saved token'),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _connect, child: const Text('Connect')),
        ],
      ),
    );
  }

  Widget _buildReposStage() {
    final filtered = _repoFilter.isEmpty
        ? _repos
        : _repos
            .where((r) => r.fullName.toLowerCase().contains(_repoFilter.toLowerCase()))
            .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Filter repositories',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _repoFilter = v),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No matching repositories.'))
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final repo = filtered[i];
                    return ListTile(
                      leading: const Icon(Icons.folder_special_outlined),
                      title: Text(repo.fullName),
                      onTap: () => _openRepo(repo),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildBrowsingStage() {
    if (_entries.isEmpty) {
      return const Center(child: Text('This folder is empty.'));
    }
    return ListView.builder(
      itemCount: _entries.length,
      itemBuilder: (context, i) {
        final entry = _entries[i];
        final isXml = entry.name.toLowerCase().endsWith('.xml');
        return ListTile(
          leading: Icon(entry.isDir
              ? Icons.folder_outlined
              : (isXml ? Icons.description_outlined : Icons.insert_drive_file_outlined)),
          title: Text(entry.name),
          enabled: entry.isDir || isXml,
          onTap: () => _openEntry(entry),
        );
      },
    );
  }
}
