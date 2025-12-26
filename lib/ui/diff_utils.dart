import 'package:flutter/material.dart';
import 'app_colors.dart';

List<TextSpan> buildDiffSpans(String text, {TextStyle? baseStyle}) {
  final lines = text.split('\n');
  final spans = <TextSpan>[];
  final defaultStyle = baseStyle ?? const TextStyle(fontFamily: 'Consolas', fontSize: 12, color: AppColors.textPrimary);

  for (final line in lines) {
    TextStyle style = defaultStyle;
    if (line.startsWith('diff --git')) {
      style = defaultStyle.copyWith(color: AppColors.textMuted);
    } else if (line.startsWith('index ') || line.startsWith('--- ') || line.startsWith('+++ ')) {
      style = defaultStyle.copyWith(color: AppColors.textMuted);
    } else if (line.startsWith('@@')) {
      style = defaultStyle.copyWith(color: AppColors.accent);
    } else if (line.startsWith('+') && !line.startsWith('+++')) {
      style = defaultStyle.copyWith(color: AppColors.success);
    } else if (line.startsWith('-') && !line.startsWith('---')) {
      style = defaultStyle.copyWith(color: AppColors.danger);
    } else if (line.startsWith('commit ') || line.startsWith('Author:')) {
      style = defaultStyle.copyWith(fontWeight: FontWeight.w600);
    } else if (line.startsWith('Date:')) {
      style = defaultStyle.copyWith(color: AppColors.textMuted);
    }
    spans.add(TextSpan(text: line + '\n', style: style));
  }
  return spans;
}
