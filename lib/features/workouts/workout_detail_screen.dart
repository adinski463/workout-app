import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/units.dart';
import '../../data/models/workout.dart';
import '../../providers.dart';
import '../browse/exercise_widgets.dart';
import '../builder/exercise_picker.dart';
import '../coverage/coverage_panel.dart';
import '../logging/session_screen.dart';
import '../shared/empty_state.dart';

/// A workout: its exercises, its coverage map, and the button that starts it.
///
/// Builder and viewer are the same screen. Splitting them would mean two
/// layouts to keep in sync for no gain, since every workout here is yours.
class WorkoutDetailScreen extends ConsumerWidget {
  const WorkoutDetailScreen({super.key, required this.workoutId});

  final String workoutId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workoutAsync = ref.watch(workoutProvider(workoutId));
    final coverageAsync = ref.watch(coverageProvider(workoutId));

    return workoutAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.error_outline,
          title: 'Could not load workout',
          message: '$error',
        ),
      ),
      data: (workout) {
        if (workout == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              icon: Icons.help_outline,
              title: 'Workout not found',
              message: 'It may have been deleted.',
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(workout.title),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete workout',
                onPressed: () => _confirmDelete(context, ref, workout),
              ),
            ],
          ),
          bottomNavigationBar: workout.items.isEmpty
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start workout'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              SessionScreen(workoutId: workout.id),
                        ),
                      ),
                    ),
                  ),
                ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (workout.isImported)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ImportedNote(workout: workout),
                ),

              Text(
                workout.items.isEmpty
                    ? 'No exercises yet'
                    : '${workout.items.length} exercises · '
                          '${workout.totalSets} sets · '
                          '~${workout.estimatedMinutes} min',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),

              if (workout.items.isEmpty)
                _EmptyBuilderPrompt(
                  onAdd: () => _addExercise(context, ref, workout.id),
                )
              else
                for (final item in workout.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ItemCard(
                      item: item,
                      onEdit: () => _editItem(context, ref, item),
                      onSwap: () => _swapItem(context, ref, item),
                      onRemove: () => _removeItem(ref, item),
                    ),
                  ),

              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add exercise'),
                onPressed: () => _addExercise(context, ref, workout.id),
              ),

              if (workout.items.isNotEmpty) ...[
                const SizedBox(height: 32),
                Text(
                  'Muscle coverage',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Shaded by how many working sets each part gets. '
                  'Tap a muscle for detail.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                coverageAsync.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (error, _) => Text('Could not build map: $error'),
                  data: (report) => CoveragePanel(report: report),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _addExercise(
    BuildContext context,
    WidgetRef ref,
    String workoutId,
  ) async {
    final slug = await ExercisePicker.show(context);
    if (slug == null) return;

    await ref.read(repositoryProvider).addItem(
      workoutId: workoutId,
      exerciseSlug: slug,
    );
    _invalidate(ref, workoutId);
  }

  Future<void> _editItem(
    BuildContext context,
    WidgetRef ref,
    WorkoutItem item,
  ) async {
    final updated = await showModalBottomSheet<WorkoutItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditItemSheet(item: item),
    );
    if (updated == null) return;

    await ref.read(repositoryProvider).updateItem(updated);
    _invalidate(ref, item.workoutId);
  }

  Future<void> _swapItem(
    BuildContext context,
    WidgetRef ref,
    WorkoutItem item,
  ) async {
    final slug = await SwapPicker.show(context, item.exerciseSlug);
    if (slug == null) return;

    await ref.read(repositoryProvider).swapExercise(item.id, slug);
    _invalidate(ref, item.workoutId);
  }

  Future<void> _removeItem(WidgetRef ref, WorkoutItem item) async {
    await ref.read(repositoryProvider).removeItem(item.id);
    _invalidate(ref, item.workoutId);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Workout workout,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete "${workout.title}"?'),
        content: const Text(
          'This also deletes the sets you logged for it. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref.read(workoutListProvider.notifier).delete(workout.id);
    if (context.mounted) Navigator.of(context).pop();
  }

  void _invalidate(WidgetRef ref, String workoutId) {
    ref.invalidate(workoutProvider(workoutId));
    ref.invalidate(coverageProvider(workoutId));
    ref.read(workoutListProvider.notifier).refresh();
  }
}

class _ItemCard extends ConsumerWidget {
  const _ItemCard({
    required this.item,
    required this.onEdit,
    required this.onSwap,
    required this.onRemove,
  });

  final WorkoutItem item;
  final VoidCallback onEdit;
  final VoidCallback onSwap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final exercise = catalog.exercise(item.exerciseSlug);
    final theme = Theme.of(context);

    if (exercise == null) {
      return Card(
        child: ListTile(
          title: Text('Unknown exercise (${item.exerciseSlug})'),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: onRemove,
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(exercise.name, style: theme.textTheme.titleSmall),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) => switch (value) {
                    'edit' => onEdit(),
                    'swap' => onSwap(),
                    'remove' => onRemove(),
                    _ => null,
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Sets and reps')),
                    PopupMenuItem(value: 'swap', child: Text('Swap exercise')),
                    PopupMenuItem(value: 'remove', child: Text('Remove')),
                  ],
                ),
              ],
            ),
            Text(
              '${item.targetSets} × ${item.targetReps}  ·  '
              '${formatRest(item.restSeconds)} rest',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            MuscleTagRow(exercise: exercise, showSecondary: false),
          ],
        ),
      ),
    );
  }
}

