import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/units.dart';
import '../../data/repository.dart';
import '../../data/models/workout.dart';
import '../../providers.dart';
import '../shared/empty_state.dart';

/// Past sessions. Deliberately plain for now — charts and PR tracking are v2,
/// and an honest list of what you did beats a chart of three data points.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(recentSessionsProvider);
    final unit = ref.watch(unitProvider);
    final dateFormat = DateFormat('EEE d MMM');

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          PopupMenuButton<WeightUnit>(
            icon: const Icon(Icons.straighten),
            tooltip: 'Weight unit',
            initialValue: unit,
            onSelected: (value) =>
                ref.read(unitProvider.notifier).state = value,
            itemBuilder: (_) => const [
              PopupMenuItem(value: WeightUnit.kg, child: Text('Kilograms')),
              PopupMenuItem(value: WeightUnit.lb, child: Text('Pounds')),
            ],
          ),
        ],
      ),
      body: sessions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Could not load history',
          message: '$error',
        ),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.history,
                title: 'No sessions yet',
                message: 'Finish a workout and it will show up here.',
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final session = list[index];
                  final workout = ref.watch(
                    workoutProvider(session.workoutId),
                  );

                  return Card(
                    child: ListTile(
                      title: Text(
                        workout.maybeWhen(
                          data: (w) => w?.title ?? 'Deleted workout',
                          orElse: () => '…',
                        ),
                      ),
                      subtitle: Text(
                        '${dateFormat.format(session.startedAt)}  ·  '
                        '${formatDuration(session.duration)}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showModalBottomSheet<void>(
                        context: context,
                        showDragHandle: true,
                        builder: (_) => _SessionSheet(session: session),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// The sets recorded in one session, grouped by exercise.
class _SessionSheet extends ConsumerWidget {
  const _SessionSheet({required this.session});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final unit = ref.watch(unitProvider);
    final catalog = ref.watch(catalogProvider);
    final repo = ref.watch(repositoryProvider);

    return FutureBuilder<({List<SetLog> logs, Workout? workout})>(
      future: _load(repo),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final logs = snapshot.data!.logs;
        final workout = snapshot.data!.workout;

        // itemId -> exercise name, so the sheet reads as a training log rather
        // than a table of foreign keys.
        final names = {
          for (final item in workout?.items ?? const <WorkoutItem>[])
            item.id:
                catalog.exercise(item.exerciseSlug)?.name ?? item.exerciseSlug,
        };

        final grouped = <String, List<SetLog>>{};
        for (final log in logs) {
          grouped.putIfAbsent(log.workoutItemId, () => []).add(log);
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          shrinkWrap: true,
          children: [
            Text(workout?.title ?? 'Session', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${logs.length} set${logs.length == 1 ? '' : 's'}  ·  '
              '${formatDuration(session.duration)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            if (logs.isEmpty)
              const Text('No sets were recorded in this session.')
            else
              for (final entry in grouped.entries) ...[
                Text(
                  names[entry.key] ?? 'Removed exercise',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                for (final log in entry.value)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      'Set ${log.setNumber}  ·  '
                      '${formatSet(log.weightKg, log.repsDone, unit)}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                const SizedBox(height: 14),
              ],
          ],
        );
      },
    );
  }

  Future<({List<SetLog> logs, Workout? workout})> _load(
    WorkoutRepository repo,
  ) async {
    return (
      logs: await repo.logsForSession(session.id),
      workout: await repo.getWorkout(session.workoutId),
    );
  }
}
