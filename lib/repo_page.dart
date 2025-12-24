import 'dart:io';

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

  bool _busy = false;
  String _log = '';

  List<GitChange> _changes = [];
  List<String> _branches = [];
  List<String> _remotes = [];
  String? _currentBranch;
  String? _selectedRemote;

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

      final nextSelection = _matchChange(changes, _selectedChange) ?? (changes.isNotEmpty ? changes.first : null);

      if (!mounted) return;
      final prevSelectedCommit = _selectedCommit;
      setState(() {
        _changes = changes;
        _branches = branches;
        _currentBranch = current;
        _remotes = remotes;
        _recentCommits = history;
        if (_remotes.isNotEmpty && (_selectedRemote == null || !_remotes.contains(_selectedRemote))) {
          _selectedRemote = _remotes.first;
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

  void _toggleCommitOverlay() => setState(() => _commitOverlay = !_commitOverlay);

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
                return ListTile(
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
                );
              },
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          _buildSectionHeader('REMOTES'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _remotes
                  .map((remote) => ChoiceChip(
                        label: Text(remote),
                        selected: _selectedRemote == remote,
                        onSelected: (_) => setState(() => _selectedRemote = remote),
                        labelStyle: const TextStyle(fontSize: 12),
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            color: AppColors.panel,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              const Text(
                'RECENT COMMITS',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1, color: AppColors.textMuted),
              ),
              const SizedBox(width: 12),
              Text(_currentBranch ?? '-', style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh history',
                icon: const Icon(Icons.refresh, size: 16),
                onPressed: _busy ? null : _refreshAll,
              ),
            ],
          ),
        ),
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
          ElevatedButton.icon(
            onPressed: _busy ? null : _commit,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Commit'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
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