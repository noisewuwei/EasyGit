import 'package:flutter/material.dart';
import '../ui/app_colors.dart';

class CommitPanel extends StatelessWidget {
  final TextEditingController messageController;
  final List<String> commitTypes;
  final String selectedCommitType;
  final ValueChanged<String> onSelectedCommitTypeChanged;
  final bool generating;
  final bool busy;
  final VoidCallback onGenerate;
  final VoidCallback onCommit;

  const CommitPanel({
    super.key,
    required this.messageController,
    required this.commitTypes,
    required this.selectedCommitType,
    required this.onSelectedCommitTypeChanged,
    required this.generating,
    required this.busy,
    required this.onGenerate,
    required this.onCommit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('Type', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              Flexible(
                child: FractionallySizedBox(
                  widthFactor: 0.33,
                  child: DropdownButtonFormField<String>(
                    value: selectedCommitType,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Commit type',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: commitTypes
                        .map((t) => DropdownMenuItem<String>(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (busy || generating)
                        ? null
                        : (value) {
                            if (value != null) {
                              onSelectedCommitTypeChanged(value);
                            }
                          },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              controller: messageController,
              expands: true,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                hintText: 'Commit message...',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (busy || generating) ? null : onGenerate,
                  icon: generating
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.bolt, size: 14),
                  label: const Text('Generate'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: busy ? null : onCommit,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Commit'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
