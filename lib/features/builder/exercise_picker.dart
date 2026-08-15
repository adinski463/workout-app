import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/catalog/catalog_models.dart';
import '../../providers.dart';
import '../browse/exercise_widgets.dart';
import '../shared/empty_state.dart';

/// Full-screen exercise picker, used when adding to a workout.
///
/// Returns the chosen slug via [Navigator.pop].
class ExercisePicker extends ConsumerWidget {
  const ExercisePicker({super.key, this.title = 'Add exercise'});

  final String title;

  static Future<String?> show(BuildContext context, {String? title}) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ExercisePicker(title: title ?? 'Add exercise'),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exercises = ref.watch(filteredExercisesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          const ExerciseFilterBar(),
          const SizedBox(height: 8),
          Expanded(
            child: exercises.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off,
                    title: 'Nothing matches',
                    message: 'Try a different muscle or clear the filters.',
                  )
                : ListView.builder(
                    itemCount: exercises.length,
                    itemBuilder: (context, index) {
                      final exercise = exercises[index];
                      return ExerciseTile(
                        exercise: exercise,
                        trailing: const Icon(Icons.add_circle_outline),
                        onTap: () => Navigator.of(context).pop(exercise.slug),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Swap picker: replacements for one exercise, restricted to those sharing its
/// primary sub-muscles.
///
/// This is the constraint that makes swapping safe — you cannot accidentally
/// turn a rear delt exercise into a bicep curl and quietly open a gap in the
/// workout you just imported.
class SwapPicker extends ConsumerWidget {
  const SwapPicker({super.key, required this.currentSlug});

  final String currentSlug;

  static Future<String?> show(BuildContext context, String currentSlug) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SwapPicker(currentSlug: currentSlug),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final current = catalog.exercise(currentSlug);
    final candidates = catalog.swapCandidates(currentSlug);
    final theme = Theme.of(context);

    final targets = (current?.primaryMuscles ?? const <String>[])
        .map((s) => catalog.muscle(s)?.name)
        .whereType<String>()
        .join(', ');

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('Swap exercise', style: theme.textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              targets.isEmpty
                  ? 'Alternatives for ${current?.name ?? 'this exercise'}.'
                  : 'Alternatives that also train $targets, so your coverage '
                        'stays the same.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: candidates.isEmpty
                ? const EmptyState(
                    icon: Icons.swap_horiz,
                    title: 'No alternatives',
                    message: 'Nothing else in the library trains this exactly.',
                  )
                : ListView.builder(
                    controller: scrollController,
                    itemCount: candidates.length,
                    itemBuilder: (context, index) {
                      final Exercise candidate = candidates[index];
                      return ExerciseTile(
                        exercise: candidate,
                        trailing: const Icon(Icons.swap_horiz),
                        onTap: () =>
                            Navigator.of(context).pop(candidate.slug),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
