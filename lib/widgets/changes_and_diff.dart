import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../git_service.dart';

class ChangesAndDiff extends StatelessWidget {
  final List<GitChange> unstaged;
  final List<GitChange> staged;
  final GitChange? selectedChange;
  final bool diffLoading;
  final String? diffText;
  final ScrollController diffScrollController;

  final void Function(GitChange change) onPreviewChange;
  final void Function(GitChange change) onStage;
  final void Function(GitChange change) onUnstage;
  final VoidCallback onStageAll;
  final VoidCallback onUnstageAll;
  final bool busy;

  const ChangesAndDiff({
    super.key,
    required this.unstaged,
    required this.staged,
    required this.selectedChange,
    required this.diffLoading,
    required this.diffText,
    required this.diffScrollController,
    required this.onPreviewChange,
    required this.onStage,
    required this.onUnstage,
    required this.onStageAll,
    required this.onUnstageAll,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(flex: 5, child: _changeColumns()),
        Container(width: 1, color: AppColors.border),
        Expanded(flex: 4, child: _diffPanel()),
      ],
    );
  }

  Widget _changeColumns() {
    return Row(
      children: [
        Expanded(child: _fileGroup('Unstaged Changes', unstaged, false)),
        Container(width: 1, color: AppColors.border),
        Expanded(child: _fileGroup('Staged Changes', staged, true)),
      ],
    );
  }

  Widget _fileGroup(String title, List<GitChange> files, bool isStaged) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            color: AppColors.panel,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Text('$title (${files.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(
                onPressed: busy
                    ? null
                    : () => isStaged
                        ? onUnstageAll()
                        : onStageAll(),
                child: Text(isStaged ? 'Unstage All' : 'Stage All'),
              ),
            ],
          ),
        ),
        Expanded(
          child: files.isEmpty
              ? const Center(child: Text('No files', style: TextStyle(color: AppColors.textMuted)))
              : ListView.separated(
                  itemCount: files.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (context, index) {
                    final file = files[index];
                    final isSelected = selectedChange != null &&
                        selectedChange!.path == file.path &&
                        selectedChange!.staged == file.staged;
                    return ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      leading: Icon(
                        Icons.insert_drive_file_outlined,
                        size: 16,
                        color: isStaged ? AppColors.success : AppColors.warning,
                      ),
                      title: Text(file.path, style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                        isStaged ? 'IDX: ${file.indexStatus}' : 'WT: ${file.workTreeStatus}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                      trailing: IconButton(
                        icon: Icon(isStaged ? Icons.remove : Icons.add, size: 16),
                        tooltip: isStaged ? 'Unstage' : 'Stage',
                        onPressed: busy
                            ? null
                            : () => isStaged
                                ? onUnstage(file)
                                : onStage(file),
                      ),
                      selected: isSelected,
                      selectedTileColor: AppColors.panel,
                      onTap: () => onPreviewChange(file),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _diffPanel() {
    final fileName = selectedChange?.path ?? 'Select a file to preview';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            color: AppColors.panel,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'DIFF PREVIEW',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1, color: AppColors.textMuted),
              ),
              const SizedBox(height: 4),
              Text(fileName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: Colors.black,
            child: diffLoading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : diffText == null
                    ? const Center(child: Text('Select a file from the list to view its diff.', style: TextStyle(color: AppColors.textMuted)))
                    : Scrollbar(
                        controller: diffScrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: diffScrollController,
                          padding: const EdgeInsets.all(12),
                          child: SelectableText.rich(
                            TextSpan(children: _buildDiffSpans(diffText!)),
                          ),
                        ),
                      ),
          ),
        ),
      ],
    );
  }

  List<TextSpan> _buildDiffSpans(String diff) {
    final lines = diff.split('\n');
    return lines
        .map(
          (line) => TextSpan(
            text: '$line\n',
            style: TextStyle(
              fontFamily: 'Consolas',
              fontSize: 12,
              color: _diffColorForLine(line),
            ),
          ),
        )
        .toList();
  }

  Color _diffColorForLine(String line) {
    if (line.startsWith('@@')) return AppColors.accent;
    if (line.startsWith('+') && !line.startsWith('+++')) return AppColors.success;
    if (line.startsWith('-') && !line.startsWith('---')) return AppColors.danger;
    if (line.startsWith('+++') || line.startsWith('---')) return AppColors.textSecondary;
    return AppColors.textPrimary;
  }
}
