import 'dart:convert';
import 'dart:io';

class GitHunk {
  final String header;
  final String patch;

  GitHunk({required this.header, required this.patch});
}

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

class BranchAheadBehind {
  final int pull;
  final int push;

  const BranchAheadBehind({required this.pull, required this.push});
}

class GitService {
  bool _isConflictStatus(String x, String y) {
    final pair = '$x$y';
    if (x == 'U' || y == 'U') return true;
    return pair == 'AA' || pair == 'DD' || pair == 'AU' || pair == 'UA' || pair == 'UD' || pair == 'DU';
  }

  Future<bool> _stageBlobExists(String repoPath, int stage, String path) async {
    // stage: 1=base, 2=ours, 3=theirs
    final res = await _run(['cat-file', '-e', ':$stage:$path'], repoPath);
    return res.exitCode == 0;
  }

  Future<String> _diffStages(String repoPath, int a, int b, String path, String label) async {
    final res = await _run(['diff', '--color=never', ':$a:$path', ':$b:$path'], repoPath);
    final out = res.stdout.toString();
    final err = res.stderr.toString();
    if (res.exitCode != 0 && out.trim().isEmpty) {
      return '===== $label =====\nFailed to load diff: $err\n';
    }
    if (out.trim().isEmpty) {
      return '===== $label =====\nNo diff to display.\n';
    }
    return '===== $label =====\n$out\n';
  }

