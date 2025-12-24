import 'dart:io';
import 'package:flutter/material.dart';
import 'git_service.dart';

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
    final time = DateTime.now().toIso8601String();
    setState(() {
      _log = '[$time] $text\n\n' + _log;
    });
  }

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    final path = widget.repoPath;
    final changes = await _git.status(path);
    final branches = await _git.branches(path);
    final current = await _git.currentBranch(path);
    final remotes = await _git.remotes(path);
    setState(() {
      _changes = changes;
      _branches = branches;
      _currentBranch = current;
      _remotes = remotes;
      if (_remotes.isNotEmpty && (_selectedRemote == null || !_remotes.contains(_selectedRemote))) {
        _selectedRemote = _remotes.first;
      }
    });
  }

  Future<void> _stage(GitChange c) async {
    setState(() => _busy = true);
    _appendLog(await _git.addFiles(widget.repoPath, [c.path]));
    setState(() => _busy = false);
    await _refreshAll();
  }

  Future<void> _unstage(GitChange c) async {
    setState(() => _busy = true);
    _appendLog(await _git.unstageFiles(widget.repoPath, [c.path]));
    setState(() => _busy = false);
    await _refreshAll();
  }

  Future<void> _stageAll() async {
    setState(() => _busy = true);
    _appendLog(await _git.addAll(widget.repoPath));
    setState(() => _busy = false);
    await _refreshAll();
  }

  Future<void> _unstageAll() async {
    final stagedPaths = _changes.where((c) => c.staged).map((c) => c.path).toList();
    if (stagedPaths.isEmpty) return;
    setState(() => _busy = true);
    _appendLog(await _git.unstageFiles(widget.repoPath, stagedPaths));
    setState(() => _busy = false);
    await _refreshAll();
  }

  Future<void> _commit() async {
    final msg = _messageController.text;
    setState(() => _busy = true);
    _appendLog(await _git.commit(widget.repoPath, msg));
    setState(() => _busy = false);
    await _refreshAll();
  }

  Future<void> _pull() async {
    setState(() => _busy = true);
    _appendLog(await _git.pull(widget.repoPath, remote: _selectedRemote, branch: _currentBranch));
    setState(() => _busy = false);
    await _refreshAll();
  }

  Future<void> _push() async {
    setState(() => _busy = true);
    _appendLog(await _git.push(widget.repoPath, remote: _selectedRemote, branch: _currentBranch));
    setState(() => _busy = false);
    await _refreshAll();
  }

  @override
  Widget build(BuildContext context) {
    final repoName = widget.repoPath.split(Platform.pathSeparator).last;
    return Scaffold(
      appBar: AppBar(
        title: Text(repoName),
        actions: [
          if (_busy) const Padding(padding: EdgeInsets.only(right: 12), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator()))),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sidebar: branches and remotes
          SizedBox(
            width: 240,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('分支', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        children: _branches
                            .map((b) => ListTile(
                                  dense: true,
                                  leading: Icon(b == _currentBranch ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                                  title: Text(b),
                                  onTap: () async {
                                    setState(() => _busy = true);
                                    _appendLog(await _git.checkout(widget.repoPath, b));
                                    setState(() => _busy = false);
                                    await _refreshAll();
                                  },
                                ))
                            .toList(),
                      ),
                    ),
                    const Divider(),
                    const Text('远程', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _remotes
                          .map((r) => ChoiceChip(
                                label: Text(r),
                                selected: _selectedRemote == r,
                                onSelected: (_) => setState(() => _selectedRemote = r),
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          // Main area
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('当前分支: ${_currentBranch ?? '-'}'),
                      const SizedBox(width: 16),
                      Text('远程: ${_selectedRemote ?? (_remotes.isNotEmpty ? _remotes.first : '-') }'),
                      const Spacer(),
                      ElevatedButton(onPressed: _busy ? null : _refreshAll, child: const Text('刷新')),
                      const SizedBox(width: 8),
                      ElevatedButton(onPressed: _busy ? null : _pull, child: const Text('拉取')),
                      const SizedBox(width: 8),
                      ElevatedButton(onPressed: _busy ? null : _push, child: const Text('推送')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Row(
                      children: [
                        // Unstaged
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text('未暂存文件 (${_changes.where((c)=>!c.staged).length})'),
                                  const Spacer(),
                                  ElevatedButton(onPressed: _busy ? null : _stageAll, child: const Text('全部暂存')),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Expanded(
                                child: ListView(
                                  children: _changes
                                      .where((c) => !c.staged)
                                      .map((c) => ListTile(
                                            title: Text(c.path),
                                            subtitle: Text('WT:${c.workTreeStatus}'),
                                            trailing: ElevatedButton(onPressed: _busy ? null : () => _stage(c), child: const Text('暂存')),
                                          ))
                                      .toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const VerticalDivider(width: 12),
                        // Staged
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text('已暂存文件 (${_changes.where((c)=>c.staged).length})'),
                                  const Spacer(),
                                  ElevatedButton(onPressed: _busy ? null : _unstageAll, child: const Text('全部取消暂存')),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Expanded(
                                child: ListView(
                                  children: _changes
                                      .where((c) => c.staged)
                                      .map((c) => ListTile(
                                            title: Text(c.path),
                                            subtitle: Text('IDX:${c.indexStatus}'),
                                            trailing: ElevatedButton(onPressed: _busy ? null : () => _unstage(c), child: const Text('取消暂存')),
                                          ))
                                      .toList(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Commit area
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: const InputDecoration(hintText: '提交说明', labelText: 'Commit Message'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(onPressed: _busy ? null : _commit, child: const Text('提交')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Log output
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
                      child: SingleChildScrollView(reverse: true, child: SelectableText(_log.isEmpty ? 'No logs yet.' : _log)),
                    ),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
