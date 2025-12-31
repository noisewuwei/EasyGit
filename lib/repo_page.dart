import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'git_service.dart';
import 'ui/app_colors.dart';
import 'ui/window_controls.dart';
import 'utils/platform_utils.dart';
import 'widgets/commit_panel.dart';
import 'widgets/repo_toolbar.dart';
import 'widgets/repo_sidebar.dart';
import 'widgets/commit_history.dart';
import 'widgets/changes_and_diff.dart';
import 'ui/diff_utils.dart';

class RepoPage extends StatefulWidget {
  final String repoPath;
  const RepoPage({super.key, required this.repoPath});

  @override
  State<RepoPage> createState() => _RepoPageState();
}

class _RepoPageState extends State<RepoPage> {
  final _git = GitService();
  final _messageController = TextEditingController();
  final _diffScrollController = ScrollController();
  final _historyScrollController = ScrollController();
  static const List<String> _commitTypes = [
    'init',
    'feature',
    'fix',
    'refactor',
    'log',
    'perf',
    'test',
    'style',
    'upsub',
  ];

  bool _busy = false;
  bool _refreshing = false;
  Timer? _autoRefreshTimer;
  bool _autoRefreshEnabled = true;
  static const Duration _autoRefreshInterval = Duration(seconds: 15);
  static const int _commitPageSize = 20;
  bool _generatingCommitInfo = false;
  String _selectedCommitType = 'feature';

  List<GitChange> _changes = [];
  List<String> _branches = [];
  List<String> _remotes = [];
  String? _currentBranch;
  String? _selectedRemote;
  Map<String, List<String>> _remoteBranches = {};
  bool _remoteBranchesLoading = false;
  List<GitSubmodule> _submodules = [];
  Map<String, int> _branchPullCounts = {};
  Map<String, int> _branchPushCounts = {};

  GitChange? _selectedChange;
  bool _diffLoading = false;
  String? _diffText;

  List<GitCommit> _recentCommits = [];
  String? _selectedBranch;
  List<String> _tags = [];
  bool _commitOverlay = false;
  GitCommit? _selectedCommit;
  bool _commitDetailsLoading = false;
  String? _commitDetailsText;
  bool _loadingMoreCommits = false;
  bool _commitHasMore = true;
  int _commitLoadedCount = 0;
  bool _rebaseInProgress = false;

  @override
  void initState() {
    super.initState();
    _refreshAll();
    _startAutoRefresh();
    _historyScrollController.addListener(_onHistoryScroll);
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _messageController.dispose();
    _diffScrollController.dispose();
    _historyScrollController.dispose();
    super.dispose();
  }

  void _appendLog(String text) {
    final time = DateTime.now().toIso8601String().split('T').last.split('.').first;
    print('$time - $text');
  }

  Future<void> _refreshAll() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      if (!mounted) return;
      final path = widget.repoPath;
      final changes = await _git.status(path);
      final branches = await _git.branches(path);
      final current = await _git.currentBranch(path);
      final remotes = await _git.remotes(path);
      var selectedBranch = _selectedBranch;
      if (selectedBranch == null || !branches.contains(selectedBranch)) {
        selectedBranch = current;
      }
      final history = await _git.recentCommits(path, branch: selectedBranch, limit: _commitPageSize, skip: 0);
      final tags = await _git.tags(path);
      final submodules = await _git.submodules(path);
      final aheadBehind = await _git.branchAheadBehind(path);
      final rebaseFlag = await _git.isRebaseInProgress(path);

      final nextSelection = _matchChange(changes, _selectedChange) ?? (changes.isNotEmpty ? changes.first : null);

      if (!mounted) return;
      final prevSelectedCommit = _selectedCommit;
      setState(() {
        _changes = changes;
        _branches = branches;
        _currentBranch = current;
        _selectedBranch = selectedBranch;
        _tags = tags;
        _remotes = remotes;
        _branchPullCounts = {for (final e in aheadBehind.entries) e.key: e.value.pull};
        _branchPushCounts = {for (final e in aheadBehind.entries) e.key: e.value.push};
        _recentCommits = history;
        _commitLoadedCount = history.length;
        _commitHasMore = history.length == _commitPageSize;
        _loadingMoreCommits = false;
        _submodules = submodules;
        _rebaseInProgress = rebaseFlag;
        if (_remotes.isNotEmpty && (_selectedRemote == null || !_remotes.contains(_selectedRemote))) {
          _selectedRemote = _remotes.first;
          // prefetch branches for the default remote so they show immediately
          _remoteBranches.clear();
          _loadRemoteBranches(_selectedRemote!);
        }
        if (nextSelection == null) {
          _selectedChange = null;
          _diffText = null;
          _diffLoading = false;
        } else {
          _selectedChange = nextSelection;
        }
        if (prevSelectedCommit != null) {
          final match = history.where((c) => c.hash == prevSelectedCommit.hash).toList();
          if (match.isNotEmpty) {
            _selectedCommit = match.first;
          } else {
            _selectedCommit = null;
            _commitDetailsText = null;
          }
        }
      });

