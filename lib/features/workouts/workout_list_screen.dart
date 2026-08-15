import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/workout.dart';
import '../../providers.dart';
import '../logging/session_screen.dart';
import '../shared/empty_state.dart';
import 'workout_detail_screen.dart';

/// Home: the workouts you can train today.
class WorkoutListScreen extends ConsumerWidget {
  const WorkoutListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workouts = ref.watch(workoutListProvider);
    final activeSession = ref.watch(activeSessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My workouts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createWorkout(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New workout'),
      ),
      body: Column(
        children: [
          // Surfaced first: an unfinished session means the user walked out
          // mid-workout or the app was killed. Losing that log would be the
          // most annoying possible bug, so resuming is the top action.
          activeSession.maybeWhen(
            data: (session) => session == null
                ? const SizedBox.shrink()
                : _ResumeBanner(session: session),
            orElse: () => const SizedBox.shrink(),
          ),
          Expanded(
            child: workouts.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (error, _) => EmptyState(
                icon: Icons.error_outline,
                title: 'Could not load workouts',
                message: '$error',
              ),
              data: (list) => list.isEmpty
                  ? EmptyState(
                      icon: Icons.fitness_center,
                      title: 'No workouts yet',
                      message:
                          'Build one from the exercise library, then log it '
                          'at the gym.',
                      action: FilledButton(
                        onPressed: () => _createWorkout(context, ref),
                        child: const Text('Build your first workout'),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () =>
                          ref.read(workoutListProvider.notifier).refresh(),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) =>
                            _WorkoutCard(workout: list[index]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createWorkout(BuildContext context, WidgetRef ref) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => const _NameWorkoutDialog(),
    );
    if (title == null || title.trim().isEmpty) return;

    final workout = await ref
        .read(workoutListProvider.notifier)
        .create(title: title.trim());

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkoutDetailScreen(workoutId: workout.id),
      ),
    );
  }
}

class _WorkoutCard extends ConsumerWidget {
  const _WorkoutCard({required this.workout});

  final Workout workout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final catalog = ref.watch(catalogProvider);

    // Show which muscle groups this workout covers, at a glance.
    final groups = <String>{};
    for (final item in workout.items) {
      final exercise = catalog.exercise(item.exerciseSlug);
      for (final slug in exercise?.primaryMuscles ?? const <String>[]) {
        final group = catalog.groupOf(slug);
        if (group != null) groups.add(group.name);
      }
    }

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => WorkoutDetailScreen(workoutId: workout.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      workout.title,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (workout.isImported)
                    Tooltip(
                      message: workout.sourceCreatorName == null
                          ? 'Imported'
                          : 'Imported from ${workout.sourceCreatorName}',
                      child: Icon(
                        Icons.download_done,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                workout.items.isEmpty
                    ? 'No exercises yet'
                    : '${workout.items.length} exercises · '
                          '${workout.totalSets} sets · '
                          '~${workout.estimatedMinutes} min',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (groups.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final name in groups)
                      Chip(
                        label: Text(name),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ResumeBanner extends ConsumerWidget {
  const _ResumeBanner({required this.session});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.play_circle_outline, color: scheme.onPrimaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Workout in progress',
              style: TextStyle(color: scheme.onPrimaryContainer),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SessionScreen(
                  workoutId: session.workoutId,
                  resumeSessionId: session.id,
                ),
              ),
            ),
            child: const Text('Resume'),
          ),
        ],
      ),
    );
  }
}

class _NameWorkoutDialog extends StatefulWidget {
  const _NameWorkoutDialog();

  @override
  State<_NameWorkoutDialog> createState() => _NameWorkoutDialogState();
}

class _NameWorkoutDialogState extends State<_NameWorkoutDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Name your workout'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Push day'),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Create'),
        ),
      ],
    );
  }
}
