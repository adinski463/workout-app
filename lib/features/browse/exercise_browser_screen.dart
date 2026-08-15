import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/catalog/catalog_models.dart';
import '../../providers.dart';
import '../shared/empty_state.dart';
import 'exercise_detail_screen.dart';
import 'exercise_widgets.dart';

/// Browse the whole exercise library, filtered by sub-muscle.
class ExerciseBrowserScreen extends ConsumerWidget {
  const ExerciseBrowserScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercises = ref.watch(filteredExercisesProvider);
    final filter = ref.watch(exerciseFilterProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Exercises')),
      body: Column(
        children: [
          const ExerciseFilterBar(),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  '${exercises.length} exercise'
                  '${exercises.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                if (!filter.isEmpty)
                  TextButton(
                    onPressed: () => ref
                        .read(exerciseFilterProvider.notifier)
                        .state = const ExerciseFilter(),
                    child: const Text('Clear filters'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: exercises.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off,
                    title: 'Nothing matches',
                    message: 'Try a different muscle or clear the filters.',
                  )
                : ListView.builder(
                    itemCount: exercises.length,
                    itemBuilder: (context, index) => ExerciseTile(
                      exercise: exercises[index],
                      onTap: () => _open(context, exercises[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Exercise exercise) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExerciseDetailScreen(slug: exercise.slug),
      ),
    );
  }
}