      if (nextSelection != null) {
        await _previewChange(nextSelection, force: true);
      }
    } catch (e) {
      _appendLog('Refresh failed: $e');
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _loadMoreCommits() async {
    if (_loadingMoreCommits || !_commitHasMore) return;
    _loadingMoreCommits = true;
    try {
      final path = widget.repoPath;
      final branch = _selectedBranch;
      final more = await _git.recentCommits(path, branch: branch, limit: _commitPageSize, skip: _commitLoadedCount);
      if (!mounted || more.isEmpty) {
        _commitHasMore = false;
        return;
      }
      setState(() {
        _recentCommits.addAll(more);
        _commitLoadedCount += more.length;
        _commitHasMore = more.length == _commitPageSize;
      });
    } catch (e) {
      _appendLog('Load more commits failed: $e');
    } finally {
      _loadingMoreCommits = false;
    }
  }

  void _onHistoryScroll() {
    if (!_historyScrollController.hasClients) return;
    final position = _historyScrollController.position;
    if (position.extentAfter < 200) {
      _loadMoreCommits();
    }
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    if (!_autoRefreshEnabled) return;
    _autoRefreshTimer = Timer.periodic(_autoRefreshInterval, (timer) async {
      if (!mounted || _busy || _refreshing) return;
      await _refreshAll();
    });
  }

  Future<void> _openRemoteUrl() async {
    if (_busy) return;
    final repoPath = widget.repoPath;
    String? remoteName = _selectedRemote;
    if (remoteName == null || !_remotes.contains(remoteName)) {
      if (_remotes.contains('origin')) {
        remoteName = 'origin';
      } else if (_remotes.isNotEmpty) {
        remoteName = _remotes.first;
      }
    }

    if (remoteName == null) {
      _appendLog('No remote configured to open.');
      return;
    }

    try {
      final url = await _git.remoteUrl(repoPath, remoteName);
      if (url == null || url.isEmpty) {
        _appendLog('Remote "$remoteName" has no URL.');
        return;
      }
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', url]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [url]);
      } else {
        await Process.start('xdg-open', [url]);
      }
    } catch (e) {
      _appendLog('Failed to open remote URL: $e');
    }
  }

  Future<void> _runGitOp(Future<String> Function() op) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final output = await op();
      _appendLog(output);
    } catch (e) {
      _appendLog('Error: $e');
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
      await _refreshAll();
    }
  }

  Future<void> _stage(GitChange change) => _runGitOp(() => _git.addFiles(widget.repoPath, [change.path]));
  Future<void> _unstage(GitChange change) => _runGitOp(() => _git.unstageFiles(widget.repoPath, [change.path]));
  Future<void> _stageAll() => _runGitOp(() => _git.addAll(widget.repoPath));

  Future<void> _unstageAll() async {
    final stagedPaths = _changes.where((c) => c.staged).map((c) => c.path).toList();
    if (stagedPaths.isEmpty) return;
    await _runGitOp(() => _git.unstageFiles(widget.repoPath, stagedPaths));
  }

  Future<void> _restoreChange(GitChange change) async {
    if (_busy) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Restore changes?'),
          content: Text('Restore (discard local changes to) "${change.path}"?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Restore')),
          ],
        );
      },
    );
    if (confirm != true) return;
    await _runGitOp(() => _git.restoreFile(widget.repoPath, change.path));
  }

  Future<void> _commit() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;
    await _runGitOp(() => _git.commit(widget.repoPath, message));
    _messageController.clear();
  }

  Future<void> _amendLastCommit() async {
    final message = await _promptAmendMessage();
    if (message == null) return;
    await _runGitOp(() => _git.amendLastCommit(widget.repoPath, message));
    _messageController.clear();
  }

  Future<String?> _promptAmendMessage() async {
    if (_busy || !mounted) return null;
    var initial = _messageController.text.trim();
    if (initial.isEmpty) {
      try {
        initial = await _git.lastCommitMessage(widget.repoPath);
      } catch (_) {
        initial = '';
      }
    }

    final ctrl = TextEditingController(text: initial);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Amend last commit'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Commit message',
            hintText: 'Leave empty to reuse previous message',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Amend')),
        ],
      ),
    );

    if (ok != true) return null;
    final value = ctrl.text.trim();
    _messageController.text = value;
    return value;
  }

  Future<void> _revertSelectedCommit() async {
    final c = _selectedCommit;
    if (c == null) return;
    await _runGitOp(() => _git.revertCommit(widget.repoPath, c.hash));
  }

  Future<void> _cherryPickSelectedCommit() async {
    final c = _selectedCommit;
    if (c == null) return;
    await _runGitOp(() => _git.cherryPick(widget.repoPath, c.hash));
  }

  Future<void> _resetToSelected(String mode) async {
    final c = _selectedCommit;
    if (c == null) return;
    await _runGitOp(() => _git.reset(widget.repoPath, c.hash, mode: mode));
  }

  Future<void> _stashSave() async {
    String msg = '';
    bool includeUntracked = true;
    bool keepIndex = false;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Stash save'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  decoration: const InputDecoration(labelText: 'Message (optional)'),
                  onChanged: (v) => msg = v,
                ),
                CheckboxListTile(
                  value: includeUntracked,
                  onChanged: (v) => includeUntracked = v ?? true,
                  title: const Text('Include untracked'),
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  value: keepIndex,
                  onChanged: (v) => keepIndex = v ?? false,
                  title: const Text('Keep index'),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save')),
          ],
        );
      },
    );
    if (ok != true) return;
    await _runGitOp(() => _git.stashSave(widget.repoPath, msg, includeUntracked: includeUntracked, keepIndex: keepIndex));
  }

  Future<void> _showStashDialog() async {
    if (!mounted) return;
    final stashes = await _git.stashList(widget.repoPath);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stashes'),
        content: SizedBox(
          width: 520,
          height: 360,
          child: stashes.isEmpty
              ? const Center(child: Text('No stashes'))
              : ListView.builder(
                  itemCount: stashes.length,
                  itemBuilder: (context, index) {
                    final s = stashes[index];
                    final name = s['name'] ?? '';
                    final msg = s['message'] ?? '';
                    return ListTile(
                      title: Text(name),
                      subtitle: Text(msg),
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          IconButton(
                            tooltip: 'Apply',
                            icon: const Icon(Icons.check, size: 18),
                            onPressed: () async {
                              Navigator.of(ctx).pop();
                              await _runGitOp(() => _git.stashApply(widget.repoPath, name));
                            },
                          ),
                          IconButton(
                            tooltip: 'Pop',
                            icon: const Icon(Icons.arrow_downward, size: 18),
                            onPressed: () async {
                              Navigator.of(ctx).pop();
                              await _runGitOp(() => _git.stashPop(widget.repoPath, name));
                            },
                          ),
                          IconButton(
                            tooltip: 'Drop',
                            icon: const Icon(Icons.delete_forever, size: 18),
                            onPressed: () async {
                              Navigator.of(ctx).pop();
                              await _runGitOp(() => _git.stashDrop(widget.repoPath, name));
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _runGitOp(() => _git.stashClear(widget.repoPath));
            },
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
  }

  Future<void> _startRebaseOnSelected() async {
    final c = _selectedCommit;
    if (c == null) return;
    await _runGitOp(() => _git.rebase(widget.repoPath, c.hash));
  }

  Future<void> _startRebaseOnBranch() async {
    String? branch = _currentBranch;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Rebase onto branch'),
          content: DropdownButtonFormField<String>(
            value: branch,
            items: _branches.map((b) => DropdownMenuItem<String>(value: b, child: Text(b))).toList(),
            onChanged: (v) => branch = v,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Rebase')),
          ],
        );
      },
    );
    if (ok != true || branch == null || branch!.isEmpty) return;
    await _runGitOp(() => _git.rebase(widget.repoPath, branch!));
  }

  Future<void> _rebaseContinue() async => _runGitOp(() => _git.rebaseContinue(widget.repoPath));
  Future<void> _rebaseSkip() async => _runGitOp(() => _git.rebaseSkip(widget.repoPath));
  Future<void> _rebaseAbort() async => _runGitOp(() => _git.rebaseAbort(widget.repoPath));

  Future<void> _showCreateTagDialog() async {
    if (_busy || !mounted) return;
    String name = '';
    String message = '';
    String target = _selectedCommit?.hash ?? _currentBranch ?? 'HEAD';
    bool pushAfter = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Create tag'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  decoration: const InputDecoration(labelText: 'Tag name'),
                  onChanged: (v) => name = v,
                  autofocus: true,
                ),
                TextField(
                  decoration: const InputDecoration(labelText: 'Message (optional, for annotated tag)'),
                  onChanged: (v) => message = v,
                  maxLines: 2,
                ),
                TextField(
                  decoration: const InputDecoration(labelText: 'Target (commit-ish)', hintText: 'HEAD'),
                  controller: TextEditingController(text: target),
                  onChanged: (v) => target = v,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: pushAfter,
                  onChanged: (v) => pushAfter = v ?? false,
                  title: const Text('Push to remote after creation'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Create')),
          ],
        );
      },
    );
    if (ok != true) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      _appendLog('Tag name cannot be empty.');
      return;
    }
    final remote = _selectedRemote ?? (_remotes.contains('origin') ? 'origin' : (_remotes.isNotEmpty ? _remotes.first : ''));
    await _runGitOp(() async {
      final createRes = await _git.createTag(widget.repoPath, trimmed, target: target.trim().isEmpty ? 'HEAD' : target.trim(), message: message);
      if (pushAfter && remote.isNotEmpty) {
        final pushRes = await _git.pushTag(widget.repoPath, remote, trimmed);
        return '$createRes\n$pushRes';
      }
      return createRes;
    });
  }

  Future<void> _pushTag(String tag) async {
    final remote = _selectedRemote ?? (_remotes.contains('origin') ? 'origin' : (_remotes.isNotEmpty ? _remotes.first : ''));
    if (remote.isEmpty) {
      _appendLog('No remote selected to push tag.');
      return;
    }
    await _runGitOp(() => _git.pushTag(widget.repoPath, remote, tag));
  }

  Future<void> _deleteTag(String tag) async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete tag?'),
        content: Text('Delete local tag "$tag"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await _runGitOp(() => _git.deleteTag(widget.repoPath, tag));
  }

  Future<void> _deleteRemoteTag(String tag) async {
    final remote = _selectedRemote ?? (_remotes.contains('origin') ? 'origin' : (_remotes.isNotEmpty ? _remotes.first : ''));
    if (remote.isEmpty) {
      _appendLog('No remote selected to delete tag.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete remote tag?'),
        content: Text('Delete remote tag "$tag" from $remote?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await _runGitOp(() => _git.deleteRemoteTag(widget.repoPath, remote, tag));
  }

  Future<void> _showChangelogDialog({String? fromTag}) async {
    if (_tags.isEmpty) {
      _appendLog('No tags available for changelog.');
      return;
    }
    final headLabel = 'HEAD';
    String? start = fromTag ?? (_tags.length > 1 ? _tags[_tags.length - 2] : _tags.first);
    String? end = headLabel;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Generate changelog'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'From tag'),
                  value: start,
                  items: _tags
                      .map((t) => DropdownMenuItem<String>(
                            value: t,
                            child: Text(t),
                          ))
                      .toList(),
                  onChanged: (v) => start = v,
                ),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'To tag or HEAD'),
                  value: end,
                  items: [..._tags, headLabel]
                      .map((t) => DropdownMenuItem<String>(
                            value: t,
                            child: Text(t),
                          ))
                      .toList(),
                  onChanged: (v) => end = v,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Generate')),
          ],
        );
      },
    );

    if (ok != true || start == null || end == null) return;
    if (start == end) {
      _appendLog('Tag range cannot be the same.');
      return;
    }
    final toValue = end == headLabel ? 'HEAD' : end;
    final res = await _git.changelogBetweenTags(widget.repoPath, start!, toValue!);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Changelog'),
        content: SizedBox(
          width: 520,
          height: 400,
          child: SingleChildScrollView(
            child: SelectableText(res, style: const TextStyle(fontFamily: 'Consolas', fontSize: 13)),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _handleToolbarAction(String action) async {
    switch (action) {
      case 'amend':
        await _amendLastCommit();
        break;
      case 'stash_save':
        await _stashSave();
        break;
      case 'stash_list':
        await _showStashDialog();
        break;
      case 'rebase_branch':
        await _startRebaseOnBranch();
        break;
      case 'rebase_continue':
        await _rebaseContinue();
        break;
      case 'rebase_skip':
        await _rebaseSkip();
        break;
      case 'rebase_abort':
        await _rebaseAbort();
        break;
    }
  }

  Future<void> _handleCommitAction(GitCommit commit, String action) async {
    setState(() => _selectedCommit = commit);
    switch (action) {
      case 'revert':
        await _runGitOp(() => _git.revertCommit(widget.repoPath, commit.hash));
        break;
      case 'cherry_pick':
        await _runGitOp(() => _git.cherryPick(widget.repoPath, commit.hash));
        break;
      case 'reset_soft':
        await _runGitOp(() => _git.reset(widget.repoPath, commit.hash, mode: 'soft'));
        break;
      case 'reset_mixed':
        await _runGitOp(() => _git.reset(widget.repoPath, commit.hash, mode: 'mixed'));
        break;
      case 'reset_hard':
        await _runGitOp(() => _git.reset(widget.repoPath, commit.hash, mode: 'hard'));
        break;
      case 'rebase_selected':
        await _runGitOp(() => _git.rebase(widget.repoPath, commit.hash));
        break;
    }
  }

  Future<void> _handleTagAction(String tag, String action) async {
    switch (action) {
      case 'checkout_tag':
        await _confirmCheckoutTag(tag);
        break;
      case 'push_tag':
        await _pushTag(tag);
        break;
      case 'delete_tag':
        await _deleteTag(tag);
        break;
      case 'delete_remote_tag':
        await _deleteRemoteTag(tag);
        break;
      case 'changelog_from_tag':
        await _showChangelogDialog(fromTag: tag);
        break;
    }
  }

  Future<void> _pull() => _runGitOp(() => _git.pull(widget.repoPath, remote: _selectedRemote, branch: _currentBranch));
  Future<void> _push() => _runGitOp(() => _git.push(
        widget.repoPath,
        remote: _selectedRemote,
        branch: _currentBranch,
        setUpstream: _selectedRemote != null && _currentBranch != null,
      ));
  Future<void> _pushBranch(String branch) => _runGitOp(() => _git.push(
        widget.repoPath,
        remote: 'origin',
        branch: branch,
        setUpstream: true,
      ));
  Future<void> _checkout(String branch) => _runGitOp(() => _git.checkout(widget.repoPath, branch));
  Future<void> _createBranch(String name, String? base) => _runGitOp(() async {
        final created = await _git.createBranch(widget.repoPath, name, startPoint: base);
        final checkout = await _git.checkout(widget.repoPath, name);
        return '$created\n$checkout';
      });
  Future<void> _deleteBranch(String branch) => _runGitOp(() => _git.deleteBranch(widget.repoPath, branch));

  Future<void> _selectBranch(String branch) async {
    setState(() {
      _selectedBranch = branch;
      _recentCommits = [];
      _selectedCommit = null;
      _commitDetailsText = null;
    });
    try {
      final history = await _git.recentCommits(widget.repoPath, branch: branch, limit: _commitPageSize, skip: 0);
      if (!mounted) return;
      if (_selectedBranch != branch) return;
      setState(() {
        _recentCommits = history;
        _commitLoadedCount = history.length;
        _commitHasMore = history.length == _commitPageSize;
        _loadingMoreCommits = false;
      });
    } catch (e) {
      _appendLog('Failed to load history for $branch: $e');
    }
  }

  void _toggleCommitOverlay() => setState(() => _commitOverlay = !_commitOverlay);

  Future<void> _showHunkDialog() async {
    if (_busy || _selectedChange == null) return;
    final change = _selectedChange!;
    final hunks = await _git.hunks(widget.repoPath, change.path, staged: change.staged);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Hunks: ${change.path}'),
          content: SizedBox(
            width: 720,
            height: 420,
            child: hunks.isEmpty
                ? const Center(child: Text('No hunks found'))
                : ListView.builder(
                    itemCount: hunks.length,
                    itemBuilder: (context, index) {
                      final h = hunks[index];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(h.header, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                              const SizedBox(height: 6),
                              Container(
                                color: Colors.black,
                                padding: const EdgeInsets.all(8),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: SelectableText.rich(
                                    TextSpan(children: buildDiffSpans(h.patch, baseStyle: const TextStyle(fontFamily: 'Consolas', fontSize: 12, color: Colors.white))),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: [
                                  if (!change.staged)
                                    OutlinedButton.icon(
                                      icon: const Icon(Icons.add, size: 16),
                                      label: const Text('Stage hunk'),
                                      onPressed: _busy
                                          ? null
                                          : () async {
                                              Navigator.of(ctx).pop();
                                              await _runGitOp(() => _git.applyPatchToIndex(widget.repoPath, h.patch));
                                            },
                                    ),
                                  if (change.staged)
                                    OutlinedButton.icon(
                                      icon: const Icon(Icons.undo, size: 16),
                                      label: const Text('Unstage hunk'),
                                      onPressed: _busy
                                          ? null
                                          : () async {
                                              Navigator.of(ctx).pop();
                                              await _runGitOp(() => _git.applyPatchToIndex(widget.repoPath, h.patch, reverse: true));
                                            },
                                    ),
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.delete_sweep, size: 16),
                                    label: const Text('Discard hunk'),
                                    onPressed: _busy
                                        ? null
                                        : () async {
                                            Navigator.of(ctx).pop();
                                            await _runGitOp(() => _git.applyPatchToWorktree(widget.repoPath, h.patch, reverse: true));
                                          },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))],
        );
      },
    );
  }

  Future<void> _loadRemoteBranches(String remote) async {
    if (remote.isEmpty) return;
    if (_remoteBranches.containsKey(remote)) return;
    setState(() => _remoteBranchesLoading = true);
    try {
      final branches = await _git.remoteBranches(widget.repoPath);
      if (!mounted) return;
      // filter to the selected remote
      final filtered = branches.where((b) => b.startsWith('$remote/')).toList();
      setState(() {
        _remoteBranches[remote] = filtered;
      });
    } catch (e) {
      _appendLog('Failed to load remote branches: $e');
    } finally {
      if (!mounted) return;
      setState(() => _remoteBranchesLoading = false);
    }
  }

  Future<void> _checkoutRemoteBranch(String remoteBranch) async {
    // remoteBranch is like 'origin/feature/x'
    final parts = remoteBranch.split('/');
    if (parts.length < 2) return;
    final remote = parts.first;
    final branch = parts.sublist(1).join('/');
    await _runGitOp(() => _git.checkoutRemoteBranch(widget.repoPath, remote, branch));
  }

  Future<void> _confirmCheckoutRemoteBranch(String remoteBranch) async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Checkout Remote Branch'),
        content: Text('Checkout "$remoteBranch" to a local branch?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Checkout')),
        ],
      ),
    );
    if (ok == true) {
      await _checkoutRemoteBranch(remoteBranch);
    }
  }

  Future<void> _mergeIntoCurrent(String sourceBranch) async {
    if (_currentBranch == null) return;
    if (sourceBranch == _currentBranch) {
      _appendLog('Cannot merge a branch into itself.');
      return;
    }
    await _runGitOp(() async {
      final res = await _git.merge(widget.repoPath, sourceBranch);
      final conflicts = await _git.hasConflicts(widget.repoPath);
      if (conflicts && mounted) {
        await _prepareConflictCommitMessage(sourceBranch);
        _showConflictDialog();
      }
      return res;
    });
  }

  Future<void> _prepareConflictCommitMessage(String sourceBranch) async {
    final conflicts = await _git.conflictPaths(widget.repoPath);
    final target = _currentBranch ?? 'current';
    final buffer = StringBuffer();
    buffer.writeln("Merge branch '$sourceBranch' into $target");
    if (conflicts.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('# Conflicts:');
      for (final p in conflicts) {
        buffer.writeln('#\t$p');
      }
    }
    if (!mounted) return;
    setState(() {
      _commitOverlay = true;
      _messageController.text = buffer.toString();
    });
  }

  Future<void> _resolveConflictOurs(GitChange change) async {
    await _runGitOp(() async {
      final res = await _git.resolveConflictOurs(widget.repoPath, change.path);
      final conflicts = await _git.hasConflicts(widget.repoPath);
      if (conflicts && mounted) _showConflictDialog();
      return res;
    });
  }

  Future<void> _resolveConflictTheirs(GitChange change) async {
    await _runGitOp(() async {
      final res = await _git.resolveConflictTheirs(widget.repoPath, change.path);
      final conflicts = await _git.hasConflicts(widget.repoPath);
      if (conflicts && mounted) _showConflictDialog();
      return res;
    });
  }

  Future<void> _markConflictResolved(GitChange change) async {
    await _runGitOp(() => _git.markConflictResolved(widget.repoPath, change.path));
  }

  Future<void> _updateSubmodules() async {
    await _runGitOp(() => _git.updateSubmodules(widget.repoPath));
  }

  void _showConflictDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Merge conflicts detected'),
          content: const Text('Resolve the conflicts before committing. Conflict files are marked in Unstaged Changes.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
          ],
        );
      },
    );
  }

  Future<void> _confirmCheckoutTag(String tag) async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Checkout Tag'),
        content: Text('Checkout tag "$tag" (detached HEAD)?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Checkout')),
        ],
      ),
    );
    if (ok == true) {
      await _checkout(tag);
    }
  }

  Future<void> _selectRef(String ref) async {
    // Reuse branch selection logic; git log accepts tags and remote refs too.
    await _selectBranch(ref);
  }

  Future<void> _openGitBash() async {
    if (_busy) return;
    try {
      if (Platform.isWindows) {
        final candidates = [
          r'C:\\Program Files\\Git\\git-bash.exe',
          r'C:\\Program Files (x86)\\Git\\git-bash.exe',
          'git-bash.exe',
        ];
        String? exe;
        for (final c in candidates) {
          if (await File(c).exists()) {
            exe = c;
            break;
          }
        }
        exe ??= 'git-bash.exe';
        await Process.start(exe, [], workingDirectory: widget.repoPath);
      } else {
        await Process.start('bash', [], workingDirectory: widget.repoPath);
      }
    } catch (e) {
      _appendLog('Failed to open Git Bash: $e');
    }
  }

  Future<void> _openSettings() async {
    if (_busy) return;
    final repoPath = widget.repoPath;

    // Fetch current data.
    final remoteNames = await _git.remotes(repoPath);
    final remoteMap = <String, String>{};
    for (final r in remoteNames) {
      remoteMap[r] = await _git.remoteUrl(repoPath, r) ?? '';
    }

    final globalName = await _git.getConfig(repoPath, 'user.name', global: true) ?? '';
    final globalEmail = await _git.getConfig(repoPath, 'user.email', global: true) ?? '';
    final localName = await _git.getConfig(repoPath, 'user.name');
    final localEmail = await _git.getConfig(repoPath, 'user.email');
    bool useGlobal = true;

    final nameCtrl = TextEditingController(text: localName ?? '');
    final emailCtrl = TextEditingController(text: localEmail ?? '');

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) {
        bool saving = false;
        Map<String, String> remotesState = Map.of(remoteMap);
        bool useGlobalState = useGlobal;
        bool autoRefreshState = _autoRefreshEnabled;

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            Future<void> addOrEditRemote({String? name, String? url}) async {
              final nameC = TextEditingController(text: name ?? '');
              final urlC = TextEditingController(text: url ?? '');
              final isEdit = name != null;
              final ok = await showDialog<bool>(
                context: context,
                builder: (c2) {
                  return AlertDialog(
                    title: Text(isEdit ? 'Edit Remote' : 'Add Remote'),
                    content: SizedBox(
                      width: 380,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Name'), enabled: !isEdit),
                          TextField(controller: urlC, decoration: const InputDecoration(labelText: 'URL')),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(c2).pop(false), child: const Text('Cancel')),
                      ElevatedButton(onPressed: () => Navigator.of(c2).pop(true), child: const Text('Save')),
                    ],
                  );
                },
              );
              if (ok != true) return;
              final newName = nameC.text.trim();
              final newUrl = urlC.text.trim();
              if (newName.isEmpty || newUrl.isEmpty) return;
              setStateDialog(() => saving = true);
              try {
                final res = isEdit
                    ? await _git.setRemoteUrl(repoPath, newName, newUrl)
                    : await _git.addRemote(repoPath, newName, newUrl);
                _appendLog(res);
                setStateDialog(() {
                  remotesState[newName] = newUrl;
                  saving = false;
                });
              } finally {
                setStateDialog(() => saving = false);
              }
            }

            Future<void> removeRemote(String name) async {
              setStateDialog(() => saving = true);
              try {
                final res = await _git.removeRemote(repoPath, name);
                _appendLog(res);
                setStateDialog(() {
                  remotesState.remove(name);
                  saving = false;
                });
              } finally {
                setStateDialog(() => saving = false);
              }
            }

            Future<void> saveUserConfig() async {
              setStateDialog(() => saving = true);
              try {
                if (useGlobalState) {
                  await _git.unsetConfig(repoPath, 'user.name');
                  await _git.unsetConfig(repoPath, 'user.email');
                } else {
                  await _git.setConfig(repoPath, 'user.name', nameCtrl.text.trim());
                  await _git.setConfig(repoPath, 'user.email', emailCtrl.text.trim());
                }
              } finally {
                setStateDialog(() => saving = false);
              }
            }

            return AlertDialog(
              title: const Text('Settings'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Remotes', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ...remotesState.entries.map(
                        (e) => ListTile(
                          dense: true,
                          title: Text(e.key),
                          subtitle: Text(e.value.isEmpty ? '(no url)' : e.value),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                onPressed: saving ? null : () => addOrEditRemote(name: e.key, url: e.value),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, size: 18),
                                onPressed: saving ? null : () => removeRemote(e.key),
                              ),
                            ],
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: saving ? null : () => addOrEditRemote(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Remote'),
                      ),
                      const Divider(height: 24),
                      const Text('User Info', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Auto refresh'),
                        subtitle: const Text('Refresh repository status every 15 seconds'),
                        value: autoRefreshState,
                        onChanged: saving
                            ? null
                            : (v) {
                                setStateDialog(() => autoRefreshState = v);
                              },
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Use global user config'),
                        subtitle: Text('Global: ${globalName.isEmpty ? "(unset)" : globalName} / ${globalEmail.isEmpty ? "(unset)" : globalEmail}'),
                        value: useGlobalState,
                        onChanged: saving
                            ? null
                            : (v) {
                                setStateDialog(() => useGlobalState = v ?? true);
                              },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: nameCtrl,
                        enabled: !useGlobalState && !saving,
                        decoration: const InputDecoration(labelText: 'Full Name'),
                      ),
                      TextField(
                        controller: emailCtrl,
                        enabled: !useGlobalState && !saving,
                        decoration: const InputDecoration(labelText: 'Email'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Close'),
                ),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          await saveUserConfig();
                          if (mounted) {
                            setState(() {
                              _autoRefreshEnabled = autoRefreshState;
                            });
                            if (_autoRefreshEnabled) {
                              _startAutoRefresh();
                            } else {
                              _autoRefreshTimer?.cancel();
                              _autoRefreshTimer = null;
                            }
                            Navigator.of(ctx).pop(remotesState);
                          }
                        },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    await _refreshAll();
  }

  @override
  Widget build(BuildContext context) {
    final repoName = widget.repoPath.split(Platform.pathSeparator).last;
    final unstaged = _changes.where((c) => !c.staged).toList();
    final staged = _changes.where((c) => c.staged).toList();
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: Platform.isMacOS ? 0 : (canPop ? 48 : 0),
        leading: Platform.isMacOS
            ? null
            : canPop
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                  )
                : null,
        titleSpacing: 0,
        centerTitle: false,
        title: isDesktop
            ? const SizedBox.shrink()
            : Text(repoName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        flexibleSpace: isDesktop
            ? Stack(
                children: [
                  const Positioned.fill(child: DragToMoveArea(child: SizedBox.expand())),
                  // Center the repo name independently of leading/actions widths.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 72),
                          child: Text(
                            repoName,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : null,
        backgroundColor: AppColors.panel,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
        actions: [
          if (Platform.isMacOS && canPop)
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          if (isDesktop && !Platform.isMacOS) const WindowControls(),
        ],
      ),
      body: Row(
        children: [
          RepoSidebar(
            branches: _branches,
            selectedBranch: _selectedBranch,
            currentBranch: _currentBranch,
            remotes: _remotes,
            selectedRemote: _selectedRemote,
            remoteBranches: _remoteBranches,
            remoteBranchesLoading: _remoteBranchesLoading,
            submodules: _submodules,
            repoPath: widget.repoPath,
            branchPullCounts: _branchPullCounts,
            branchPushCounts: _branchPushCounts,
            tags: _tags,
            onCreateTag: _showCreateTagDialog,
            onShowChangelog: _showChangelogDialog,
            onTagAction: _handleTagAction,
            onOpenSubmodule: (p) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RepoPage(repoPath: p))),
            onUpdateSubmodules: () => _updateSubmodules(),
            onSelectBranch: (b) => _selectBranch(b),
            onCheckoutBranch: (b) => _checkout(b),
            onShowBranchContextMenu: (b, isCurrent, pos) => _showBranchContextMenu(b, isCurrent, pos),
            onCheckoutRemoteBranch: (rb) => _confirmCheckoutRemoteBranch(rb),
            onSelectRemoteBranch: (rb) => _selectRef(rb),
            onSelectTag: (t) => _selectRef(t),
            onCheckoutTag: (t) => _confirmCheckoutTag(t),
          ),
          Expanded(
            child: Column(
              children: [
                RepoToolbar(
                  currentBranch: _currentBranch,
                  selectedRemote: _selectedRemote,
                  busy: _busy,
                  commitOverlay: _commitOverlay,
                  changeCount: _changes.length,
                  onCreateBranch: _showCreateBranchDialog,
                  onPull: _pull,
                  onPush: _push,
                  onToggleCommitOverlay: _toggleCommitOverlay,
                  onOpenRemote: _openRemoteUrl,
                  onOpenSettings: _openSettings,
                  onOpenShell: _openGitBash,
                  onRefresh: _refreshAll,
                  onMoreAction: _handleToolbarAction,
                  rebaseInProgress: _rebaseInProgress,
                ),
                if (_commitOverlay) ...[
                  SizedBox(
                    height: 180,
                    child: CommitHistoryPanel(
                      recentCommits: _recentCommits,
                      showDetails: false,
                      selectedCommit: _selectedCommit,
                      onSelectCommit: _loadCommitDetails,
                      onCommitAction: _handleCommitAction,
                      detailsLoading: _commitDetailsLoading,
                      detailsText: _commitDetailsText,
                      diffScrollController: _diffScrollController,
                      historyScrollController: _historyScrollController,
                    ),
                  ),
                  Expanded(
                    child: ChangesAndDiff(
                      unstaged: unstaged,
                      staged: staged,
                      selectedChange: _selectedChange,
                      diffLoading: _diffLoading,
                      diffText: _diffText,
                      diffScrollController: _diffScrollController,
                      onRestoreUnstaged: (c) => _restoreChange(c),
                      onResolveOurs: (c) => _resolveConflictOurs(c),
                      onResolveTheirs: (c) => _resolveConflictTheirs(c),
                      onMarkResolved: (c) => _markConflictResolved(c),
                      onPreviewChange: (c) => _previewChange(c),
                      onStage: (c) => _stage(c),
                      onUnstage: (c) => _unstage(c),
                      onStageAll: _stageAll,
                      onUnstageAll: _unstageAll,
                      busy: _busy,
                      onOpenHunks: _showHunkDialog,
                    ),
                  ),
                  Container(height: 1, color: AppColors.border),
                  SizedBox(
                    height: 220,
                    child: CommitPanel(
                      messageController: _messageController,
                      commitTypes: _commitTypes,
                      selectedCommitType: _selectedCommitType,
                      onSelectedCommitTypeChanged: (v) => setState(() => _selectedCommitType = v),
                      generating: _generatingCommitInfo,
                      busy: _busy,
                      onGenerate: _generateCommitInfo,
                      onCommit: _commit,
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: CommitHistoryPanel(
                      recentCommits: _recentCommits,
                      showDetails: true,
                      selectedCommit: _selectedCommit,
                      onSelectCommit: _loadCommitDetails,
                      onCommitAction: _handleCommitAction,
                      detailsLoading: _commitDetailsLoading,
                      detailsText: _commitDetailsText,
                      diffScrollController: _diffScrollController,
                      historyScrollController: _historyScrollController,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  GitChange? _matchChange(List<GitChange> list, GitChange? target) {
    if (target == null) return null;
    GitChange? fallback;
    for (final change in list) {
      if (change.path != target.path) continue;
      if (change.staged == target.staged) {
        return change;
      }
      fallback ??= change;
    }
    return fallback;
  }

  Future<void> _previewChange(GitChange change, {bool force = false}) async {
    final sameSelection = _selectedChange != null &&
        _selectedChange!.path == change.path &&
        _selectedChange!.staged == change.staged;
    if (!force && sameSelection && _diffText != null && !_diffLoading) {
      return;
    }
    setState(() {
      _selectedChange = change;
      _diffLoading = true;
      _diffText = null;
    });
    try {
      final diff = await _git.diffFile(widget.repoPath, change);
      if (!mounted) return;
      setState(() {
        _diffLoading = false;
        _diffText = diff;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _diffLoading = false;
        _diffText = 'Failed to load diff: $e';
      });
    }
  }

  

  

  

  

  

  

  

  

  Future<String?> _getDeepseekApiKey() async {
    final envKey = Platform.environment['DEEPSEEK_API_KEY'];
    if (envKey != null && envKey.trim().isNotEmpty) return envKey.trim();
    try {
      final f = File('.env');
      if (!await f.exists()) return null;
      final contents = await f.readAsLines();
      for (final line in contents) {
        final trimmed = line.trim();
        if (trimmed.startsWith('DEEPSEEK_API_KEY=')) {
          return trimmed.split('=')[1].trim();
        }
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> _callDeepseek(String prompt) async {
    final key = await _getDeepseekApiKey();
    if (key == null) {
      _appendLog('Deepseek API key not found in environment or .env');
      return null;
    }

    final uri = Uri.parse('https://api.deepseek.com/chat/completions');
    try {
      final httpClient = HttpClient();
      final req = await httpClient.postUrl(uri);
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('Authorization', 'Bearer $key');
      final body = jsonEncode({
        'model': 'deepseek-chat',
        'messages': [
          {'role': 'system', 'content': 'You are a helpful assistant that generates concise commit message in JSON.'},
          {'role': 'user', 'content': prompt}
        ],
        'stream': false,
      });
      req.add(utf8.encode(body));
      final resp = await req.close();
      final respBody = await resp.transform(utf8.decoder).join();
      httpClient.close();
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        _appendLog('Deepseek API error: ${resp.statusCode} ${respBody}');
        return null;
      }
      final decoded = jsonDecode(respBody) as Map<String, dynamic>;
      return decoded;
    } catch (e) {
      _appendLog('Deepseek request failed: $e');
      return null;
    }
  }

  Future<void> _generateCommitInfo() async {
    if (_busy || _generatingCommitInfo) return;
    setState(() => _generatingCommitInfo = true);
    try {
      final staged = _changes.where((c) => c.staged).toList();
      final source = staged.isNotEmpty ? staged : _changes.where((c) => !c.staged).toList();
      if (source.isEmpty) {
        _appendLog('No changes found to generate commit message from.');
        return;
      }

      final buffers = <String>[];
      int totalLen = 0;
      for (final c in source) {
        try {
          final d = await _git.diffFile(widget.repoPath, c);
          final snippet = d.length > 4000 ? d.substring(0, 4000) + '\n...[truncated]' : d;
          buffers.add('FILE: ${c.path}\n$snippet');
          totalLen += snippet.length;
          if (totalLen > 10000) break;
        } catch (_) {
          // ignore single file errors
        }
      }

      final prompt = '''Please generate a concise commit message (max 20 chars) based on the following diffs. Return ONLY a JSON object with keys "message".\n\n${buffers.join('\n\n---\n\n')}''';

      _appendLog('Calling Deepseek to generate commit info...');
      final resp = await _callDeepseek(prompt);
      if (resp == null) return;

      String? content;
      if (resp.containsKey('choices') && resp['choices'] is List && resp['choices'].isNotEmpty) {
        final first = resp['choices'][0];
        if (first is Map && first.containsKey('message')) {
          final msg = first['message'];
          if (msg is Map && msg.containsKey('content')) content = msg['content'] as String?;
        }
        content ??= (first is Map && first['text'] is String) ? first['text'] as String : null;
      }
      content ??= resp['output']?.toString();
      if (content == null) {
        _appendLog('Deepseek returned no usable content.');
        return;
      }

      String? aiMessage;
      try {
        final j = jsonDecode(content);
        if (j is Map) {
          aiMessage = (j['message'] ?? j['title'] ?? j['msg'])?.toString();
        }
      } catch (_) {
        final jsonStart = content.indexOf('{');
        final jsonEnd = content.lastIndexOf('}');
        if (jsonStart != -1 && jsonEnd != -1 && jsonEnd > jsonStart) {
          try {
            final j = jsonDecode(content.substring(jsonStart, jsonEnd + 1));
            if (j is Map) {
              aiMessage = (j['message'] ?? j['title'] ?? j['msg'])?.toString();
            }
          } catch (_) {}
        }
      }

      String msg = (aiMessage ?? content).trim();
      msg = msg.replaceAll(RegExp(r'[\r\n]+'), ' ').replaceAll(RegExp(r'\s+'), ' ');

      final prefix = _selectedCommitType.trim();
      if (prefix.isNotEmpty) {
        final lower = msg.toLowerCase();
        for (final t in _commitTypes) {
          final t1 = '$t:';
          final t2 = '$t：';
          if (lower.startsWith(t1) || lower.startsWith(t2)) {
            final idx1 = msg.indexOf(':');
            final idx2 = msg.indexOf('：');
            int cut = -1;
            if (idx1 == -1) {
              cut = idx2;
            } else if (idx2 == -1) {
              cut = idx1;
            } else {
              cut = idx1 < idx2 ? idx1 : idx2;
            }
            if (cut != -1) {
              msg = msg.substring(cut + 1).trimLeft();
            }
            break;
          }
        }
        msg = '$prefix: ' + msg;
      }

      _messageController.text = msg;
      _appendLog('Inserted AI-generated commit message.');
    } finally {
      if (!mounted) return;
      setState(() => _generatingCommitInfo = false);
    }
  }

  

  

  

  

  Future<void> _loadCommitDetails(GitCommit commit) async {
    setState(() {
      _selectedCommit = commit;
      _commitDetailsLoading = true;
      _commitDetailsText = null;
    });
    try {
      final details = await _git.showCommit(widget.repoPath, commit.hash);
      if (!mounted) return;
      setState(() {
        _commitDetailsLoading = false;
        _commitDetailsText = details;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _commitDetailsLoading = false;
        _commitDetailsText = 'Failed to load commit: $e';
      });
    }
  }

  void _showCreateBranchDialog() {
    if (_busy) return;
    final nameController = TextEditingController();
    String? base = _currentBranch;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Create Branch'),
          content: SizedBox(
            width: 420,
            child: StatefulBuilder(
              builder: (context, setStateDialog) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Branch name', hintText: 'feature/new-branch'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: base,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Base branch'),
                      items: _branches
                          .map((b) => DropdownMenuItem<String>(
                                value: b,
                                child: Text(b),
                              ))
                          .toList(),
                      onChanged: (v) => setStateDialog(() => base = v),
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.of(ctx).pop();
                await _createBranch(name, base);
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showBranchContextMenu(String branch, bool isCurrent, Offset? position) async {
    final overlayBox = Overlay.of(context).context.findRenderObject() as RenderBox?;
    final fallback = overlayBox != null ? overlayBox.size.center(Offset.zero) : Offset.zero;
    final pos = position ?? fallback;
    final rect = overlayBox != null
        ? RelativeRect.fromRect(Rect.fromLTWH(pos.dx, pos.dy, 0, 0), Offset.zero & overlayBox.size)
        : RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy);

    final hasOrigin = _remotes.contains('origin');

    final selected = await showMenu<String>(
      context: context,
      position: rect,
      items: [
        if (hasOrigin)
          const PopupMenuItem<String>(value: 'push_origin', child: Text('Push to origin')),
        if (_currentBranch != null && !isCurrent)
          PopupMenuItem<String>(value: 'merge_into_current', child: Text('Merge into ${_currentBranch!}')),
        const PopupMenuItem<String>(value: 'delete', child: Text('Delete branch')),
      ],
    );

    if (selected == 'push_origin') {
      await _pushBranch(branch);
      return;
    }

    if (selected == 'merge_into_current') {
      await _mergeIntoCurrent(branch);
      return;
    }

    if (selected == 'delete') {
      if (isCurrent) {
        _appendLog('Cannot delete the current checked-out branch.');
        return;
      }
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Delete branch?'),
            content: Text('Are you sure you want to delete branch "$branch"?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
            ],
          );
        },
      );
      if (confirm == true) {
        await _deleteBranch(branch);
      }
    }
  }

  
}