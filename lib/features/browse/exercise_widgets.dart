import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/catalog/catalog_models.dart';
import '../../providers.dart';

/// The sub-muscle tags under an exercise name — the detail the whole app is
/// built to surface. Primary movers are filled, assisting muscles outlined.
class MuscleTagRow extends ConsumerWidget {
  const MuscleTagRow({
    super.key,
    required this.exercise,
    this.showSecondary = true,
  });

  final Exercise exercise;
  final bool showSecondary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelSmall;

    Widget tag(String slug, {required bool primary}) {
      final muscle = catalog.muscle(slug);
      if (muscle == null) return const SizedBox.shrink();

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: primary ? scheme.primaryContainer : Colors.transparent,
          border: Border.all(
            color: primary ? Colors.transparent : scheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          muscle.name,
          style: labelStyle?.copyWith(
            color: primary ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final slug in exercise.primaryMuscles) tag(slug, primary: true),
        if (showSecondary)
          for (final slug in exercise.secondaryMuscles)
            tag(slug, primary: false),
      ],
    );
  }
}

/// A single exercise row. [trailing] lets the same tile serve browsing,
/// picking and swapping.
class ExerciseTile extends StatelessWidget {
  const ExerciseTile({
    super.key,
    required this.exercise,
    this.onTap,
    this.trailing,
    this.dense = false,
  });

  final Exercise exercise;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: dense ? 10 : 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ExerciseThumbnail(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exercise.name,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${exercise.equipment.label}'
                    '${exercise.isCompound ? ' · Compound' : ' · Isolation'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (!dense) ...[
                    const SizedBox(height: 8),
                    MuscleTagRow(exercise: exercise, showSecondary: false),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

/// Placeholder for exercise imagery.
///
/// Image coverage in every free exercise library is uneven, so the absence of a
/// picture is the normal case, not an error state. A plain glyph reads better
/// than a broken image box — and keeps the layout stable when images do arrive.
class ExerciseThumbnail extends StatelessWidget {
  const ExerciseThumbnail({super.key, this.imageUrl, this.size = 44});

  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        Icons.fitness_center,
        size: size * 0.5,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

/// Search field plus muscle-group and sub-muscle filter chips.
///
/// Group chips appear first; picking one reveals its sub-muscles. That ordering
/// matters — showing 33 sub-muscles at once is unusable, and the group is what
/// people think in first ("shoulders") before they narrow ("rear delts").
class ExerciseFilterBar extends ConsumerWidget {
  const ExerciseFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final filter = ref.watch(exerciseFilterProvider);
    final notifier = ref.read(exerciseFilterProvider.notifier);

    final selected = filter.muscleSlug == null
        ? null
        : catalog.muscle(filter.muscleSlug!);
    final activeGroup = selected == null ? null : catalog.groupOf(selected.slug);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search exercises',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: filter.query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => notifier.update(
                        (f) => f.copyWith(query: ''),
                      ),
                    ),
            ),
            onChanged: (value) =>
                notifier.update((f) => f.copyWith(query: value)),
          ),
        ),
        const SizedBox(height: 12),

        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final group in catalog.groups)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(group.name),
                    selected: activeGroup?.slug == group.slug,
                    onSelected: (isOn) => notifier.update(
                      (f) => f.copyWith(
                        muscleSlug: () => isOn ? group.slug : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        if (activeGroup != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final sub in catalog.subMusclesOf(activeGroup.slug))
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(sub.name),
                      selected: filter.muscleSlug == sub.slug,
                      onSelected: (isOn) => notifier.update(
                        (f) => f.copyWith(
                          muscleSlug: () =>
                              isOn ? sub.slug : activeGroup.slug,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 8),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: const Text('Targets it directly'),
                  selected: filter.primaryOnly,
                  onSelected: (isOn) =>
                      notifier.update((f) => f.copyWith(primaryOnly: isOn)),
                ),
              ),
              for (final equipment in Equipment.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(equipment.label),
                    selected: filter.equipment == equipment,
                    onSelected: (isOn) => notifier.update(
                      (f) => f.copyWith(
                        equipment: () => isOn ? equipment : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
