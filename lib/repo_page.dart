import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'git_service.dart';
import 'ui/app_colors.dart';
import 'ui/window_controls.dart';
import 'utils/platform_utils.dart';

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
    setState(() {
      _log = '[$time] $text\n\n$_log';
    });
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
          _buildSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildToolbar(),
                if (_commitOverlay) ...[
                  SizedBox(height: 180, child: _buildCommitHistoryPanel()),
                  Expanded(child: _buildChangesAndDiff(unstaged, staged)),
                  Container(height: 1, color: AppColors.border),
                  SizedBox(
                    height: 220,
                    child: Row(
                      children: [
                        Expanded(flex: 2, child: _buildCommitPanel()),
                        Container(width: 1, color: AppColors.border),
                        Expanded(flex: 3, child: _buildLogPanel()),
                      ],
                    ),
                  ),
                ] else ...[
                  Expanded(child: _buildCommitHistoryPanel(showDetails: true)),
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

  Widget _buildSidebar() {
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('BRANCHES'),
          Expanded(
            child: ListView.builder(
              itemCount: _branches.length,
              itemBuilder: (context, index) {
                final branch = _branches[index];
                final isCurrent = branch == _currentBranch;
                return GestureDetector(
                  onSecondaryTapDown: (details) => _showBranchContextMenu(branch, isCurrent, details.globalPosition),
                  onLongPress: () => _showBranchContextMenu(branch, isCurrent, null),
                  child: ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Icon(Icons.call_split, size: 16, color: isCurrent ? AppColors.accent : AppColors.textMuted),
                    title: Text(
                      branch,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                        color: isCurrent ? AppColors.textPrimary : AppColors.textSecondary,
                      ),
                    ),
                    selected: isCurrent,
                    selectedTileColor: AppColors.panel,
                    onTap: () => _checkout(branch),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          _buildSectionHeader('REMOTES'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: _remotes.isEmpty
                ? const Text('No remotes', style: TextStyle(color: AppColors.textMuted))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _remotes
                        .map(
                          (remote) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(remote, style: TextStyle(fontSize: 13, color: _selectedRemote == remote ? AppColors.textPrimary : AppColors.textSecondary)),
                          ),
                        )
                        .toList(),
                  ),
          ),
          // remote branches list for selected remote
          if (_selectedRemote != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              height: 160,
              child: _remoteBranchesLoading
                  ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                  : _remoteBranches[_selectedRemote!]?.isEmpty ?? true
                      ? const Center(child: Text('No remote branches', style: TextStyle(color: AppColors.textMuted)))
                      : ListView.separated(
                          itemCount: _remoteBranches[_selectedRemote!]!.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                          itemBuilder: (context, index) {
                            final rb = _remoteBranches[_selectedRemote!]![index];
                            return ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              title: Text(rb, style: const TextStyle(fontSize: 13)),
                              trailing: IconButton(
                                icon: const Icon(Icons.download, size: 16),
                                tooltip: 'Checkout',
                                onPressed: () => _checkoutRemoteBranch(rb),
                              ),
                            );
                          },
                        ),
            ),
          const Divider(height: 1, color: AppColors.border),
          _buildSectionHeader('SUBMODULES'),
          Expanded(
            child: _submodules.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text('No submodules', style: TextStyle(color: AppColors.textMuted)),
                  )
                : ListView.separated(
                    itemCount: _submodules.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (context, index) {
                      final sm = _submodules[index];
                      final absolutePath = '${widget.repoPath}${Platform.pathSeparator}${sm.path}';
                      return GestureDetector(
                        onDoubleTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RepoPage(repoPath: absolutePath),
                            ),
                          );
                        },
                        child: ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: Icon(sm.initialized ? Icons.link : Icons.link_off, size: 16, color: sm.initialized ? AppColors.accent : AppColors.textMuted),
                          title: Text(sm.path, style: const TextStyle(fontSize: 13)),
                          subtitle: Text(sm.commit, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.call_split, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Text(_currentBranch ?? '-', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _showCreateBranchDialog,
            icon: const Icon(Icons.fork_right, size: 14),
            label: const Text('New'),
            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
          ),
          const SizedBox(width: 24),
          const Icon(Icons.cloud_outlined, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Text(_selectedRemote ?? '-', style: const TextStyle(color: AppColors.textSecondary)),
          const Spacer(),
          _buildActionButton('Pull', Icons.arrow_downward, _pull),
          const SizedBox(width: 8),
          _buildActionButton('Push', Icons.arrow_upward, _push),
          const SizedBox(width: 8),
          _buildActionButton(_commitOverlay ? 'Done' : 'Add', _commitOverlay ? Icons.check : Icons.add, _toggleCommitOverlay),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _busy ? null : _refreshAll,
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }

  Widget _buildCommitHistoryPanel({bool showDetails = false}) {
    final historyList = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            color: AppColors.background,
            child: _recentCommits.isEmpty
                ? const Center(child: Text('No commits found.', style: TextStyle(color: AppColors.textMuted)))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: _recentCommits.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (context, index) {
                      final commit = _recentCommits[index];
                      final isSelected = showDetails && _selectedCommit?.hash == commit.hash;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(commit.message, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${commit.hash} · ${commit.author} · ${commit.date}', style: const TextStyle(color: AppColors.textMuted)),
                        dense: true,
                        selected: isSelected,
                        selectedTileColor: AppColors.panel,
                        onTap: showDetails ? () => _loadCommitDetails(commit) : null,
                      );
                    },
                  ),
          ),
        ),
      ],
    );

    if (!showDetails) {
      return historyList;
    }

    return Row(
      children: [
        Expanded(flex: 3, child: historyList),
        Container(width: 1, color: AppColors.border),
        Expanded(flex: 4, child: _buildCommitDetailPanel()),
      ],
    );
  }

  Widget _buildChangesAndDiff(List<GitChange> unstaged, List<GitChange> staged) {
    return Row(
      children: [
        Expanded(flex: 5, child: _buildChangeColumns(unstaged, staged)),
        Container(width: 1, color: AppColors.border),
        Expanded(flex: 4, child: _buildDiffPanel()),
      ],
    );
  }

  Widget _buildChangeColumns(List<GitChange> unstaged, List<GitChange> staged) {
    return Row(
      children: [
        Expanded(child: _buildFileGroup('Unstaged Changes', unstaged, false)),
        Container(width: 1, color: AppColors.border),
        Expanded(child: _buildFileGroup('Staged Changes', staged, true)),
      ],
    );
  }

  Widget _buildDiffPanel() {
    final fileName = _selectedChange?.path ?? 'Select a file to preview';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            color: AppColors.panel,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'DIFF PREVIEW',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1, color: AppColors.textMuted),
              ),
              const SizedBox(height: 4),
              Text(fileName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: Colors.black,
            child: _diffLoading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _diffText == null
                    ? const Center(child: Text('Select a file from the list to view its diff.', style: TextStyle(color: AppColors.textMuted)))
                    : Scrollbar(
                        controller: _diffScrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _diffScrollController,
                          padding: const EdgeInsets.all(12),
                          child: SelectableText.rich(TextSpan(children: _buildDiffSpans(_diffText!))),
                        ),
                      ),
          ),
        ),
      ],
    );
  }

  List<TextSpan> _buildDiffSpans(String diff) {
    final lines = diff.split('\n');
    return lines
        .map(
          (line) => TextSpan(
            text: '$line\n',
            style: TextStyle(
              fontFamily: 'Consolas',
              fontSize: 12,
              color: _diffColorForLine(line),
            ),
          ),
        )
        .toList();
  }

  Color _diffColorForLine(String line) {
    if (line.startsWith('@@')) return AppColors.accent;
    if (line.startsWith('+') && !line.startsWith('+++')) return AppColors.success;
    if (line.startsWith('-') && !line.startsWith('---')) return AppColors.danger;
    if (line.startsWith('+++') || line.startsWith('---')) return AppColors.textSecondary;
    return AppColors.textPrimary;
  }

  Widget _buildCommitPanel() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('Type', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedCommitType,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Commit type',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: _commitTypes
                      .map(
                        (t) => DropdownMenuItem<String>(
                          value: t,
                          child: Text(t),
                        ),
                      )
                      .toList(),
                  onChanged: (_busy || _generatingCommitInfo)
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _selectedCommitType = value);
                          }
                        },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              controller: _messageController,
              expands: true,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                hintText: 'Commit message...',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (_busy || _generatingCommitInfo) ? null : _generateCommitInfo,
                  icon: _generatingCommitInfo
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.bolt, size: 14),
                  label: const Text('Generate'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _busy ? null : _commit,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Commit'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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

  Widget _buildLogPanel() {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('OUTPUT', style: TextStyle(fontSize: 12, letterSpacing: 1, color: AppColors.textMuted)),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                reverse: true,
                child: SelectableText(
                  _log.isEmpty ? 'No logs yet.' : _log,
                  style: const TextStyle(fontFamily: 'Consolas', fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
          letterSpacing: 1,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, VoidCallback onPressed) {
    return OutlinedButton.icon(
      onPressed: _busy ? null : onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        side: const BorderSide(color: AppColors.border),
      ),
    );
  }

  Widget _buildFileGroup(String title, List<GitChange> files, bool isStaged) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            color: AppColors.panel,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Text('$title (${files.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => isStaged
                        ? _unstageAll()
                        : _stageAll(),
                child: Text(isStaged ? 'Unstage All' : 'Stage All'),
              ),
            ],
          ),
        ),
        Expanded(
          child: files.isEmpty
              ? const Center(child: Text('No files', style: TextStyle(color: AppColors.textMuted)))
              : ListView.separated(
                  itemCount: files.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (context, index) {
                    final file = files[index];
                    final isSelected = _selectedChange != null &&
                        _selectedChange!.path == file.path &&
                        _selectedChange!.staged == file.staged;
                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      leading: Icon(
                        Icons.insert_drive_file_outlined,
                        size: 16,
                        color: isStaged ? AppColors.success : AppColors.warning,
                      ),
                      title: Text(file.path, style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                        isStaged ? 'IDX: ${file.indexStatus}' : 'WT: ${file.workTreeStatus}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                      trailing: IconButton(
                        icon: Icon(isStaged ? Icons.remove : Icons.add, size: 16),
                        tooltip: isStaged ? 'Unstage' : 'Stage',
                        onPressed: _busy
                            ? null
                            : () => isStaged
                                ? _unstage(file)
                                : _stage(file),
                      ),
                      selected: isSelected,
                      selectedTileColor: AppColors.panel,
                      onTap: () => _previewChange(file),
                    );
                  },
                ),
        ),
      ],
    );
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

  Widget _buildCommitDetailPanel() {
    if (_selectedCommit == null) {
      return Container(
        color: AppColors.background,
        alignment: Alignment.center,
        child: const Text('Select a commit to view details.', style: TextStyle(color: AppColors.textMuted)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: AppColors.panel,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_selectedCommit!.message, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('${_selectedCommit!.hash} · ${_selectedCommit!.author} · ${_selectedCommit!.date}', style: const TextStyle(color: AppColors.textMuted)),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: Colors.black,
            child: _commitDetailsLoading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _commitDetailsText == null
                    ? const Center(child: Text('No details loaded.', style: TextStyle(color: AppColors.textMuted)))
                    : Scrollbar(
                        controller: _diffScrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _diffScrollController,
                          padding: const EdgeInsets.all(12),
                          child: SelectableText.rich(
                            TextSpan(children: _buildDiffSpans(_commitDetailsText!)),
                          ),
                        ),
                      ),
          ),
        ),
      ],
    );
  }
}