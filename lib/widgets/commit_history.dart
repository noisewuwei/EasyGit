import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../git_service.dart';

class CommitHistoryPanel extends StatelessWidget {
  final List<GitCommit> recentCommits;
  final bool showDetails;
  final GitCommit? selectedCommit;
  final void Function(GitCommit commit) onSelectCommit;
  final bool detailsLoading;
  final String? detailsText;
  final ScrollController diffScrollController;

  const CommitHistoryPanel({
    super.key,
    required this.recentCommits,
    required this.showDetails,
    required this.selectedCommit,
    required this.onSelectCommit,
    required this.detailsLoading,
    required this.detailsText,
    required this.diffScrollController,
  });

  @override
  Widget build(BuildContext context) {
    final historyList = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            color: AppColors.background,
            child: recentCommits.isEmpty
                ? const Center(child: Text('No commits found.', style: TextStyle(color: AppColors.textMuted)))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: recentCommits.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (context, index) {
                      final commit = recentCommits[index];
                      final isSelected = showDetails && selectedCommit?.hash == commit.hash;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(commit.message, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${commit.hash} · ${commit.author} · ${commit.date}', style: const TextStyle(color: AppColors.textMuted)),
                        dense: true,
                        selected: isSelected,
                        selectedTileColor: AppColors.panel,
                        onTap: showDetails ? () => onSelectCommit(commit) : null,
                      );
                    },
                  ),
          ),
        ),
      ],
    );

    if (!showDetails) {
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
    if (selectedCommit == null) {
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
              Text(selectedCommit!.message, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('${selectedCommit!.hash} · ${selectedCommit!.author} · ${selectedCommit!.date}', style: const TextStyle(color: AppColors.textMuted)),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: Colors.black,
            child: detailsLoading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : detailsText == null
                    ? const Center(child: Text('No details loaded.', style: TextStyle(color: AppColors.textMuted)))
                    : Scrollbar(
                        controller: diffScrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: diffScrollController,
                          padding: const EdgeInsets.all(12),
                          child: SelectableText(detailsText!, style: const TextStyle(fontFamily: 'Consolas', fontSize: 12, color: AppColors.textPrimary)),
                        ),
                      ),
          ),
        ),
      ],
    );
  }
}
