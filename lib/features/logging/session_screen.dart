import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/units.dart';
import '../../data/models/workout.dart';
import '../../providers.dart';
import '../shared/empty_state.dart';
import 'rest_timer.dart';

/// The gym screen: log every set, see what you did last time, rest, repeat.
///
/// Two rules shape this screen:
///   1. Nothing blocks on the network. Every tap writes locally and returns.
///   2. Last session's numbers are always visible next to the input, because
///      that is what turns a logger into something worth opening twice.
class SessionScreen extends ConsumerStatefulWidget {
  const SessionScreen({
    super.key,
    required this.workoutId,
    this.resumeSessionId,
  });

  final String workoutId;

  /// Set when picking up a session that was left open.
  final String? resumeSessionId;

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  final _restTimer = RestTimerController();

  String? _sessionId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepareSession();
  }

  @override
  void dispose() {
    _restTimer.dispose();
    super.dispose();
  }

  Future<void> _prepareSession() async {
    try {
      if (widget.resumeSessionId != null) {
        setState(() => _sessionId = widget.resumeSessionId);
        return;
      }

      final repo = ref.read(repositoryProvider);

      // Reuse an open session for this workout rather than starting a second
      // one — otherwise backing out and tapping Start again silently splits a
      // single gym visit into two.
      final existing = await repo.activeSession();
      final session = (existing != null && existing.workoutId == widget.workoutId)
          ? existing
          : await repo.startSession(widget.workoutId);

      if (!mounted) return;
      setState(() => _sessionId = session.id);
      ref.invalidate(activeSessionProvider);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final workoutAsync = ref.watch(workoutProvider(widget.workoutId));

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.error_outline,
          title: 'Could not start the session',
          message: _error!,
        ),
      );
    }

    final sessionId = _sessionId;
    if (sessionId == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return workoutAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
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

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _confirmLeave(workout, sessionId);
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(workout.title),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => _confirmLeave(workout, sessionId),
              ),
            ),
            bottomNavigationBar: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Finish workout'),
                  onPressed: () => _finish(sessionId),
                ),
              ),
            ),
            body: Column(
              children: [
                RestTimerBar(controller: _restTimer),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: workout.items.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _ExerciseLogCard(
                        item: workout.items[index],
                        sessionId: sessionId,
                        onSetCompleted: (restSeconds) =>
                            _restTimer.start(restSeconds),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _finish(String sessionId) async {
    await ref.read(repositoryProvider).finishSession(sessionId);
    ref.invalidate(activeSessionProvider);
    ref.invalidate(recentSessionsProvider);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmLeave(Workout workout, String sessionId) async {
    final logs = await ref.read(repositoryProvider).logsForSession(sessionId);
    if (!mounted) return;

    // Nothing logged yet: no reason to make the user think about it.
    if (logs.isEmpty) {
      await ref.read(repositoryProvider).abandonSession(sessionId);
      ref.invalidate(activeSessionProvider);
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Leave this workout?'),
        content: Text(
          'You have logged ${logs.length} set${logs.length == 1 ? '' : 's'}. '
          'Keep the session so you can come back to it, or discard it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('cancel'),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('discard'),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('keep'),
            child: const Text('Keep for later'),
          ),
        ],
      ),
    );

    if (!mounted || choice == null || choice == 'cancel') return;

    if (choice == 'discard') {
      await ref.read(repositoryProvider).abandonSession(sessionId);
    }
    ref.invalidate(activeSessionProvider);
    if (mounted) Navigator.of(context).pop();
  }
}

/// One exercise and its sets.
class _ExerciseLogCard extends ConsumerWidget {
  const _ExerciseLogCard({
    required this.item,
    required this.sessionId,
    required this.onSetCompleted,
  });

  final WorkoutItem item;
  final String sessionId;
  final void Function(int restSeconds) onSetCompleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    final exercise = catalog.exercise(item.exerciseSlug);
    final theme = Theme.of(context);
    final unit = ref.watch(unitProvider);

    final logs = ref.watch(sessionLogsProvider(sessionId));
    final lastTime = ref.watch(
      lastPerformanceProvider((
        exerciseSlug: item.exerciseSlug,
        sessionId: sessionId,
      )),
    );

    final lastBySet = lastTime.maybeWhen(
      data: (list) => {for (final l in list) l.setNumber: l},
      orElse: () => <int, SetLog>{},
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              exercise?.name ?? item.exerciseSlug,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 2),
            Text(
              'Target ${item.targetSets} × ${item.targetReps}  ·  '
              '${formatRest(item.restSeconds)} rest',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),

            for (var setNumber = 1;
                setNumber <= item.targetSets;
                setNumber++)
              _SetRow(
                key: ValueKey('${item.id}:$setNumber'),
                setNumber: setNumber,
                unit: unit,
                previous: lastBySet[setNumber],
                logged: logs.maybeWhen(
                  data: (map) => map['${item.id}:$setNumber'],
                  orElse: () => null,
                ),
                onSubmit: (weight, reps) async {
                  await ref.read(repositoryProvider).logSet(
                    sessionId: sessionId,
                    workoutItemId: item.id,
                    setNumber: setNumber,
                    weightKg: weight,
                    repsDone: reps,
                  );
                  ref.invalidate(sessionLogsProvider(sessionId));
                  onSetCompleted(item.restSeconds);
                },
                onClear: () async {
                  await ref.read(repositoryProvider).deleteSetLog(
                    sessionId: sessionId,
                    workoutItemId: item.id,
                    setNumber: setNumber,
                  );
                  ref.invalidate(sessionLogsProvider(sessionId));
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// A single set: weight, reps, and a tick to record it.
class _SetRow extends StatefulWidget {
  const _SetRow({
    super.key,
    required this.setNumber,
    required this.unit,
    required this.previous,
    required this.logged,
    required this.onSubmit,
    required this.onClear,
  });

  final int setNumber;
  final WeightUnit unit;

  /// What was done on this set number last session — the inline hint.
  final SetLog? previous;

  /// What has been logged for this set in the current session.
  final SetLog? logged;

  final Future<void> Function(double? weightKg, int? reps) onSubmit;
  final Future<void> Function() onClear;

  @override
  State<_SetRow> createState() => _SetRowState();
}

class _SetRowState extends State<_SetRow> {
  late final TextEditingController _weight = TextEditingController(
    text: _initialWeight(),
  );
  late final TextEditingController _reps = TextEditingController(
    text: _initialReps(),
  );

  String _initialWeight() {
    final logged = widget.logged?.weightKg;
    if (logged != null) return formatWeight(logged, widget.unit, withSuffix: false);
    // Pre-filling with last session's load means a normal set is one tap.
    final previous = widget.previous?.weightKg;
    return previous == null
        ? ''
        : formatWeight(previous, widget.unit, withSuffix: false);
  }

  String _initialReps() {
    final logged = widget.logged?.repsDone;
    if (logged != null) return '$logged';
    return widget.previous?.repsDone?.toString() ?? '';
  }

  @override
  void dispose() {
    _weight.dispose();
    _reps.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLogged = widget.logged != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '${widget.setNumber}',
              style: theme.textTheme.titleSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),

          // The whole reason this screen beats a notes app.
          SizedBox(
            width: 84,
            child: Text(
              widget.previous == null
                  ? '—'
                  : formatSet(
                      widget.previous!.weightKg,
                      widget.previous!.repsDone,
                      widget.unit,
                    ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),

          Expanded(
            child: _NumberField(
              controller: _weight,
              hint: widget.unit.suffix,
              allowDecimal: true,
              enabled: !isLogged,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _NumberField(
              controller: _reps,
              hint: 'reps',
              enabled: !isLogged,
            ),
          ),
          const SizedBox(width: 4),

          IconButton(
            icon: Icon(
              isLogged ? Icons.check_circle : Icons.check_circle_outline,
              color: isLogged ? scheme.primary : scheme.onSurfaceVariant,
            ),
            tooltip: isLogged ? 'Undo set' : 'Log set',
            onPressed: () async {
              if (isLogged) {
                await widget.onClear();
                return;
              }

              final weightValue = double.tryParse(
                _weight.text.replaceAll(',', '.'),
              );
              await widget.onSubmit(
                weightValue == null
                    ? null
                    : displayToKg(weightValue, widget.unit),
                int.tryParse(_reps.text),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.hint,
    this.allowDecimal = false,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String hint;
  final bool allowDecimal;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          allowDecimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]'),
        ),
      ],
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 10,
        ),
      ),
    );
  }
}
