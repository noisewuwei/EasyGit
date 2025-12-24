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
  bool _busy = false;
  String _log = '';

  List<GitChange> _changes = [];
  List<String> _branches = [];
  String? _currentBranch;
  List<String> _remotes = [];
  String? _selectedRemote;

  void _appendLog(String text) {
    final time = DateTime.now().toIso8601String().split('T').last.split('.').first;
    setState(() {
      _log = '[$time] $text\n' + _log;
    });
  }

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    if (!mounted) return;
    final path = widget.repoPath;
    try {
      final changes = await _git.status(path);
      final branches = await _git.branches(path);
      final current = await _git.currentBranch(path);
      final remotes = await _git.remotes(path);
      if (!mounted) return;
      setState(() {
        _changes = changes;
        _branches = branches;
        _currentBranch = current;
        _remotes = remotes;
        if (_remotes.isNotEmpty && (_selectedRemote == null || !_remotes.contains(_selectedRemote))) {
          _selectedRemote = _remotes.first;
        }
      });
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
                tooltip: '返回',
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
        centerTitle: false,
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
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _buildFileGroup('Unstaged Changes', unstaged, false)),
                      Container(width: 1, color: AppColors.border),
                      Expanded(child: _buildFileGroup('Staged Changes', staged, true)),
                    ],
                  ),
                ),
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
              ],
            ),
          ),
        ],
      ),
    );
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
          IconButton(
            onPressed: _busy ? null : _refreshAll,
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
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
              ? const Center(
                  child: Text('No files', style: TextStyle(color: AppColors.textMuted)),
                )
              : ListView.separated(
                  itemCount: files.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (context, index) {
                    final file = files[index];
                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      leading: Icon(
                        Icons.insert_drive_file_outlined,
                        size: 16,
                        color: isStaged ? AppColors.success : AppColors.warning,
                      ),
                      title: Text(file.path, style: const TextStyle(fontSize: 13)),
                      subtitle: Text(isStaged ? 'IDX: ${file.indexStatus}' : 'WT: ${file.workTreeStatus}', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                      trailing: IconButton(
                        icon: Icon(isStaged ? Icons.remove : Icons.add, size: 16),
                        tooltip: isStaged ? 'Unstage' : 'Stage',
                        onPressed: _busy
                            ? null
                            : () => isStaged
                                ? _unstage(file)
                                : _stage(file),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
