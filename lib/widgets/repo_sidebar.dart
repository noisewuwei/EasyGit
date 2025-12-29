import 'dart:io';
import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../git_service.dart';

class RepoSidebar extends StatelessWidget {
  final List<String> branches;
  final String? selectedBranch;
  final Map<String, int> branchPullCounts;
  final Map<String, int> branchPushCounts;
  final String? currentBranch;
  final List<String> remotes;
  final String? selectedRemote;
  final Map<String, List<String>> remoteBranches;
  final bool remoteBranchesLoading;
  final List<GitSubmodule> submodules;
  final String repoPath;
  final List<String> tags;

  final void Function(String branch) onSelectBranch;
  final void Function(String branch) onCheckoutBranch;
  final void Function(String branch, bool isCurrent, Offset? pos) onShowBranchContextMenu;
  final void Function(String remoteBranch) onCheckoutRemoteBranch;
  final void Function(String remoteBranch) onSelectRemoteBranch;
  final void Function(String tag) onSelectTag;
  final void Function(String tag) onCheckoutTag;
  final void Function(String repoPath) onOpenSubmodule;
  final VoidCallback onUpdateSubmodules;

  const RepoSidebar({
    super.key,
    required this.branches,
    required this.selectedBranch,
    required this.currentBranch,
    required this.remotes,
    required this.selectedRemote,
    required this.remoteBranches,
    required this.remoteBranchesLoading,
    required this.submodules,
    required this.repoPath,
    required this.branchPullCounts,
    required this.branchPushCounts,
    required this.tags,
    required this.onSelectBranch,
    required this.onCheckoutBranch,
    required this.onShowBranchContextMenu,
    required this.onCheckoutRemoteBranch,
    required this.onSelectRemoteBranch,
    required this.onSelectTag,
    required this.onCheckoutTag,
    required this.onOpenSubmodule,
    required this.onUpdateSubmodules,
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
                final isSelected = branch == selectedBranch;
                final pullCount = branchPullCounts[branch] ?? 0;
                final pushCount = branchPushCounts[branch] ?? 0;
                return GestureDetector(
                  onSecondaryTapDown: (details) => onShowBranchContextMenu(branch, isCurrent, details.globalPosition),
                  onLongPress: () => onShowBranchContextMenu(branch, isCurrent, null),
                  onTap: () => onSelectBranch(branch),
                  onDoubleTap: () => onCheckoutBranch(branch),
                  child: ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Icon(Icons.call_split, size: 16, color: isCurrent ? AppColors.accent : AppColors.textMuted),
                    title: Text(
                      branch,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isCurrent || isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isCurrent
                            ? AppColors.textPrimary
                            : isSelected
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                      ),
                    ),
                    selected: isCurrent || isSelected,
                    selectedTileColor: AppColors.panel,
                    trailing: (pullCount > 0 || pushCount > 0)
                        ? Wrap(
                            spacing: 6,
                            children: [
                              if (pullCount > 0)
                                _badge(
                                  icon: Icons.arrow_downward,
                                  color: AppColors.warning,
                                  textColor: Colors.black,
                                  count: pullCount,
                                ),
                              if (pushCount > 0)
                                _badge(
                                  icon: Icons.arrow_upward,
                                  color: AppColors.accent,
                                  textColor: Colors.white,
                                  count: pushCount,
                                ),
                            ],
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          _sectionHeader('REMOTES'),
          // Padding(
          //   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          //   child: remotes.isEmpty
          //       ? const Text('No remotes', style: TextStyle(color: AppColors.textMuted))
          //       : Column(
          //           crossAxisAlignment: CrossAxisAlignment.start,
          //           children: remotes
          //               .map(
          //                 (remote) => Padding(
          //                   padding: const EdgeInsets.only(bottom: 6),
          //                   child: Text(remote, style: TextStyle(fontSize: 13, color: selectedRemote == remote ? AppColors.textPrimary : AppColors.textSecondary)),
          //                 ),
          //               )
          //               .toList(),
          //         ),
          // ),
          if (selectedRemote != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              height: 160,
              child: remoteBranchesLoading
                  ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                  : remoteBranches[selectedRemote!]?.isEmpty ?? true
                      ? const Center(child: Text('No remote branches', style: TextStyle(color: AppColors.textMuted)))
                      : ListView.builder(
                          itemCount: remoteBranches[selectedRemote!]!.length,
                          itemBuilder: (context, index) {
                            final rb = remoteBranches[selectedRemote!]![index];
                            return Padding(
                              padding: EdgeInsets.only(bottom: index == remoteBranches[selectedRemote!]!.length - 1 ? 0 : 6),
                              child: GestureDetector(
                                onTap: () => onSelectRemoteBranch(rb),
                                onDoubleTap: () => onCheckoutRemoteBranch(rb),
                                child: ListTile(
                                  dense: true,
                                  visualDensity: VisualDensity.compact,
                                  title: Text(rb, style: const TextStyle(fontSize: 13)),
                                  selected: selectedBranch == rb,
                                  selectedTileColor: AppColors.panel,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            );
                          },
                        ),
            ),
          const Divider(height: 1, color: AppColors.border),
          _sectionHeader('TAGS'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            height: 160,
            child: tags.isEmpty
                ? const Center(child: Text('No tags', style: TextStyle(color: AppColors.textMuted)))
                : ListView.builder(
                    itemCount: tags.length,
                    itemBuilder: (context, index) {
                      final tag = tags[index];
                      return Padding(
                        padding: EdgeInsets.only(bottom: index == tags.length - 1 ? 0 : 6),
                        child: GestureDetector(
                          onTap: () => onSelectTag(tag),
                          onDoubleTap: () => onCheckoutTag(tag),
                          child: ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            leading: const Icon(Icons.local_offer, size: 16, color: AppColors.textMuted),
                            title: Text(tag, style: const TextStyle(fontSize: 13)),
                            selected: selectedBranch == tag,
                            selectedTileColor: AppColors.panel,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'SUBMODULES',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      letterSpacing: 1,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.update, size: 18, color: AppColors.textPrimary),
                  tooltip: 'Update all submodules',
                  onPressed: onUpdateSubmodules,
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: submodules.isEmpty
                  ? const Text('No submodules', style: TextStyle(color: AppColors.textMuted))
                  : ListView.builder(
                      itemCount: submodules.length,
                      itemBuilder: (context, index) {
                        final sm = submodules[index];
                        final absolutePath = repoPath + Platform.pathSeparator + sm.path;
                        return Padding(
                          padding: EdgeInsets.only(bottom: index == submodules.length - 1 ? 0 : 6),
                          child: GestureDetector(
                            onDoubleTap: () => onOpenSubmodule(absolutePath),
                            child: ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              leading: Icon(sm.initialized ? Icons.link : Icons.link_off, size: 16, color: sm.initialized ? AppColors.accent : AppColors.textMuted),
                              title: Text(sm.path, style: const TextStyle(fontSize: 13)),
                              subtitle: Text(sm.commit, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        );
                      },
                    ),
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

Widget _badge({required IconData icon, required Color color, required Color textColor, required int count}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: textColor),
        const SizedBox(width: 4),
        Text('$count', style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    ),
  );
}
