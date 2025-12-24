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

class GitService {
  Future<ProcessResult> _run(List<String> args, String workingDir) async {
    return await Process.run('git', args, workingDirectory: workingDir);
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

  Future<List<String>> remotes(String repoPath) async {
    final result = await _run(['remote'], repoPath);
    final out = result.stdout.toString();
    return out.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }
}
