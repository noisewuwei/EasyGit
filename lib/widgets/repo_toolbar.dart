import 'package:flutter/material.dart';
import '../ui/app_colors.dart';

class RepoToolbar extends StatelessWidget {
  final String? currentBranch;
  final String? selectedRemote;
  final bool busy;
  final VoidCallback onCreateBranch;
  final VoidCallback onPull;
  final VoidCallback onPush;
  final VoidCallback onToggleCommitOverlay;
  final VoidCallback onRefresh;

  const RepoToolbar({
    super.key,
    required this.currentBranch,
    required this.selectedRemote,
    required this.busy,
    required this.onCreateBranch,
    required this.onPull,
    required this.onPush,
    required this.onToggleCommitOverlay,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.call_split, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Text(currentBranch ?? '-', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: busy ? null : onCreateBranch,
            icon: const Icon(Icons.fork_right, size: 14),
            label: const Text('New'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
          ),
          const SizedBox(width: 24),
          const Icon(Icons.cloud_outlined, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Text(selectedRemote ?? '-', style: const TextStyle(color: AppColors.textSecondary)),
          const Spacer(),
          _actionButton('Pull', Icons.arrow_downward, onPull, busy),
          const SizedBox(width: 8),
          _actionButton('Push', Icons.arrow_upward, onPush, busy),
          const SizedBox(width: 8),
          _actionButton('Add', Icons.add, onToggleCommitOverlay, busy),
          const SizedBox(width: 8),
          IconButton(
            onPressed: busy ? null : onRefresh,
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }

  Widget _actionButton(String label, IconData icon, VoidCallback onPressed, bool busy) {
    return OutlinedButton.icon(
      onPressed: busy ? null : onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        side: const BorderSide(color: AppColors.border),
      ),
    );
  }
}
