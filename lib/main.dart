import 'package:flutter/material.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'git_service.dart';
import 'repo_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EasyGit - Simple',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'EasyGit - Repo Manager'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _repoController = TextEditingController();
  final _remoteUrlController = TextEditingController();
  final _cloneTargetController = TextEditingController();
  final _searchController = TextEditingController();

  final _git = GitService();

  bool _busy = false;
  final List<String> _repos = [];
  String? _activeRepo;

  void _openRepo(String path) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => RepoPage(repoPath: path)));
  }

  @override
  void initState() {
    super.initState();
    _loadRepos();
  }

  Future<void> _loadRepos() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('repos') ?? [];
    setState(() {
      _repos.clear();
      _repos.addAll(list);
    });
  }

  Future<void> _saveRepos() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('repos', _repos);
  }

  Future<void> _showAddRepoDialog() async {
    if (_busy) return;
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('添加仓库'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('本地仓库'),
                  TextField(
                    controller: _repoController,
                    decoration: const InputDecoration(hintText: '本地路径 如 C\\path\\to\\repo'),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    ElevatedButton(onPressed: _addLocalRepo, child: const Text('添加本地')),
                    const SizedBox(width: 8),
                    ElevatedButton(
                        onPressed: () {
                          final cwd = Directory.current.path;
                          _repoController.text = cwd;
                        },
                        child: const Text('使用当前目录')),
                    const SizedBox(width: 8),
                    ElevatedButton(
                        onPressed: () async {
                          final dirPath = await FilePicker.platform.getDirectoryPath();
                          if (dirPath != null) {
                            _repoController.text = dirPath;
                          }
                        },
                        child: const Text('浏览...')),
                  ]),
                  const Divider(height: 24),
                  const Text('克隆远程仓库'),
                  TextField(controller: _remoteUrlController, decoration: const InputDecoration(hintText: '远程 URL')), 
                  const SizedBox(height: 8),
                  TextField(controller: _cloneTargetController, decoration: const InputDecoration(hintText: '目标父目录')), 
                  const SizedBox(height: 8),
                  ElevatedButton(onPressed: _cloneRemoteRepo, child: const Text('克隆')),
                ],
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('关闭'))],
        );
      },
    );
  }

  Future<void> _addLocalRepo() async {
    final path = _repoController.text.trim();
    if (path.isEmpty) {
      print('Local path is empty.');
      return;
    }
    if (!Directory(path).existsSync()) {
      print('Path does not exist: $path');
      return;
    }
    if (!await _git.isGitRepo(path)) {
      print('Not a git repository: $path');
      return;
    }
    if (!_repos.contains(path)) {
      setState(() {
        _repos.add(path);
        _activeRepo = path;
      });
      await _saveRepos();
      _openRepo(path);
    } else {
      _openRepo(path);
    }
  }

  Future<void> _cloneRemoteRepo() async {
    final url = _remoteUrlController.text.trim();
    final targetParent = _cloneTargetController.text.trim();
    if (url.isEmpty || targetParent.isEmpty) {
      print('Remote URL or target directory is empty.');
      return;
    }
    if (!Directory(targetParent).existsSync()) {
      print('Target directory does not exist: $targetParent');
      return;
    }
    setState(() => _busy = true);
    final res = await _git.cloneRepo(url, targetParent);
    setState(() => _busy = false);
    // Try to infer cloned folder by listing new directories; keep simple: user can manually add after clone
  }

  // Repo interactions happen in RepoPage; home only manages list and navigation.

  @override
  void dispose() {
    _repoController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _repos
        : _repos.where((r) => r.toLowerCase().contains(query) || r.split(Platform.pathSeparator).last.toLowerCase().contains(query)).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加仓库',
            onPressed: _busy ? null : _showAddRepoDialog,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('本地仓库', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '搜索'),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: _busy ? null : _showAddRepoDialog, child: const Text('添加仓库')),
            ]),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final path = filtered[i];
                  final name = path.split(Platform.pathSeparator).last;
                  return ListTile(
                    leading: const Icon(Icons.folder),
                    title: Text(name),
                    subtitle: Text(path),
                    onTap: () => _openRepo(path),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton(onPressed: () => _openRepo(path), child: const Text('打开')),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: '移除',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            setState(() {
                              _repos.remove(path);
                            });
                            await _saveRepos();
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
