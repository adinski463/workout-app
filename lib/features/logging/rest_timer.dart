import 'dart:async';

import 'package:flutter/material.dart';

/// Countdown state for the rest timer, driven by wall-clock time.
///
/// Deliberately not a tick-counter: if the screen sleeps or the app is
/// backgrounded between sets — which is exactly what happens while resting —
/// a counter that decrements per tick drifts or stalls. Comparing against an
/// end timestamp always recovers the true remaining time.
class RestTimerController extends ChangeNotifier {
  RestTimerController();

  Timer? _ticker;
  DateTime? _endsAt;
  int _totalSeconds = 0;

  bool get isRunning => _endsAt != null;
  int get totalSeconds => _totalSeconds;

  Duration get remaining {
    final endsAt = _endsAt;
    if (endsAt == null) return Duration.zero;
    final left = endsAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  double get progress {
    if (_totalSeconds == 0) return 0;
    return 1 - (remaining.inMilliseconds / (_totalSeconds * 1000));
  }

  void start(int seconds) {
    if (seconds <= 0) return;

    _totalSeconds = seconds;
    _endsAt = DateTime.now().add(Duration(seconds: seconds));

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (remaining == Duration.zero) {
        stop();
      } else {
        notifyListeners();
      }
    });

    notifyListeners();
  }

  void addSeconds(int seconds) {
    final endsAt = _endsAt;
    if (endsAt == null) return;
    _endsAt = endsAt.add(Duration(seconds: seconds));
    _totalSeconds += seconds;
    notifyListeners();
  }

  void stop() {
    _ticker?.cancel();
    _ticker = null;
    _endsAt = null;
    _totalSeconds = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

/// The rest countdown bar shown above the logging list once a set is completed.
class RestTimerBar extends StatelessWidget {
  const RestTimerBar({super.key, required this.controller});

  final RestTimerController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.isRunning) return const SizedBox.shrink();

        final scheme = Theme.of(context).colorScheme;
        final remaining = controller.remaining;
        final label =
            '${remaining.inMinutes}:'
            '${(remaining.inSeconds % 60).toString().padLeft(2, '0')}';

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.timer_outlined, color: scheme.onPrimaryContainer),
                  const SizedBox(width: 12),
                  Text(
                    'Rest  $label',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => controller.addSeconds(30),
                    child: const Text('+30s'),
                  ),
                  TextButton(
                    onPressed: controller.stop,
                    child: const Text('Skip'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: controller.progress.clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: scheme.onPrimaryContainer.withValues(
                    alpha: 0.2,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
