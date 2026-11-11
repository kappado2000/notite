import 'package:flutter/material.dart';

import '../theme.dart';

/// Alegerea nuanței unui grup (carnet sau tip de parole): culoarea din
/// paletă, intensitatea și culoarea scrisului, cu o previzualizare.
class TintPicker extends StatelessWidget {
  const TintPicker({
    super.key,
    required this.color,
    required this.level,
    required this.text,
    required this.onChanged,
    this.sampleTitle = 'Exemplu',
    this.sampleIcon = Icons.book_outlined,
  });

  /// Indexul în [GroupTint.all].
  final int color;
  final int level;
  final TintText text;
  final void Function(int color, int level, TintText text) onChanged;
  final String sampleTitle;
  final IconData sampleIcon;

  @override
  Widget build(BuildContext context) {
    final tint = GroupTint.at(color).styled(level: level, text: text);
    final label = Theme.of(context).textTheme.titleSmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Culoare', style: label),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < GroupTint.all.length; i++)
              _Swatch(
                tint: GroupTint.all[i].styled(level: 2),
                selected: i == color,
                onTap: () => onChanged(i, level, text),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text('Intensitate', style: label),
            const Spacer(),
            Text(
              GroupTint.levelNames[level],
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ],
        ),
        Slider(
          value: level.toDouble(),
          min: 0,
          max: (GroupTint.levelNames.length - 1).toDouble(),
          divisions: GroupTint.levelNames.length - 1,
          activeColor: GroupTint.all[color].base,
          label: GroupTint.levelNames[level],
          onChanged: (v) => onChanged(color, v.round(), text),
        ),
        const SizedBox(height: 4),
        Text('Culoarea scrisului', style: label),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<TintText>(
            showSelectedIcon: false,
            segments: [
              for (final t in TintText.values)
                ButtonSegment(value: t, label: Text(t.label)),
            ],
            selected: {text},
            onSelectionChanged: (s) => onChanged(color, level, s.first),
          ),
        ),
        const SizedBox(height: 16),
        _Preview(tint: tint, title: sampleTitle, icon: sampleIcon),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.tint,
    required this.selected,
    required this.onTap,
  });
  final GroupTint tint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tint.name,
    child: InkResponse(
      onTap: onTap,
      radius: 24,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: tint.base,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 3,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, size: 20, color: Colors.white)
            : null,
      ),
    ),
  );
}

/// Cum arată un card al grupului cu setările alese.
class _Preview extends StatelessWidget {
  const _Preview({required this.tint, required this.title, required this.icon});
  final GroupTint tint;
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final accent = tint.onContainer(context);
    final fg = tint.textColor(context);
    return Container(
      decoration: BoxDecoration(
        color: tint.surface(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.55)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: tint.container(context),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          Divider(height: 18, color: accent.withValues(alpha: 0.18)),
          Text(
            'Așa arată un rând din grup',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Text secundar și data',
            style: TextStyle(fontSize: 13, color: fg.withValues(alpha: 0.72)),
          ),
        ],
      ),
    );
  }
}
