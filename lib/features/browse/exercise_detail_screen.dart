import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/units.dart';
import '../../providers.dart';
import 'exercise_widgets.dart';

/// Everything known about one exercise: what it trains, how to do it, what you
/// have lifted on it, and what you could swap it for.
class ExerciseDetailScreen extends ConsumerWidget {
  const ExerciseDetailScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final exercise = catalog.exercise(slug);
    final theme = Theme.of(context);

    if (exercise == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Exercise not found')),
      );
    }

    final unit = ref.watch(unitProvider);
    final history = ref.watch(
      lastPerformanceProvider((exerciseSlug: slug, sessionId: null)),
    );
    final alternatives = catalog.swapCandidates(slug).take(6).toList();

    return Scaffold(
      appBar: AppBar(title: Text(exercise.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            children: [
              const ExerciseThumbnail(size: 72),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(exercise.name, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      [
                        exercise.equipment.label,
                        exercise.isCompound ? 'Compound' : 'Isolation',
                        if (exercise.difficulty != null)
                          exercise.difficulty!.name,
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (exercise.description != null) ...[
            const SizedBox(height: 20),
            Text('How to do it', style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(exercise.description!, style: theme.textTheme.bodyMedium),
          ],

          const SizedBox(height: 20),
          Text('Muscles worked', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          MuscleTagRow(exercise: exercise),
          const SizedBox(height: 6),
          Text(
            'Filled tags are the primary movers. Outlined tags assist.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 20),
          Text('Your last session', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          history.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Could not load history: $e'),
            data: (logs) => logs.isEmpty
                ? Text(
                    'No logged sets yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final log in logs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            'Set ${log.setNumber}  ·  '
                            '${formatSet(log.weightKg, log.repsDone, unit)}',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                    ],
                  ),
          ),

          if (alternatives.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Trains the same thing', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Alternatives that hit the same primary muscles.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            for (final alt in alternatives)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ExerciseTile(
                  exercise: alt,
                  dense: true,
                  onTap: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => ExerciseDetailScreen(slug: alt.slug),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
