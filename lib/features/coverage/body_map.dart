import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/catalog/catalog_models.dart';
import '../../data/coverage.dart';

/// Front and back body diagrams shaded by how much work each sub-muscle got.
///
/// Drawn with [CustomPaint] rather than an SVG asset so each region is a real
/// hit-testable shape: tapping a muscle tells you its volume, which is what
/// turns the picture from decoration into a tool.
class BodyMap extends StatelessWidget {
  const BodyMap({
    super.key,
    required this.report,
    this.onMuscleTap,
    this.highlighted,
  });

  final CoverageReport report;
  final void Function(Muscle muscle)? onMuscleTap;

  /// Slug drawn with an outline, used to show which muscle is selected.
  final String? highlighted;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Two figures side by side, each in a 1:2.2 portrait box.
        final width = (constraints.maxWidth - 12) / 2;
        final height = width * 2.2;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Figure(
              side: BodySide.front,
              report: report,
              size: Size(width, height),
              onMuscleTap: onMuscleTap,
              highlighted: highlighted,
            ),
            const SizedBox(width: 12),
            _Figure(
              side: BodySide.back,
              report: report,
              size: Size(width, height),
              onMuscleTap: onMuscleTap,
              highlighted: highlighted,
            ),
          ],
        );
      },
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.side,
    required this.report,
    required this.size,
    required this.onMuscleTap,
    required this.highlighted,
  });

  final BodySide side;
  final CoverageReport report;
  final Size size;
  final void Function(Muscle muscle)? onMuscleTap;
  final String? highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final regions = BodyRegions.forSide(side);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTapUp: onMuscleTap == null
              ? null
              : (details) {
                  final slug = BodyRegions.hitTest(
                    regions,
                    details.localPosition,
                    size,
                  );
                  if (slug == null) return;
                  final muscle = report.catalog.muscle(slug);
                  if (muscle != null) onMuscleTap!(muscle);
                },
          child: CustomPaint(
            size: size,
            painter: _BodyPainter(
              regions: regions,
              report: report,
              scheme: scheme,
              highlighted: highlighted,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          side == BodySide.front ? 'Front' : 'Back',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _BodyPainter extends CustomPainter {
  _BodyPainter({
    required this.regions,
    required this.report,
    required this.scheme,
    required this.highlighted,
  });

  final List<BodyRegion> regions;
  final CoverageReport report;
  final ColorScheme scheme;
  final String? highlighted;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = CoverageColors.outline(scheme);

    for (final region in regions) {
      final path = region.toPath(size);

      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..color = CoverageColors.forBand(
            report.bandFor(region.muscleSlug),
            scheme,
          ),
      );

      canvas.drawPath(path, outline);

      if (region.muscleSlug == highlighted) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = scheme.tertiary,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BodyPainter old) =>
      old.report != report ||
      old.highlighted != highlighted ||
      old.scheme != scheme;
}

/// One shaded muscle region, stored in a 0..1 coordinate space so it scales to
/// any size. Shapes are stylised blocks rather than an anatomical drawing —
/// enough to read at a glance on a phone, and cheap to adjust.
@immutable
class BodyRegion {
  const BodyRegion(this.muscleSlug, this.points);

  final String muscleSlug;

  /// Polygon vertices, each component in the range 0..1.
  final List<Offset> points;

  Path toPath(Size size) {
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final p = Offset(points[i].dx * size.width, points[i].dy * size.height);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path..close();
  }
}

/// The region geometry for both figures.
///
/// Left/right pairs share a muscle slug: coverage is not tracked per side, so
/// tapping either arm reports the same muscle.
class BodyRegions {
  static List<BodyRegion> forSide(BodySide side) =>
      side == BodySide.front ? _front : _back;

  /// Returns the muscle slug under [point], or null for a tap on empty space.
  /// Later regions win, matching paint order.
  static String? hitTest(
    List<BodyRegion> regions,
    Offset point,
    Size size,
  ) {
    for (final region in regions.reversed) {
      if (region.toPath(size).contains(point)) return region.muscleSlug;
    }
    return null;
  }

  static const _front = <BodyRegion>[
    // Head and neck are drawn for shape only and carry no muscle.
    BodyRegion('', [
      Offset(0.42, 0.02), Offset(0.58, 0.02),
      Offset(0.58, 0.09), Offset(0.42, 0.09),
    ]),

    // Shoulders
    BodyRegion('delts-front', [
      Offset(0.20, 0.12), Offset(0.32, 0.10),
      Offset(0.34, 0.19), Offset(0.22, 0.21),
    ]),
    BodyRegion('delts-front', [
      Offset(0.80, 0.12), Offset(0.68, 0.10),
      Offset(0.66, 0.19), Offset(0.78, 0.21),
    ]),
    BodyRegion('delts-side', [
      Offset(0.16, 0.13), Offset(0.20, 0.12),
      Offset(0.22, 0.22), Offset(0.17, 0.22),
    ]),
    BodyRegion('delts-side', [
      Offset(0.84, 0.13), Offset(0.80, 0.12),
      Offset(0.78, 0.22), Offset(0.83, 0.22),
    ]),

    // Chest, split into the three regions the app is built around.
    BodyRegion('chest-upper', [
      Offset(0.34, 0.11), Offset(0.66, 0.11),
      Offset(0.66, 0.155), Offset(0.34, 0.155),
    ]),
    BodyRegion('chest-mid', [
      Offset(0.34, 0.155), Offset(0.66, 0.155),
      Offset(0.66, 0.20), Offset(0.34, 0.20),
    ]),
    BodyRegion('chest-lower', [
      Offset(0.35, 0.20), Offset(0.65, 0.20),
      Offset(0.63, 0.235), Offset(0.37, 0.235),
    ]),

    // Arms
    BodyRegion('biceps-long', [
      Offset(0.17, 0.22), Offset(0.24, 0.22),
      Offset(0.24, 0.31), Offset(0.18, 0.31),
    ]),
    BodyRegion('biceps-long', [
      Offset(0.83, 0.22), Offset(0.76, 0.22),
      Offset(0.76, 0.31), Offset(0.82, 0.31),
    ]),
    BodyRegion('biceps-short', [
      Offset(0.13, 0.22), Offset(0.17, 0.22),
      Offset(0.18, 0.31), Offset(0.14, 0.31),
    ]),
    BodyRegion('biceps-short', [
      Offset(0.87, 0.22), Offset(0.83, 0.22),
      Offset(0.82, 0.31), Offset(0.86, 0.31),
    ]),
    BodyRegion('brachialis', [
      Offset(0.14, 0.31), Offset(0.24, 0.31),
      Offset(0.24, 0.35), Offset(0.15, 0.35),
    ]),
    BodyRegion('brachialis', [
      Offset(0.86, 0.31), Offset(0.76, 0.31),
      Offset(0.76, 0.35), Offset(0.85, 0.35),
    ]),
    BodyRegion('forearm-flexors', [
      Offset(0.15, 0.35), Offset(0.24, 0.35),
      Offset(0.23, 0.45), Offset(0.16, 0.45),
    ]),
    BodyRegion('forearm-flexors', [
      Offset(0.85, 0.35), Offset(0.76, 0.35),
      Offset(0.77, 0.45), Offset(0.84, 0.45),
    ]),

    // Core
    BodyRegion('abs-upper', [
      Offset(0.40, 0.235), Offset(0.60, 0.235),
      Offset(0.60, 0.30), Offset(0.40, 0.30),
    ]),
    BodyRegion('abs-lower', [
      Offset(0.40, 0.30), Offset(0.60, 0.30),
      Offset(0.59, 0.37), Offset(0.41, 0.37),
    ]),
    BodyRegion('obliques', [
      Offset(0.34, 0.235), Offset(0.40, 0.235),
      Offset(0.41, 0.37), Offset(0.35, 0.35),
    ]),
    BodyRegion('obliques', [
      Offset(0.66, 0.235), Offset(0.60, 0.235),
      Offset(0.59, 0.37), Offset(0.65, 0.35),
    ]),

    // Legs
    BodyRegion('adductors', [
      Offset(0.44, 0.40), Offset(0.56, 0.40),
      Offset(0.55, 0.52), Offset(0.45, 0.52),
    ]),
    BodyRegion('quads-rectus', [
      Offset(0.38, 0.40), Offset(0.44, 0.40),
      Offset(0.44, 0.60), Offset(0.38, 0.60),
    ]),
    BodyRegion('quads-rectus', [
      Offset(0.62, 0.40), Offset(0.56, 0.40),
      Offset(0.56, 0.60), Offset(0.62, 0.60),
    ]),
    BodyRegion('quads-lateral', [
      Offset(0.32, 0.40), Offset(0.38, 0.40),
      Offset(0.38, 0.60), Offset(0.33, 0.58),
    ]),
    BodyRegion('quads-lateral', [
      Offset(0.68, 0.40), Offset(0.62, 0.40),
      Offset(0.62, 0.60), Offset(0.67, 0.58),
    ]),
    BodyRegion('quads-medial', [
      Offset(0.38, 0.60), Offset(0.44, 0.60),
      Offset(0.44, 0.66), Offset(0.38, 0.65),
    ]),
    BodyRegion('quads-medial', [
      Offset(0.62, 0.60), Offset(0.56, 0.60),
      Offset(0.56, 0.66), Offset(0.62, 0.65),
    ]),

    // Lower leg, front view shows the shin: still shaded with calf work so the
    // figure does not read as an untrained gap.
    BodyRegion('calves-gastroc', [
      Offset(0.36, 0.70), Offset(0.44, 0.70),
      Offset(0.43, 0.86), Offset(0.37, 0.86),
    ]),
    BodyRegion('calves-gastroc', [
      Offset(0.64, 0.70), Offset(0.56, 0.70),
      Offset(0.57, 0.86), Offset(0.63, 0.86),
    ]),
  ];

  static const _back = <BodyRegion>[
    BodyRegion('', [
      Offset(0.42, 0.02), Offset(0.58, 0.02),
      Offset(0.58, 0.09), Offset(0.42, 0.09),
    ]),

    // Traps: the upper/mid/lower split is the reason this app exists.
    BodyRegion('traps-upper', [
      Offset(0.36, 0.09), Offset(0.64, 0.09),
      Offset(0.68, 0.15), Offset(0.32, 0.15),
    ]),
    BodyRegion('traps-mid', [
      Offset(0.38, 0.15), Offset(0.62, 0.15),
      Offset(0.62, 0.21), Offset(0.38, 0.21),
    ]),
    BodyRegion('traps-lower', [
      Offset(0.42, 0.21), Offset(0.58, 0.21),
      Offset(0.56, 0.27), Offset(0.44, 0.27),
    ]),
    BodyRegion('rhomboids', [
      Offset(0.40, 0.155), Offset(0.48, 0.155),
      Offset(0.48, 0.20), Offset(0.40, 0.20),
    ]),
    BodyRegion('rhomboids', [
      Offset(0.60, 0.155), Offset(0.52, 0.155),
      Offset(0.52, 0.20), Offset(0.60, 0.20),
    ]),

    BodyRegion('delts-rear', [
      Offset(0.20, 0.12), Offset(0.32, 0.10),
      Offset(0.34, 0.19), Offset(0.22, 0.21),
    ]),
    BodyRegion('delts-rear', [
      Offset(0.80, 0.12), Offset(0.68, 0.10),
      Offset(0.66, 0.19), Offset(0.78, 0.21),
    ]),

    BodyRegion('lats', [
      Offset(0.30, 0.17), Offset(0.40, 0.20),
      Offset(0.40, 0.30), Offset(0.33, 0.28),
    ]),
    BodyRegion('lats', [
      Offset(0.70, 0.17), Offset(0.60, 0.20),
      Offset(0.60, 0.30), Offset(0.67, 0.28),
    ]),

    BodyRegion('erectors', [
      Offset(0.44, 0.27), Offset(0.56, 0.27),
      Offset(0.56, 0.38), Offset(0.44, 0.38),
    ]),

    // Triceps
    BodyRegion('triceps-long', [
      Offset(0.17, 0.22), Offset(0.24, 0.22),
      Offset(0.24, 0.29), Offset(0.18, 0.29),
    ]),
    BodyRegion('triceps-long', [
      Offset(0.83, 0.22), Offset(0.76, 0.22),
      Offset(0.76, 0.29), Offset(0.82, 0.29),
    ]),
    BodyRegion('triceps-lateral', [
      Offset(0.13, 0.22), Offset(0.17, 0.22),
      Offset(0.18, 0.31), Offset(0.14, 0.31),
    ]),
    BodyRegion('triceps-lateral', [
      Offset(0.87, 0.22), Offset(0.83, 0.22),
      Offset(0.82, 0.31), Offset(0.86, 0.31),
    ]),
    BodyRegion('triceps-medial', [
      Offset(0.18, 0.29), Offset(0.24, 0.29),
      Offset(0.24, 0.35), Offset(0.19, 0.35),
    ]),
    BodyRegion('triceps-medial', [
      Offset(0.82, 0.29), Offset(0.76, 0.29),
      Offset(0.76, 0.35), Offset(0.81, 0.35),
    ]),
    BodyRegion('forearm-extensors', [
      Offset(0.15, 0.35), Offset(0.24, 0.35),
      Offset(0.23, 0.45), Offset(0.16, 0.45),
    ]),
    BodyRegion('forearm-extensors', [
      Offset(0.85, 0.35), Offset(0.76, 0.35),
      Offset(0.77, 0.45), Offset(0.84, 0.45),
    ]),

    // Glutes
    BodyRegion('glute-max', [
      Offset(0.38, 0.38), Offset(0.50, 0.38),
      Offset(0.50, 0.48), Offset(0.37, 0.47),
    ]),
    BodyRegion('glute-max', [
      Offset(0.62, 0.38), Offset(0.50, 0.38),
      Offset(0.50, 0.48), Offset(0.63, 0.47),
    ]),
    BodyRegion('glute-med', [
      Offset(0.32, 0.37), Offset(0.38, 0.38),
      Offset(0.37, 0.45), Offset(0.32, 0.43),
    ]),
    BodyRegion('glute-med', [
      Offset(0.68, 0.37), Offset(0.62, 0.38),
      Offset(0.63, 0.45), Offset(0.68, 0.43),
    ]),

    // Hamstrings
    BodyRegion('hams-lateral', [
      Offset(0.33, 0.48), Offset(0.40, 0.48),
      Offset(0.40, 0.66), Offset(0.34, 0.65),
    ]),
    BodyRegion('hams-lateral', [
      Offset(0.67, 0.48), Offset(0.60, 0.48),
      Offset(0.60, 0.66), Offset(0.66, 0.65),
    ]),
    BodyRegion('hams-medial', [
      Offset(0.40, 0.48), Offset(0.46, 0.48),
      Offset(0.46, 0.66), Offset(0.40, 0.66),
    ]),
    BodyRegion('hams-medial', [
      Offset(0.60, 0.48), Offset(0.54, 0.48),
      Offset(0.54, 0.66), Offset(0.60, 0.66),
    ]),

    // Calves
    BodyRegion('calves-gastroc', [
      Offset(0.35, 0.70), Offset(0.45, 0.70),
      Offset(0.44, 0.80), Offset(0.36, 0.80),
    ]),
    BodyRegion('calves-gastroc', [
      Offset(0.65, 0.70), Offset(0.55, 0.70),
      Offset(0.56, 0.80), Offset(0.64, 0.80),
    ]),
    BodyRegion('calves-soleus', [
      Offset(0.36, 0.80), Offset(0.44, 0.80),
      Offset(0.43, 0.88), Offset(0.37, 0.88),
    ]),
    BodyRegion('calves-soleus', [
      Offset(0.64, 0.80), Offset(0.56, 0.80),
      Offset(0.57, 0.88), Offset(0.63, 0.88),
    ]),
  ];
}

/// Legend explaining the shading, shown under the map.
class CoverageLegend extends StatelessWidget {
  const CoverageLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        for (final band in CoverageBand.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: CoverageColors.forBand(band, scheme),
                  border: Border.all(color: CoverageColors.outline(scheme)),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                CoverageColors.label(band),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
      ],
    );
  }
}
