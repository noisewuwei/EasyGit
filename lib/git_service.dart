import 'dart:convert';
import 'dart:io';

class GitChange {
  final String path;
  final String indexStatus; // X
  final String workTreeStatus; // Y
  final bool staged;

  GitChange({
    required this.path,
    required this.indexStatus,
    required this.workTreeStatus,
    required this.staged,
  });
}

class GitCommit {
  final String hash;
  final String author;
  final String date;
  final String message;

  GitCommit({
    required this.hash,
    required this.author,
    required this.date,
    required this.message,
  });
}

class GitSubmodule {
  final String path;
  final String url;
  final String commit;
  final bool initialized;

  GitSubmodule({
    required this.path,
    required this.url,
    required this.commit,
    required this.initialized,
  });
}

class GitService {
  Future<ProcessResult> _run(List<String> args, String workingDir) async {
    return await Process.run(
      'git',
      args,
      workingDirectory: workingDir,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  }

  Future<String> runGit(List<String> args, String workingDir) async {
    try {
      final result = await _run(args, workingDir);
      final out = result.stdout?.toString() ?? '';
      final err = result.stderr?.toString() ?? '';
      return '[git ${args.join(' ')}] exit=${result.exitCode}\nSTDOUT:\n$out\nSTDERR:\n$err';
    } catch (e) {
      return 'Failed to run git ${args.join(' ')}: $e';
    }
  }

  Future<bool> isGitRepo(String repoPath) async {
    try {
      final result = await _run(['rev-parse', '--is-inside-work-tree'], repoPath);
      return result.exitCode == 0 && result.stdout.toString().trim() == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<String> cloneRepo(String remoteUrl, String targetDirParent) async {
    // Clone into parent directory; git will create folder based on repo name
    return await runGit(['clone', remoteUrl], targetDirParent);
  }

  Future<String> addAll(String repoPath) async {
    return await runGit(['add', '.'], repoPath);
  }

  Future<String> addFiles(String repoPath, List<String> files) async {
    if (files.isEmpty) return 'No files to stage.';
    return await runGit(['add', ...files], repoPath);
  }

  Future<String> unstageFiles(String repoPath, List<String> files) async {
    if (files.isEmpty) return 'No files to unstage.';
    return await runGit(['reset', 'HEAD', '--', ...files], repoPath);
  }

  Future<String> commit(String repoPath, String message) async {
    if (message.trim().isEmpty) return 'Commit message is empty.';
    final commitRes = await runGit(['commit', '-m', message], repoPath);
    return 'COMMIT RESULT:\n$commitRes';
  }

  Future<String> pull(String repoPath, {String? remote, String? branch}) async {
    final args = ['pull'];
    if (remote != null && remote.isNotEmpty) args.add(remote);
    if (branch != null && branch.isNotEmpty) args.add(branch);
    final res = await runGit(args, repoPath);
    return 'PULL RESULT:\n$res';
  }

  Future<String> push(String repoPath, {String? remote, String? branch}) async {
    final args = ['push'];
    if (remote != null && remote.isNotEmpty) args.add(remote);
    if (branch != null && branch.isNotEmpty) args.add(branch);
    final res = await runGit(args, repoPath);
    return 'PUSH RESULT:\n$res';
  }

  Future<List<GitChange>> status(String repoPath) async {
    final result = await _run(['status', '--porcelain'], repoPath);
    final out = result.stdout.toString();
    final lines = out.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final changes = <GitChange>[];
    for (final line in lines) {
      if (line.length < 3) continue;
      final x = line[0];
      final y = line[1];
      var path = line.substring(3).trim();
      if (path.contains(' -> ')) {
        // Rename format
        path = path.split(' -> ').last.trim();
      }
      final staged = x != ' ' && x != '?';
      changes.add(GitChange(path: path, indexStatus: x, workTreeStatus: y, staged: staged));
    }
    return changes;
  }

  Future<List<String>> branches(String repoPath) async {
    final result = await _run(['branch', '--list'], repoPath);
    final out = result.stdout.toString();
    final lines = out.split('\n');
    final names = <String>[];
    for (final l in lines) {
      final trimmed = l.trim();
      if (trimmed.isEmpty) continue;
      names.add(trimmed.replaceFirst('* ', ''));
    }
    return names;
  }

  Future<String?> currentBranch(String repoPath) async {
    final result = await _run(['rev-parse', '--abbrev-ref', 'HEAD'], repoPath);
    if (result.exitCode != 0) return null;
    return result.stdout.toString().trim();
  }

  Future<String> checkout(String repoPath, String branch) async {
    return await runGit(['checkout', branch], repoPath);
  }

  Future<String> createBranch(String repoPath, String name, {String? startPoint}) async {
    if (name.trim().isEmpty) return 'Branch name is empty.';
    final args = ['branch', name];
    if (startPoint != null && startPoint.trim().isNotEmpty) {
      args.add(startPoint);
    }
    return await runGit(args, repoPath);
  }

  Future<String> deleteBranch(String repoPath, String name, {bool force = true}) async {
    if (name.trim().isEmpty) return 'Branch name is empty.';
    final flag = force ? '-D' : '-d';
    return await runGit(['branch', flag, name], repoPath);
  }

  Future<List<String>> remotes(String repoPath) async {
    final result = await _run(['remote'], repoPath);
    final out = result.stdout.toString();
    return out.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  Future<List<GitSubmodule>> submodules(String repoPath) async {
    final result = await _run(['submodule', 'status', '--recursive'], repoPath);
    if (result.exitCode != 0) {
      return [];
    }
    final lines = result.stdout.toString().split('\n');
    final modules = <GitSubmodule>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      // Format: " 4a1b2c3d path (heads/main)"; leading char indicates init status
      final initialized = line.startsWith(' ');
      final cleaned = line.trimLeft();
      final parts = cleaned.split(' ');
      if (parts.length < 2) continue;
      final commit = parts[0];
      final path = parts[1];
      // Try to get URL via git config submodule.<path>.url
      String url = '';
      try {
        final urlRes = await _run(['config', '--file', '.gitmodules', '--get', 'submodule.$path.url'], repoPath);
        if (urlRes.exitCode == 0) {
          url = urlRes.stdout.toString().trim();
        }
      } catch (_) {}
      modules.add(GitSubmodule(path: path, url: url, commit: commit, initialized: initialized));
    }
    return modules;
  }

  /// List remote branches (returns entries like `origin/branch-name`).
  Future<List<String>> remoteBranches(String repoPath) async {
    final result = await _run(['branch', '-r'], repoPath);
    if (result.exitCode != 0) return [];
    final out = result.stdout.toString();
    final lines = out.split('\n');
    final branches = <String>[];
    for (var l in lines) {
      var trimmed = l.trim();
      if (trimmed.isEmpty) continue;
      // skip symbolic refs like "origin/HEAD -> origin/main"
      if (trimmed.contains('->')) continue;
      branches.add(trimmed);
    }
    return branches;
  }

  /// Create a local branch that tracks the remote branch and check it out.
  /// Uses `git checkout --track <remote>/<branch>`; if that fails, falls back
  /// to `git checkout -b <branch> <remote>/<branch>`.
  Future<String> checkoutRemoteBranch(String repoPath, String remote, String branch) async {
    final fullRef = '$remote/$branch';
    // Try --track first
    var res = await runGit(['checkout', '--track', fullRef], repoPath);
    if (res.contains('error') || res.contains('fatal')) {
      // Try explicit creation
      res = await runGit(['checkout', '-b', branch, fullRef], repoPath);
    }
    return res;
  }

  Future<List<GitCommit>> recentCommits(String repoPath, {int limit = 20}) async {
    final format = '%h%x09%an%x09%ad%x09%s';
    final result = await _run(['log', '-n', '$limit', '--date=short', '--pretty=format:$format'], repoPath);
    if (result.exitCode != 0) {
      return [];
    }
    final lines = result.stdout.toString().split('\n').where((l) => l.trim().isNotEmpty);
    final commits = <GitCommit>[];
    for (final line in lines) {
      final parts = line.split('\t');
      if (parts.length < 4) continue;
      commits.add(GitCommit(
        hash: parts[0],
        author: parts[1],
        date: parts[2],
        message: parts.sublist(3).join('\t'),
      ));
    }
    return commits;
  }

  Future<String> diffFile(String repoPath, GitChange change) async {
    final args = <String>['diff'];
    if (change.staged) {
      args.add('--cached');
    }
    args.addAll(['--', change.path]);
    final result = await _run(args, repoPath);
    final stdout = result.stdout.toString();
    final stderr = result.stderr.toString();
    if (result.exitCode != 0 && stdout.trim().isEmpty) {
      return 'Failed to load diff for ${change.path}:\n$stderr';
    }
    if (stdout.trim().isEmpty) {
      return 'No diff to display for ${change.path}.';
    }
    return stdout;
  }

  Future<String> showCommit(String repoPath, String hash) async {
    final result = await _run(['show', '--stat', '--patch', '--color=never', hash], repoPath);
    final stdout = result.stdout.toString();
    final stderr = result.stderr.toString();
    if (result.exitCode != 0 && stdout.trim().isEmpty) {
      return 'Failed to load commit $hash:\n$stderr';
    }
    return stdout.trim().isEmpty ? stderr : stdout;
  }
}
