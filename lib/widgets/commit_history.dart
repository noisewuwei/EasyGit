import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../ui/diff_utils.dart';
import '../git_service.dart';

class CommitHistoryPanel extends StatefulWidget {
  final List<GitCommit> recentCommits;
  final bool showDetails;
  final GitCommit? selectedCommit;
  final void Function(GitCommit commit) onSelectCommit;
  final void Function(GitCommit commit, String action)? onCommitAction;
  final bool detailsLoading;
  final String? detailsText;
  final ScrollController diffScrollController;
  final ScrollController historyScrollController;

  const CommitHistoryPanel({
    super.key,
    required this.recentCommits,
    required this.showDetails,
    required this.selectedCommit,
    required this.onSelectCommit,
    this.onCommitAction,
    required this.detailsLoading,
    required this.detailsText,
    required this.diffScrollController,
    required this.historyScrollController,
  });

  @override
  State<CommitHistoryPanel> createState() => _CommitHistoryPanelState();
}

class _CommitHistoryPanelState extends State<CommitHistoryPanel> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<GitCommit> get _filteredCommits {
    if (_searchQuery.isEmpty) return widget.recentCommits;
    final query = _searchQuery.toLowerCase();
    return widget.recentCommits.where((commit) {
      return commit.message.toLowerCase().contains(query) ||
             commit.author.toLowerCase().contains(query) ||
             commit.hash.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final commits = _filteredCommits;
    final historyList = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Search bar
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: AppColors.panel,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search commits (message, author, hash)...',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
          ),
        ),
        Expanded(
          child: Container(
            color: AppColors.background,
            child: commits.isEmpty
                ? Center(
                    child: Text(
                      _searchQuery.isEmpty ? 'No commits found.' : 'No commits match "$_searchQuery"',
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    controller: widget.historyScrollController,
                    itemCount: commits.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (context, index) {
                      final commit = commits[index];
                      final isSelected = widget.showDetails && widget.selectedCommit?.hash == commit.hash;
                      return GestureDetector(
                        onSecondaryTapDown: widget.onCommitAction == null
                          ? null
                          : (details) => _showCommitMenu(context, details.globalPosition, commit),
                        onLongPress: widget.onCommitAction == null
                          ? null
                          : () => _showCommitMenu(context, null, commit),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(commit.message, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${commit.hash} · ${commit.author} · ${commit.date}', style: const TextStyle(color: AppColors.textMuted)),
                          dense: true,
                          selected: isSelected,
                          selectedTileColor: AppColors.panel,
                          onTap: widget.showDetails ? () => widget.onSelectCommit(commit) : null,
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );

    if (!widget.showDetails) {
      return historyList;
    }

    return Row(
      children: [
        Expanded(flex: 3, child: historyList),
        Container(width: 1, color: AppColors.border),
        Expanded(flex: 4, child: _detailPanel()),
      ],
    );
  }

  Widget _detailPanel() {
    if (widget.selectedCommit == null) {
      return Container(
        color: AppColors.background,
        alignment: Alignment.center,
        child: const Text('Select a commit to view details.', style: TextStyle(color: AppColors.textMuted)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: AppColors.panel,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.selectedCommit!.message, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('${widget.selectedCommit!.hash} · ${widget.selectedCommit!.author} · ${widget.selectedCommit!.date}', style: const TextStyle(color: AppColors.textMuted)),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: Colors.black,
            child: widget.detailsLoading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : widget.detailsText == null
                    ? const Center(child: Text('No details loaded.', style: TextStyle(color: AppColors.textMuted)))
                    : Scrollbar(
                        controller: widget.diffScrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: widget.diffScrollController,
                          padding: const EdgeInsets.all(12),
                          child: SelectableText.rich(
                            TextSpan(children: buildDiffSpans(widget.detailsText!, baseStyle: const TextStyle(fontFamily: 'Consolas', fontSize: 12))),
                            style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
                          ),
                        ),
                      ),
          ),
        ),
      ],
    );
  }

  Future<void> _showCommitMenu(BuildContext context, Offset? position, GitCommit commit) async {
    if (widget.onCommitAction == null) return;
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
        PopupMenuItem<String>(value: 'revert', child: Text('Revert this commit')),
        PopupMenuItem<String>(value: 'cherry_pick', child: Text('Cherry-pick this commit')),
        PopupMenuDivider(),
        PopupMenuItem<String>(value: 'reset_soft', child: Text('Reset (soft) to here')),
        PopupMenuItem<String>(value: 'reset_mixed', child: Text('Reset (mixed) to here')),
        PopupMenuItem<String>(value: 'reset_hard', child: Text('Reset (hard) to here')),
        PopupMenuDivider(),
        PopupMenuItem<String>(value: 'rebase_selected', child: Text('Rebase current branch onto here')),
      ],
    );

    if (selected == null) return;
    widget.onCommitAction!(commit, selected);
  }
}
