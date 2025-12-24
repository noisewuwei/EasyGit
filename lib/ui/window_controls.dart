import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../utils/platform_utils.dart';
import 'app_colors.dart';

class WindowControls extends StatefulWidget {
  const WindowControls({super.key});

  @override
  State<WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (isDesktop) {
      windowManager.addListener(this);
      _syncState();
    }
  }

  Future<void> _syncState() async {
    if (!isDesktop) return;
    final value = await windowManager.isMaximized();
    if (mounted) setState(() => _isMaximized = value);
  }

  @override
  void dispose() {
    if (isDesktop) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowMaximize() => _syncState();

  @override
  void onWindowUnmaximize() => _syncState();

  @override
  Widget build(BuildContext context) {
    if (!isDesktop) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CaptionButton(
          tooltip: 'Minimize',
          icon: Icons.remove,
          action: _WindowAction.minimize,
        ),
        const SizedBox(width: 4),
        _CaptionButton(
          tooltip: _isMaximized ? 'Restore Down' : 'Maximize',
          icon: _isMaximized ? Icons.crop_square_rounded : Icons.check_box_outline_blank,
          action: _WindowAction.maximize,
          isMaximized: _isMaximized,
        ),
        const SizedBox(width: 4),
        const _CaptionButton(
          tooltip: 'Close',
          icon: Icons.close,
          action: _WindowAction.close,
          isDestructive: true,
        ),
      ],
    );
  }
}

enum _WindowAction { minimize, maximize, close }

class _CaptionButton extends StatefulWidget {
  final String tooltip;
  final IconData icon;
  final _WindowAction action;
  final bool isDestructive;
  final bool isMaximized;

  const _CaptionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.action,
    this.isDestructive = false,
    this.isMaximized = false,
  });

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.isDestructive ? AppColors.danger : AppColors.textPrimary;
    final bgColor = widget.isDestructive
        ? (_hovering ? AppColors.danger.withOpacity(0.15) : Colors.transparent)
        : (_hovering ? AppColors.border.withOpacity(0.3) : Colors.transparent);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            switch (widget.action) {
              case _WindowAction.minimize:
                await windowManager.minimize();
                break;
              case _WindowAction.maximize:
                if (widget.isMaximized) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
                break;
              case _WindowAction.close:
                await windowManager.close();
                break;
            }
          },
          child: Container(
            width: 38,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(widget.icon, size: 16, color: baseColor),
          ),
        ),
      ),
    );
  }
}