class _ImportedNote extends StatelessWidget {
  const _ImportedNote({required this.workout});

  final Workout workout;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.download_done, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              workout.sourceCreatorName == null
                  ? 'Your copy of an imported workout. Edits stay yours.'
                  : 'Your copy of ${workout.sourceCreatorName}\'s workout. '
                        'Edits stay yours.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyBuilderPrompt extends StatelessWidget {
  const _EmptyBuilderPrompt({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.playlist_add,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Add your first exercise',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'The coverage map appears once there is something to map.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onAdd, child: const Text('Add exercise')),
          ],
        ),
      ),
    );
  }
}

/// Sets, reps and rest for one exercise.
class _EditItemSheet extends StatefulWidget {
  const _EditItemSheet({required this.item});

  final WorkoutItem item;

  @override
  State<_EditItemSheet> createState() => _EditItemSheetState();
}

class _EditItemSheetState extends State<_EditItemSheet> {
  late int _sets = widget.item.targetSets;
  late int _reps = widget.item.targetReps;
  late int _rest = widget.item.restSeconds;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sets and reps',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          _Stepper(
            label: 'Sets',
            value: _sets,
            min: 1,
            max: 20,
            onChanged: (v) => setState(() => _sets = v),
          ),
          _Stepper(
            label: 'Reps',
            value: _reps,
            min: 1,
            max: 100,
            onChanged: (v) => setState(() => _reps = v),
          ),
          _Stepper(
            label: 'Rest',
            value: _rest,
            min: 0,
            max: 600,
            step: 15,
            format: formatRest,
            onChanged: (v) => setState(() => _rest = v),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(
              widget.item.copyWith(
                targetSets: _sets,
                targetReps: _reps,
                restSeconds: _rest,
              ),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.format,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final String Function(int)? format;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          IconButton.filledTonal(
            icon: const Icon(Icons.remove),
            onPressed: value <= min
                ? null
                : () => onChanged((value - step).clamp(min, max)),
          ),
          SizedBox(
            width: 72,
            child: Text(
              format?.call(value) ?? '$value',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton.filledTonal(
            icon: const Icon(Icons.add),
            onPressed: value >= max
                ? null
                : () => onChanged((value + step).clamp(min, max)),
          ),
        ],
      ),
    );
  }
}
