import 'package:flutter/material.dart';

import '../../data/catalog/catalog_models.dart';
import '../../data/coverage.dart';
import 'body_map.dart';

/// The muscle coverage map plus the reading of it.
///
/// The map alone is decoration; the gap callouts underneath are the reason the
/// feature exists — spotting that a shoulder workout never trains rear delts is
/// the thing no other workout app tells you.
class CoveragePanel extends StatefulWidget {
  const CoveragePanel({super.key, required this.report});

  final CoverageReport report;

  @override
  State<CoveragePanel> createState() => _CoveragePanelState();
}

class _CoveragePanelState extends State<CoveragePanel> {
  Muscle? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final report = widget.report;
    final gaps = report.gaps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BodyMap(
          report: report,
          highlighted: _selected?.slug,
          onMuscleTap: (muscle) => setState(
            () => _selected = _selected?.slug == muscle.slug ? null : muscle,
          ),
        ),
        const SizedBox(height: 12),
        const CoverageLegend(),

        if (_selected != null) ...[
          const SizedBox(height: 16),
          _SelectedMuscleCard(
            muscle: _selected!,
            coverage: report.forMuscle(_selected!.slug),
            onDismiss: () => setState(() => _selected = null),
          ),
        ],

        if (gaps.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Gaps', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final gap in gaps)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _GapCallout(gap: gap),
            ),
        ],

        if (report.trained.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Volume by muscle', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final coverage in report.trained.take(8))
            _VolumeRow(coverage: coverage),
        ],
      ],
    );
  }
}

class _SelectedMuscleCard extends StatelessWidget {
  const _SelectedMuscleCard({
    required this.muscle,
    required this.coverage,
    required this.onDismiss,
  });

  final Muscle muscle;
  final MuscleCoverage? coverage;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sets = coverage?.weightedSets ?? 0;

    return Card(
      child: ListTile(
        title: Text(muscle.name),
        subtitle: Text(
          sets == 0
              ? 'Not trained in this workout'
              : '${_trim(sets)} working sets'
                    '${coverage!.hasPrimaryWork ? '' : ' (assisting only)'}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: IconButton(
          icon: const Icon(Icons.close),
          onPressed: onDismiss,
          tooltip: 'Dismiss',
        ),
      ),
    );
  }
}

class _GapCallout extends StatelessWidget {
  const _GapCallout({required this.gap});

  final MuscleGap gap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: scheme.tertiary, width: 3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: scheme.tertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              gap.describe(),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _VolumeRow extends StatelessWidget {
  const _VolumeRow({required this.coverage});

  final MuscleCoverage coverage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Ten weighted sets fills the bar — a normal upper bound for one session.
    final fraction = (coverage.weightedSets / 10).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              coverage.muscle.name,
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 32,
            child: Text(
              _trim(coverage.weightedSets),
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

String _trim(double value) =>
    value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);
