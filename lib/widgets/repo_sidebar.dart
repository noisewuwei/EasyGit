import 'dart:io';
import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../git_service.dart';
import '../repo_page.dart';

class RepoSidebar extends StatelessWidget {
  final List<String> branches;
  final String? currentBranch;
  final List<String> remotes;
  final String? selectedRemote;
  final Map<String, List<String>> remoteBranches;
  final bool remoteBranchesLoading;
  final List<GitSubmodule> submodules;
  final String repoPath;

  final void Function(String branch) onCheckoutBranch;
  final void Function(String branch, bool isCurrent, Offset? pos) onShowBranchContextMenu;
  final void Function(String remoteBranch) onCheckoutRemoteBranch;

  const RepoSidebar({
    super.key,
    required this.branches,
    required this.currentBranch,
    required this.remotes,
    required this.selectedRemote,
    required this.remoteBranches,
    required this.remoteBranchesLoading,
    required this.submodules,
    required this.repoPath,
    required this.onCheckoutBranch,
    required this.onShowBranchContextMenu,
    required this.onCheckoutRemoteBranch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('BRANCHES'),
          Expanded(
            child: ListView.builder(
              itemCount: branches.length,
              itemBuilder: (context, index) {
                final branch = branches[index];
                final isCurrent = branch == currentBranch;
                return GestureDetector(
                  onSecondaryTapDown: (details) => onShowBranchContextMenu(branch, isCurrent, details.globalPosition),
                  onLongPress: () => onShowBranchContextMenu(branch, isCurrent, null),
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
                    onTap: () => onCheckoutBranch(branch),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          _sectionHeader('REMOTES'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: remotes.isEmpty
                ? const Text('No remotes', style: TextStyle(color: AppColors.textMuted))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: remotes
                        .map(
                          (remote) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(remote, style: TextStyle(fontSize: 13, color: selectedRemote == remote ? AppColors.textPrimary : AppColors.textSecondary)),
                          ),
                        )
                        .toList(),
                  ),
          ),
          if (selectedRemote != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              height: 160,
              child: remoteBranchesLoading
                  ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                  : remoteBranches[selectedRemote!]?.isEmpty ?? true
                      ? const Center(child: Text('No remote branches', style: TextStyle(color: AppColors.textMuted)))
                      : ListView.separated(
                          itemCount: remoteBranches[selectedRemote!]!.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                          itemBuilder: (context, index) {
                            final rb = remoteBranches[selectedRemote!]![index];
                            return ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              title: Text(rb, style: const TextStyle(fontSize: 13)),
                              trailing: IconButton(
                                icon: const Icon(Icons.download, size: 16),
                                tooltip: 'Checkout',
                                onPressed: () => onCheckoutRemoteBranch(rb),
                              ),
                            );
                          },
                        ),
            ),
          const Divider(height: 1, color: AppColors.border),
          _sectionHeader('SUBMODULES'),
          Expanded(
            child: submodules.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text('No submodules', style: TextStyle(color: AppColors.textMuted)),
                  )
                : ListView.separated(
                    itemCount: submodules.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (context, index) {
                      final sm = submodules[index];
                      final absolutePath = repoPath + Platform.pathSeparator + sm.path;
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

  Widget _sectionHeader(String title) {
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
}