  Future<ProcessResult> _run(List<String> args, String workingDir) async {
    return await Process.run(
      'git',
      args,
      workingDirectory: workingDir,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  }

  Future<ProcessResult> _runWithInput(List<String> args, String workingDir, String input) async {
    final process = await Process.start(
      'git',
      args,
      workingDirectory: workingDir,
    );
    process.stdin.write(input);
    await process.stdin.close();
    final stdoutText = await process.stdout.transform(utf8.decoder).join();
    final stderrText = await process.stderr.transform(utf8.decoder).join();
    final exit = await process.exitCode;
    return ProcessResult(process.pid, exit, stdoutText, stderrText);
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

  Future<List<GitHunk>> hunks(String repoPath, String path, {bool staged = false}) async {
    final args = <String>['diff', '-U0'];
    if (staged) args.add('--cached');
    args.addAll(['--', path]);
    final res = await _run(args, repoPath);
    if (res.exitCode != 0) return [];
    final text = res.stdout.toString();
    return _extractHunks(text);
  }

  List<GitHunk> _extractHunks(String diffText) {
    final lines = diffText.split('\n');
    final hunks = <GitHunk>[];
    var fileHeader = <String>[];
    var current = <String>[];

    void flush() {
      if (current.isEmpty) return;
      final header = fileHeader.join('\n');
      final patch = [...fileHeader, ...current].join('\n');
      hunks.add(GitHunk(header: header, patch: patch + '\n'));
      current = [];
    }

    for (final line in lines) {
      if (line.startsWith('diff --git ')) {
        flush();
        fileHeader = [line];
        continue;
      }
      if (line.startsWith('index ') || line.startsWith('new file mode') || line.startsWith('deleted file mode')) {
        fileHeader.add(line);
        continue;
      }
      if (line.startsWith('--- ') || line.startsWith('+++ ')) {
        fileHeader.add(line);
        continue;
      }
      if (line.startsWith('@@')) {
        flush();
        current = [line];
        continue;
      }
      if (current.isNotEmpty) {
        current.add(line);
      }
    }
    flush();
    return hunks;
  }

  Future<String> applyPatchToIndex(String repoPath, String patch, {bool reverse = false}) async {
    final args = <String>['apply', '--cached', '--unidiff-zero', '--allow-empty'];
    if (reverse) args.add('-R');
    final res = await _runWithInput(args, repoPath, patch);
    final out = res.stdout.toString();
    final err = res.stderr.toString();
    return 'git ${args.join(' ')} exit=${res.exitCode}\nSTDOUT:\n$out\nSTDERR:\n$err';
  }

  Future<String> applyPatchToWorktree(String repoPath, String patch, {bool reverse = false}) async {
    final args = <String>['apply', '--unidiff-zero', '--allow-empty'];
    if (reverse) args.add('-R');
    final res = await _runWithInput(args, repoPath, patch);
    final out = res.stdout.toString();
    final err = res.stderr.toString();
    return 'git ${args.join(' ')} exit=${res.exitCode}\nSTDOUT:\n$out\nSTDERR:\n$err';
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

  Future<String> push(String repoPath, {String? remote, String? branch, bool setUpstream = false}) async {
    final args = <String>['push'];
    if (setUpstream) args.add('--set-upstream');
    if (remote != null && remote.isNotEmpty) args.add(remote);
    if (branch != null && branch.isNotEmpty) args.add(branch);
    final res = await runGit(args, repoPath);
    return 'PUSH RESULT:\n$res';
  }

  Future<String> merge(String repoPath, String sourceBranch) async {
    if (sourceBranch.trim().isEmpty) return 'Merge source branch is empty.';
    return await runGit(['merge', sourceBranch], repoPath);
  }

  Future<String> revertCommit(String repoPath, String hash) async {
    if (hash.trim().isEmpty) return 'Revert hash is empty.';
    return await runGit(['revert', hash], repoPath);
  }

  Future<String> cherryPick(String repoPath, String hash) async {
    if (hash.trim().isEmpty) return 'Cherry-pick hash is empty.';
    return await runGit(['cherry-pick', hash], repoPath);
  }

  Future<String> reset(String repoPath, String target, {String mode = 'mixed'}) async {
    if (target.trim().isEmpty) return 'Reset target is empty.';
    final valid = {'soft', 'mixed', 'hard'};
    final chosen = valid.contains(mode) ? mode : 'mixed';
    return await runGit(['reset', '--$chosen', target], repoPath);
  }

  Future<String> amendLastCommit(String repoPath, String message) async {
    // If no message is provided, reuse the existing commit message (--no-edit).
    final trimmed = message.trim();
    final args = trimmed.isEmpty
        ? ['commit', '--amend', '--no-edit']
        : ['commit', '--amend', '-m', trimmed];
    return await runGit(args, repoPath);
  }

  Future<String> lastCommitMessage(String repoPath) async {
    final res = await _run(['log', '-1', '--pretty=%B'], repoPath);
    if (res.exitCode != 0) return '';
    return res.stdout.toString().trim();
  }

  Future<String> restoreFile(String repoPath, String path) async {
    if (path.trim().isEmpty) return 'Restore path is empty.';
    // Restore changes in working tree for the given file.
    return await runGit(['restore', '--worktree', '--', path], repoPath);
  }

  Future<String> restoreFileFromIndex(String repoPath, String path) async {
    if (path.trim().isEmpty) return 'Restore path is empty.';
    // Unstage changes for a single file without touching worktree
    return await runGit(['checkout', 'HEAD', '--', path], repoPath);
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
      if (_isConflictStatus(x, y)) {
        // Show conflicts in both staged and unstaged lists.
        changes.add(GitChange(path: path, indexStatus: x, workTreeStatus: y, staged: true));
        changes.add(GitChange(path: path, indexStatus: x, workTreeStatus: y, staged: false));
        continue;
      }
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

  Future<String?> remoteUrl(String repoPath, String name) async {
    final result = await _run(['remote', 'get-url', name], repoPath);
    if (result.exitCode != 0) return null;
    return result.stdout.toString().trim();
  }

  Future<String> addRemote(String repoPath, String name, String url) async {
    if (name.trim().isEmpty || url.trim().isEmpty) return 'Remote name or url is empty.';
    return await runGit(['remote', 'add', name, url], repoPath);
  }

  Future<String> setRemoteUrl(String repoPath, String name, String url) async {
    if (name.trim().isEmpty || url.trim().isEmpty) return 'Remote name or url is empty.';
    return await runGit(['remote', 'set-url', name, url], repoPath);
  }

  Future<String> removeRemote(String repoPath, String name) async {
    if (name.trim().isEmpty) return 'Remote name is empty.';
    return await runGit(['remote', 'remove', name], repoPath);
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

  /// Ahead/behind counts for each local branch relative to its upstream.
  /// pull = commits remote has that local doesn't (needs pull)
  /// push = commits local has that remote doesn't (needs push)
  Future<Map<String, BranchAheadBehind>> branchAheadBehind(String repoPath) async {
    final map = <String, BranchAheadBehind>{};
    try {
      final res = await _run([
        'for-each-ref',
        '--format=%(refname:short) %(upstream:short)',
        'refs/heads'
      ], repoPath);
      if (res.exitCode != 0) return map;
      final lines = res.stdout.toString().split('\n');
      for (final l in lines) {
        final trimmed = l.trim();
        if (trimmed.isEmpty) continue;
        final parts = trimmed.split(RegExp(r"\s+"));
        if (parts.isEmpty) continue;
        final local = parts[0];
        final upstream = parts.length > 1 ? parts.sublist(1).join(' ') : '';
        if (upstream.isEmpty) continue;
        final cntRes = await _run(['rev-list', '--left-right', '--count', '$upstream...$local'], repoPath);
        if (cntRes.exitCode != 0) continue;
        final out = cntRes.stdout.toString().trim();
        if (out.isEmpty) continue;
        final nums = out.split(RegExp(r"\s+"));
        if (nums.length < 2) continue;
        final remoteOnly = int.tryParse(nums[0]) ?? 0; // pull
        final localOnly = int.tryParse(nums[1]) ?? 0; // push
        map[local] = BranchAheadBehind(pull: remoteOnly, push: localOnly);
      }
    } catch (_) {}
    return map;
  }

  /// Returns a map of local branch -> number of commits the upstream is ahead of local.
  /// Example: {'feature/x': 3} means remote has 3 commits that local doesn't (needs pull).
  Future<Map<String, int>> remoteAheadCountPerBranch(String repoPath) async {
    final map = <String, int>{};
    try {
      // List local branches and their upstream (may be empty)
      final res = await _run([
        'for-each-ref',
        '--format=%(refname:short) %(upstream:short)',
        'refs/heads'
      ], repoPath);
      if (res.exitCode != 0) return map;
      final lines = res.stdout.toString().split('\n');
      for (final l in lines) {
        final trimmed = l.trim();
        if (trimmed.isEmpty) continue;
        final parts = trimmed.split(RegExp(r"\s+"));
        if (parts.isEmpty) continue;
        final local = parts[0];
        final upstream = parts.length > 1 ? parts.sublist(1).join(' ') : '';
        if (upstream.isEmpty) continue;
        // Get counts: remoteOnly localOnly
        final cntRes = await _run(['rev-list', '--left-right', '--count', '$upstream...$local'], repoPath);
        if (cntRes.exitCode != 0) continue;
        final out = cntRes.stdout.toString().trim();
        if (out.isEmpty) continue;
        final nums = out.split(RegExp(r"\s+"));
        if (nums.length < 2) continue;
        final remoteOnly = int.tryParse(nums[0]) ?? 0;
        map[local] = remoteOnly;
      }
    } catch (_) {}
    return map;
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

  Future<List<String>> tags(String repoPath) async {
    final result = await _run(['tag', '--list'], repoPath);
    if (result.exitCode != 0) return [];
    return result.stdout
        .toString()
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<List<GitCommit>> recentCommits(String repoPath, {int limit = 20, int skip = 0, String? branch}) async {
    final format = '%h%x09%an%x09%ad%x09%s';
    final args = ['log', '-n', '$limit'];
    if (skip > 0) {
      args.addAll(['--skip', '$skip']);
    }
    args.addAll(['--date=short', '--pretty=format:$format']);
    if (branch != null && branch.trim().isNotEmpty) {
      args.add(branch.trim());
    }
    final result = await _run(args, repoPath);
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

  Future<List<Map<String, String>>> stashList(String repoPath) async {
    final res = await _run(['stash', 'list'], repoPath);
    if (res.exitCode != 0) return [];
    final lines = res.stdout.toString().split('\n').where((l) => l.trim().isNotEmpty);
    return lines.map((l) {
      final colon = l.indexOf(':');
      if (colon <= 0) return {'name': l.trim(), 'message': ''};
      final name = l.substring(0, colon).trim();
      final msg = l.substring(colon + 1).trim();
      return {'name': name, 'message': msg};
    }).toList();
  }

  Future<String> stashSave(String repoPath, String message, {bool includeUntracked = false, bool keepIndex = false}) async {
    final args = <String>['stash', 'push'];
    if (includeUntracked) args.add('--include-untracked');
    if (keepIndex) args.add('--keep-index');
    if (message.trim().isNotEmpty) {
      args.addAll(['-m', message]);
    }
    return await runGit(args, repoPath);
  }

  Future<String> stashApply(String repoPath, String name) async {
    return await runGit(['stash', 'apply', name], repoPath);
  }

  Future<String> stashPop(String repoPath, String name) async {
    return await runGit(['stash', 'pop', name], repoPath);
  }

  Future<String> stashDrop(String repoPath, String name) async {
    return await runGit(['stash', 'drop', name], repoPath);
  }

  Future<String> stashClear(String repoPath) async {
    return await runGit(['stash', 'clear'], repoPath);
  }

  Future<String> rebase(String repoPath, String upstream) async {
    if (upstream.trim().isEmpty) return 'Rebase upstream is empty.';
    return await runGit(['rebase', upstream], repoPath);
  }

  Future<String> rebaseContinue(String repoPath) async {
    return await runGit(['rebase', '--continue'], repoPath);
  }

  Future<String> rebaseAbort(String repoPath) async {
    return await runGit(['rebase', '--abort'], repoPath);
  }

  Future<String> rebaseSkip(String repoPath) async {
    return await runGit(['rebase', '--skip'], repoPath);
  }

  Future<bool> isRebaseInProgress(String repoPath) async {
    try {
      final merge = await _run(['rev-parse', '--git-path', 'rebase-merge'], repoPath);
      final apply = await _run(['rev-parse', '--git-path', 'rebase-apply'], repoPath);
      final mergeDir = merge.stdout.toString().trim();
      final applyDir = apply.stdout.toString().trim();
      if (mergeDir.isNotEmpty && await FileSystemEntity.isDirectory(mergeDir)) return true;
      if (applyDir.isNotEmpty && await FileSystemEntity.isDirectory(applyDir)) return true;
    } catch (_) {}
    return false;
  }

  Future<String> diffFile(String repoPath, GitChange change) async {
    final isConflict = _isConflictStatus(change.indexStatus, change.workTreeStatus);
    // For conflicts, build a composite view so both normal changes and conflict parts are visible.
    if (isConflict) {
      // Section 1: working tree diff (shows conflict markers plus other edits).
      final wtRes = await _run(['diff', '--color=never', '--', change.path], repoPath);
      final wtOut = wtRes.stdout.toString();
      final wtErr = wtRes.stderr.toString();

      final hasBase = await _stageBlobExists(repoPath, 1, change.path);
      final hasOurs = await _stageBlobExists(repoPath, 2, change.path);
      final hasTheirs = await _stageBlobExists(repoPath, 3, change.path);

      final buffer = StringBuffer();

      if (wtRes.exitCode == 0 && wtOut.trim().isNotEmpty) {
        buffer.writeln('===== WORKTREE vs INDEX (含冲突标记) =====');
        buffer.writeln(wtOut.trim());
        buffer.writeln();
      } else if (wtRes.exitCode != 0 && wtOut.trim().isEmpty) {
        buffer.writeln('===== WORKTREE DIFF FAILED =====');
        buffer.writeln(wtErr);
        buffer.writeln();
      }

      if (hasBase && hasOurs) {
        buffer.write(await _diffStages(repoPath, 1, 2, change.path, 'CURRENT (ours) vs BASE'));
      }
      if (hasBase && hasTheirs) {
        buffer.write(await _diffStages(repoPath, 1, 3, change.path, 'INCOMING (theirs) vs BASE'));
      }
      if (hasOurs && hasTheirs) {
        buffer.write(await _diffStages(repoPath, 2, 3, change.path, 'CURRENT (ours) vs INCOMING (theirs)'));
      }

      final text = buffer.toString();
      if (text.trim().isNotEmpty) return text;
      // Fall through to regular diff if nothing collected.
    }

    final args = <String>['diff'];
    if (change.staged && !isConflict) {
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

  Future<String> updateSubmodules(String repoPath) async {
    return await runGit(['submodule', 'update', '--init', '--recursive', '--force'], repoPath);
  }

  Future<String?> getConfig(String repoPath, String key, {bool global = false}) async {
    final args = ['config'];
    if (global) args.add('--global');
    args.add(key);
    final res = await _run(args, repoPath);
    if (res.exitCode != 0) return null;
    return res.stdout.toString().trim();
  }

  Future<String> setConfig(String repoPath, String key, String value, {bool global = false}) async {
    if (key.trim().isEmpty) return 'Config key is empty.';
    final args = ['config'];
    if (global) args.add('--global');
    args.addAll([key, value]);
    return await runGit(args, repoPath);
  }

  Future<String> unsetConfig(String repoPath, String key, {bool global = false}) async {
    if (key.trim().isEmpty) return 'Config key is empty.';
    final args = ['config'];
    if (global) args.add('--global');
    args.addAll(['--unset', key]);
    return await runGit(args, repoPath);
  }

  Future<bool> hasConflicts(String repoPath) async {
    try {
      final res = await _run(['status', '--porcelain'], repoPath);
      if (res.exitCode != 0) return false;
      final lines = res.stdout.toString().split('\n');
      for (final line in lines) {
        if (line.length < 3) continue;
        final x = line[0];
        final y = line[1];
        final pair = '$x$y';
        if (x == 'U' || y == 'U') return true;
        if (pair == 'AA' || pair == 'DD' || pair == 'AU' || pair == 'UA' || pair == 'UD' || pair == 'DU') {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<String> resolveConflictOurs(String repoPath, String path) async {
    if (path.trim().isEmpty) return 'Path is empty.';
    final res1 = await runGit(['checkout', '--ours', '--', path], repoPath);
    final res2 = await runGit(['add', '--', path], repoPath);
    return '$res1\n$res2';
  }

  Future<String> resolveConflictTheirs(String repoPath, String path) async {
    if (path.trim().isEmpty) return 'Path is empty.';
    final res1 = await runGit(['checkout', '--theirs', '--', path], repoPath);
    final res2 = await runGit(['add', '--', path], repoPath);
    return '$res1\n$res2';
  }

  Future<String> markConflictResolved(String repoPath, String path) async {
    if (path.trim().isEmpty) return 'Path is empty.';
    // Mark as resolved by staging the file
    return await runGit(['add', '--', path], repoPath);
  }

  Future<List<String>> conflictPaths(String repoPath) async {
    final result = await _run(['diff', '--name-only', '--diff-filter=U'], repoPath);
    if (result.exitCode != 0) return [];
    return result.stdout
        .toString()
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
}
