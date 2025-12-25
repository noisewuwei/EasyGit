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
  String _log = '';
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

  GitChange? _selectedChange;
  bool _diffLoading = false;
  String? _diffText;

  List<GitCommit> _recentCommits = [];
  bool _commitOverlay = false;
  GitCommit? _selectedCommit;
  bool _commitDetailsLoading = false;
  String? _commitDetailsText;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _diffScrollController.dispose();
    super.dispose();
  }

  void _appendLog(String text) {
    final time = DateTime.now().toIso8601String().split('T').last.split('.').first;
    print('$time - $text');
  }

  Future<void> _refreshAll() async {
    if (!mounted) return;
    final path = widget.repoPath;
    try {
      final changes = await _git.status(path);
      final branches = await _git.branches(path);
      final current = await _git.currentBranch(path);
      final remotes = await _git.remotes(path);
      final history = await _git.recentCommits(path);
      final submodules = await _git.submodules(path);

      final nextSelection = _matchChange(changes, _selectedChange) ?? (changes.isNotEmpty ? changes.first : null);

      if (!mounted) return;
      final prevSelectedCommit = _selectedCommit;
      setState(() {
        _changes = changes;
        _branches = branches;
        _currentBranch = current;
        _remotes = remotes;
        _recentCommits = history;
        _submodules = submodules;
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

  Future<void> _commit() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;
    await _runGitOp(() => _git.commit(widget.repoPath, message));
    _messageController.clear();
  }

  Future<void> _pull() => _runGitOp(() => _git.pull(widget.repoPath, remote: _selectedRemote, branch: _currentBranch));
  Future<void> _push() => _runGitOp(() => _git.push(widget.repoPath, remote: _selectedRemote, branch: _currentBranch));
  Future<void> _checkout(String branch) => _runGitOp(() => _git.checkout(widget.repoPath, branch));
  Future<void> _createBranch(String name, String? base) => _runGitOp(() async {
        final created = await _git.createBranch(widget.repoPath, name, startPoint: base);
        final checkout = await _git.checkout(widget.repoPath, name);
        return '$created\n$checkout';
      });
  Future<void> _deleteBranch(String branch) => _runGitOp(() => _git.deleteBranch(widget.repoPath, branch));

  void _toggleCommitOverlay() => setState(() => _commitOverlay = !_commitOverlay);

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

  @override
  Widget build(BuildContext context) {
    final repoName = widget.repoPath.split(Platform.pathSeparator).last;
    final unstaged = _changes.where((c) => !c.staged).toList();
    final staged = _changes.where((c) => c.staged).toList();
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: canPop ? 48 : 0,
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        titleSpacing: 0,
        title: isDesktop
            ? Row(
                children: [
                  Expanded(
                    child: DragToMoveArea(
                      child: Container(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(repoName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              )
            : Text(repoName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.panel,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          if (isDesktop) const WindowControls(),
        ],
      ),
      body: Row(
        children: [
          RepoSidebar(
            branches: _branches,
            currentBranch: _currentBranch,
            remotes: _remotes,
            selectedRemote: _selectedRemote,
            remoteBranches: _remoteBranches,
            remoteBranchesLoading: _remoteBranchesLoading,
            submodules: _submodules,
            repoPath: widget.repoPath,
            onCheckoutBranch: (b) => _checkout(b),
            onShowBranchContextMenu: (b, isCurrent, pos) => _showBranchContextMenu(b, isCurrent, pos),
            onCheckoutRemoteBranch: (rb) => _checkoutRemoteBranch(rb),
          ),
          Expanded(
            child: Column(
              children: [
                RepoToolbar(
                  currentBranch: _currentBranch,
                  selectedRemote: _selectedRemote,
                  busy: _busy,
                  onCreateBranch: _showCreateBranchDialog,
                  onPull: _pull,
                  onPush: _push,
                  onToggleCommitOverlay: _toggleCommitOverlay,
                  onRefresh: _refreshAll,
                ),
                if (_commitOverlay) ...[
                  SizedBox(
                    height: 180,
                    child: CommitHistoryPanel(
                      recentCommits: _recentCommits,
                      showDetails: false,
                      selectedCommit: _selectedCommit,
                      onSelectCommit: _loadCommitDetails,
                      detailsLoading: _commitDetailsLoading,
                      detailsText: _commitDetailsText,
                      diffScrollController: _diffScrollController,
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
                      onPreviewChange: (c) => _previewChange(c),
                      onStage: (c) => _stage(c),
                      onUnstage: (c) => _unstage(c),
                      onStageAll: _stageAll,
                      onUnstageAll: _unstageAll,
                      busy: _busy,
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
                      detailsLoading: _commitDetailsLoading,
                      detailsText: _commitDetailsText,
                      diffScrollController: _diffScrollController,
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

    final selected = await showMenu<String>(
      context: context,
      position: rect,
      items: [
        const PopupMenuItem<String>(value: 'delete', child: Text('Delete branch')),
      ],
    );

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