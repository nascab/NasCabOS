part of '../video_trans_view.dart';

class _KeyValueRow extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle? valueStyle;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool selectable;
  final VoidCallback? onTap;

  const _KeyValueRow({
    required this.label,
    required this.value,
    this.valueStyle,
    this.maxLines,
    this.overflow,
    this.selectable = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = value.isEmpty ? '-' : value;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: onTap != null || !selectable || maxLines != null
              ? InkWell(
                  onTap: onTap,
                  child: Text(
                    text,
                    style: valueStyle ?? theme.textTheme.bodySmall,
                    maxLines: maxLines,
                    overflow: overflow,
                  ),
                )
              : SelectableText(
                  text,
                  style: valueStyle ?? theme.textTheme.bodySmall,
                ),
        ),
      ],
    );
  }
}
