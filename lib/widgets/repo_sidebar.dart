import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ui/app_colors.dart';
import '../git_service.dart';

class RepoSidebar extends StatefulWidget {
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
  final VoidCallback onCreateTag;
  final VoidCallback onShowChangelog;
  final void Function(String tag, String action)? onTagAction;

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
    required this.onCreateTag,
    required this.onShowChangelog,
    this.onTagAction,
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
  State<RepoSidebar> createState() => _RepoSidebarState();
}

class _RepoSidebarState extends State<RepoSidebar> {
  bool _branchesExpanded = true;
  bool _remotesExpanded = true;
  bool _tagsExpanded = true;
  bool _submodulesExpanded = true;

  @override
  void initState() {
    super.initState();
    _loadExpandedStates();
  }

  String _stateKey(String panel) => 'repo_sidebar.${widget.repoPath}.$panel.expanded';

  Future<void> _loadExpandedStates() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _branchesExpanded = prefs.getBool(_stateKey('branches')) ?? true;
      _remotesExpanded = prefs.getBool(_stateKey('remotes')) ?? true;
      _tagsExpanded = prefs.getBool(_stateKey('tags')) ?? true;
      _submodulesExpanded = prefs.getBool(_stateKey('submodules')) ?? true;
    });
  }

  Future<void> _saveExpandedState(String panel, bool expanded) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_stateKey(panel), expanded);
  }

  void _toggleBranches() {
    final next = !_branchesExpanded;
    setState(() => _branchesExpanded = next);
    _saveExpandedState('branches', next);
  }

  void _toggleRemotes() {
    final next = !_remotesExpanded;
    setState(() => _remotesExpanded = next);
    _saveExpandedState('remotes', next);
  }

  void _toggleTags() {
    final next = !_tagsExpanded;
    setState(() => _tagsExpanded = next);
    _saveExpandedState('tags', next);
  }

  void _toggleSubmodules() {
    final next = !_submodulesExpanded;
    setState(() => _submodulesExpanded = next);
    _saveExpandedState('submodules', next);
  }

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
          _sectionHeader(
            title: 'BRANCHES',
            expanded: _branchesExpanded,
            onToggle: _toggleBranches,
          ),
          if (_branchesExpanded) Expanded(child: _buildBranchesPanel()),
          const Divider(height: 1, color: AppColors.border),
          _sectionHeader(
            title: 'REMOTES',
            expanded: _remotesExpanded,
            onToggle: _toggleRemotes,
          ),
          if (_remotesExpanded) Expanded(child: _buildRemotesPanel()),
          const Divider(height: 1, color: AppColors.border),
          _sectionHeader(
            title: 'TAGS',
            expanded: _tagsExpanded,
            onToggle: _toggleTags,
            actions: [
              IconButton(
                tooltip: 'Generate changelog',
                icon: const Icon(Icons.receipt_long, size: 18, color: AppColors.textPrimary),
                onPressed: widget.onShowChangelog,
              ),
              IconButton(
                tooltip: 'Create tag',
                icon: const Icon(Icons.add, size: 18, color: AppColors.textPrimary),
                onPressed: widget.onCreateTag,
              ),
            ],
          ),
          if (_tagsExpanded) Expanded(child: _buildTagsPanel()),
          const Divider(height: 1, color: AppColors.border),
          _sectionHeader(
            title: 'SUBMODULES',
            expanded: _submodulesExpanded,
            onToggle: _toggleSubmodules,
            actions: [
              IconButton(
                icon: const Icon(Icons.update, size: 18, color: AppColors.textPrimary),
                tooltip: 'Update all submodules',
                onPressed: widget.onUpdateSubmodules,
              ),
            ],
          ),
          if (_submodulesExpanded) Expanded(child: _buildSubmodulesPanel()),
        ],
      ),
    );
  }

  Widget _buildBranchesPanel() {
    return ListView.builder(
      itemCount: widget.branches.length,
      itemBuilder: (context, index) {
        final branch = widget.branches[index];
        final isCurrent = branch == widget.currentBranch;
        final isSelected = branch == widget.selectedBranch;
        final pullCount = widget.branchPullCounts[branch] ?? 0;
        final pushCount = widget.branchPushCounts[branch] ?? 0;
        return GestureDetector(
          onSecondaryTapDown: (details) => widget.onShowBranchContextMenu(branch, isCurrent, details.globalPosition),
          onLongPress: () => widget.onShowBranchContextMenu(branch, isCurrent, null),
          onTap: () => widget.onSelectBranch(branch),
          onDoubleTap: () => widget.onCheckoutBranch(branch),
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
    );
  }

  Widget _buildRemotesPanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: widget.selectedRemote == null
          ? const Center(child: Text('No remote selected', style: TextStyle(color: AppColors.textMuted)))
          : widget.remoteBranchesLoading
              ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
              : widget.remoteBranches[widget.selectedRemote!]?.isEmpty ?? true
                  ? const Center(child: Text('No remote branches', style: TextStyle(color: AppColors.textMuted)))
                  : ListView.builder(
                      itemCount: widget.remoteBranches[widget.selectedRemote!]!.length,
                      itemBuilder: (context, index) {
                        final rb = widget.remoteBranches[widget.selectedRemote!]![index];
                        return Padding(
                          padding: EdgeInsets.only(bottom: index == widget.remoteBranches[widget.selectedRemote!]!.length - 1 ? 0 : 6),
                          child: GestureDetector(
                            onTap: () => widget.onSelectRemoteBranch(rb),
                            onDoubleTap: () => widget.onCheckoutRemoteBranch(rb),
                            child: ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              title: Text(rb, style: const TextStyle(fontSize: 13)),
                              selected: widget.selectedBranch == rb,
                              selectedTileColor: AppColors.panel,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        );
                      },
                    ),
    );
  }

  Widget _buildTagsPanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: widget.tags.isEmpty
          ? const Center(child: Text('No tags', style: TextStyle(color: AppColors.textMuted)))
          : ListView.builder(
              itemCount: widget.tags.length,
              itemBuilder: (context, index) {
                final tag = widget.tags[index];
                return Padding(
                  padding: EdgeInsets.only(bottom: index == widget.tags.length - 1 ? 0 : 6),
                  child: GestureDetector(
                    onSecondaryTapDown: (d) => _showTagContextMenu(context, tag, d.globalPosition),
                    onLongPress: () => _showTagContextMenu(context, tag, null),
                    onTap: () => widget.onSelectTag(tag),
                    onDoubleTap: () => widget.onCheckoutTag(tag),
                    child: ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      leading: const Icon(Icons.local_offer, size: 16, color: AppColors.textMuted),
                      title: Text(tag, style: const TextStyle(fontSize: 13)),
                      selected: widget.selectedBranch == tag,
                      selectedTileColor: AppColors.panel,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildSubmodulesPanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: widget.submodules.isEmpty
          ? const Text('No submodules', style: TextStyle(color: AppColors.textMuted))
          : ListView.builder(
              itemCount: widget.submodules.length,
              itemBuilder: (context, index) {
                final sm = widget.submodules[index];
                final absolutePath = widget.repoPath + Platform.pathSeparator + sm.path;
                return Padding(
                  padding: EdgeInsets.only(bottom: index == widget.submodules.length - 1 ? 0 : 6),
                  child: GestureDetector(
                    onDoubleTap: () => widget.onOpenSubmodule(absolutePath),
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
    );
  }

  Widget _sectionHeader({
    required String title,
    required bool expanded,
    required VoidCallback onToggle,
    List<Widget> actions = const [],
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                letterSpacing: 1,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...actions,
          IconButton(
            icon: Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: AppColors.textPrimary),
            tooltip: expanded ? 'Collapse' : 'Expand',
            onPressed: onToggle,
          ),
        ],
      ),
    );
  }

  Future<void> _showTagContextMenu(BuildContext context, String tag, Offset? position) async {
    if (widget.onTagAction == null) return;
    final overlayBox = Overlay.of(context).context.findRenderObject() as RenderBox?;
    final fallback = overlayBox != null ? overlayBox.size.center(Offset.zero) : Offset.zero;
    final pos = position ?? fallback;
    final rect = overlayBox != null
        ? RelativeRect.fromRect(Rect.fromLTWH(pos.dx, pos.dy, 0, 0), Offset.zero & overlayBox.size)
        : RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy);

    final selected = await showMenu<String>(
      context: context,
      position: rect,
      items: const [
        PopupMenuItem<String>(value: 'checkout_tag', child: Text('Checkout tag (detached HEAD)')),
        PopupMenuDivider(),
        PopupMenuItem<String>(value: 'push_tag', child: Text('Push tag')),
        PopupMenuItem<String>(value: 'delete_tag', child: Text('Delete tag (local)')),
        PopupMenuItem<String>(value: 'delete_remote_tag', child: Text('Delete tag (remote)')),
        PopupMenuDivider(),
        PopupMenuItem<String>(value: 'changelog_from_tag', child: Text('Changelog from this tag to HEAD')),
      ],
    );

    if (selected == null) return;
    widget.onTagAction!(tag, selected);
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
