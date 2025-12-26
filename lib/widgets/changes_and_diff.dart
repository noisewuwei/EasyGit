import 'package:flutter/material.dart';
import '../ui/app_colors.dart';
import '../ui/diff_utils.dart';
import '../git_service.dart';

class ChangesAndDiff extends StatelessWidget {
  final List<GitChange> unstaged;
  final List<GitChange> staged;
  final GitChange? selectedChange;
  final bool diffLoading;
  final String? diffText;
  final ScrollController diffScrollController;

  final void Function(GitChange change) onRestoreUnstaged;
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
    required this.onRestoreUnstaged,
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
                    return GestureDetector(
                      onSecondaryTapDown: isStaged || busy
                          ? null
                          : (details) => _showUnstagedContextMenu(context, details.globalPosition, file),
                      onLongPress: isStaged || busy
                          ? null
                          : () => _showUnstagedContextMenu(context, null, file),
                      child: ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        leading: Icon(
                          _iconForChange(file, isStaged),
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
                      ),
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
                            TextSpan(children: buildDiffSpans(diffText!, baseStyle: const TextStyle(fontFamily: 'Consolas', fontSize: 12))),
                          ),
                        ),
                      ),
          ),
        ),
      ],
    );
  }

  

  IconData _iconForChange(GitChange change, bool isStaged) {
    final status = (isStaged ? change.indexStatus : change.workTreeStatus).toUpperCase();
    if (status == '?' || status == 'A') return Icons.fiber_new;
    if (status == 'D') return Icons.delete_forever;
    return Icons.insert_drive_file_outlined;
  }

  Future<void> _showUnstagedContextMenu(BuildContext context, Offset? position, GitChange file) async {
    if (busy) return;
    // If no position provided (long press), center in overlay.
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
        PopupMenuItem<String>(value: 'restore', child: Text('Restore changes')),
      ],
    );

    if (selected == 'restore') {
      onRestoreUnstaged(file);
    }
  }
}
