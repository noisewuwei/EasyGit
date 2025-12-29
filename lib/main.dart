import 'package:flutter/material.dart';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'git_service.dart';
import 'repo_page.dart';
import 'ui/app_theme.dart';
import 'ui/window_controls.dart';
import 'utils/platform_utils.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (isDesktop) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1400, 900),
      minimumSize: Size(1400, 900),
      center: true,
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Colors.transparent,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EasyGit',
      theme: AppTheme.dark,
      home: const MyHomePage(title: 'EasyGit'),
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
          title: const Text('Add Repository'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Local Repositories'),
                  TextField(
                    controller: _repoController,
                    decoration: const InputDecoration(hintText: 'Local path, e.g. C\\path\\to\\repo'),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    ElevatedButton(onPressed: () => _addLocalRepo(ctx), child: const Text('Add Local')),
                    // const SizedBox(width: 8),
                    // ElevatedButton(
                    //     onPressed: () {
                    //       final cwd = Directory.current.path;
                    //       _repoController.text = cwd;
                    //     },
                    //     child: const Text('Use Current Directory')),
                    const SizedBox(width: 8),
                    ElevatedButton(
                        onPressed: () async {
                          final dirPath = await getDirectoryPath();
                          if (dirPath != null) {
                            _repoController.text = dirPath;
                          }
                        },
                        child: const Text('Browse...')),
                  ]),
                  const Divider(height: 24),
                  const Text('Clone Remote Repository'),
                  TextField(controller: _remoteUrlController, decoration: const InputDecoration(hintText: 'Remote URL')), 
                  const SizedBox(height: 8),
                  TextField(controller: _cloneTargetController, decoration: const InputDecoration(hintText: 'Target Parent Directory')), 
                  const SizedBox(height: 8),
                  ElevatedButton(onPressed: () => _cloneRemoteRepo(ctx), child: const Text('Clone Repository')),
                ],
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))],
        );
      },
    );
  }

  Future<void> _addLocalRepo(BuildContext dialogCtx) async {
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
      Navigator.of(dialogCtx).pop();
      _openRepo(path);
    } else {
      Navigator.of(dialogCtx).pop();
      _openRepo(path);
    }
  }

  Future<void> _cloneRemoteRepo(BuildContext dialogCtx) async {
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
    await _git.cloneRepo(url, targetParent);
    setState(() => _busy = false);
    Navigator.of(dialogCtx).pop();
    // Try to infer cloned folder by listing new directories; keep simple: user can manually add after clone
  }

  // Repo interactions happen in RepoPage; home only manages list and navigation.

  @override
  void dispose() {
    _repoController.dispose();
    _remoteUrlController.dispose();
    _cloneTargetController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _repos
        : _repos.where((r) => r.toLowerCase().contains(query) || r.split(Platform.pathSeparator).last.toLowerCase().contains(query)).toList();
    final showWindowControls = isDesktop && !Platform.isMacOS;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: isDesktop
            ? ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: kToolbarHeight),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DragToMoveArea(
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(widget.title, textAlign: TextAlign.center),
                        ),
                      ),
                    ),
                    if (showWindowControls)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: WindowControls(),
                        ),
                      ),
                  ],
                ),
              )
            : Text(widget.title, textAlign: TextAlign.center),
        centerTitle: true,
        actions: [
          // actions kept empty to avoid shifting center
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Local Repositories', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search'),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: _busy ? null : _showAddRepoDialog, child: const Text('Add Repository')),
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
                        ElevatedButton(onPressed: () => _openRepo(path), child: const Text('Open')),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Remove',
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
