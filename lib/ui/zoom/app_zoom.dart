import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_zoom_storage.dart';

class AppZoomState {
  const AppZoomState({
    required this.scale,
    this.loaded = false,
  });

  final double scale;
  final bool loaded;

  int get percent => (scale * 100).round();

  AppZoomState copyWith({
    double? scale,
    bool? loaded,
  }) {
    return AppZoomState(
      scale: scale ?? this.scale,
      loaded: loaded ?? this.loaded,
    );
  }
}

class AppZoomController extends StateNotifier<AppZoomState> {
  AppZoomController() : super(const AppZoomState(scale: 1.0)) {
    _load();
  }

  static const List<double> levels = <double>[0.8, 0.9, 1.0, 1.1, 1.25, 1.5];

  Future<void> zoomIn() async {
    await setZoom(_nextLevel(up: true));
  }

  Future<void> zoomOut() async {
    await setZoom(_nextLevel(up: false));
  }

  Future<void> resetZoom() async {
    await setZoom(1.0);
  }

  Future<void> setZoom(double value) async {
    final normalized = _nearestLevel(value);
    state = state.copyWith(scale: normalized, loaded: true);
    await _save(normalized);
  }

  Future<void> reset() => resetZoom();

  Future<void> setScale(double value) => setZoom(value);

  double _nextLevel({required bool up}) {
    final current = state.scale;
    if (up) {
      for (final level in levels) {
        if (level > current + 0.001) {
          return level;
        }
      }
      return levels.last;
    }
    for (final level in levels.reversed) {
      if (level < current - 0.001) {
        return level;
      }
    }
    return levels.first;
  }

  double _nearestLevel(double value) {
    var best = levels.first;
    var bestDistance = (value - best).abs();
    for (final level in levels.skip(1)) {
      final distance = (value - level).abs();
      if (distance < bestDistance) {
        best = level;
        bestDistance = distance;
      }
    }
    return best;
  }

  Future<void> _load() async {
    try {
      final saved = await AppZoomStorage.readScale();
      if (saved == null) {
        state = state.copyWith(loaded: true);
        return;
      }
      state = AppZoomState(
        scale: _nearestLevel(saved),
        loaded: true,
      );
    } catch (_) {
      state = state.copyWith(scale: 1.0, loaded: true);
    }
  }

  Future<void> _save(double scale) async {
    try {
      await AppZoomStorage.writeScale(scale);
    } catch (_) {
      // Zoom remains active for this session even if local persistence fails.
    }
  }
}

final appZoomProvider =
    StateNotifierProvider<AppZoomController, AppZoomState>((ref) {
  return AppZoomController();
});

class AppZoomHost extends ConsumerWidget {
  const AppZoomHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zoom = ref.watch(appZoomProvider);
    return Stack(
      children: [
        Positioned.fill(child: _ZoomedApp(scale: zoom.scale, child: child)),
        const Positioned(
          right: 16,
          bottom: 16,
          child: SafeArea(child: AppZoomControls()),
        ),
      ],
    );
  }
}

class _ZoomedApp extends StatelessWidget {
  const _ZoomedApp({required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        if (width <= 0 || height <= 0) {
          return child;
        }
        final logicalSize = Size(width / scale, height / scale);
        final media = MediaQuery.maybeOf(context);
        final wrappedChild = media == null
            ? child
            : MediaQuery(
                data: media.copyWith(size: logicalSize),
                child: child,
              );
        return ClipRect(
          child: Transform.scale(
            alignment: Alignment.topLeft,
            scale: scale,
            transformHitTests: true,
            child: SizedBox(
              width: logicalSize.width,
              height: logicalSize.height,
              child: wrappedChild,
            ),
          ),
        );
      },
    );
  }
}

class AppZoomControls extends ConsumerStatefulWidget {
  const AppZoomControls({super.key});

  @override
  ConsumerState<AppZoomControls> createState() => _AppZoomControlsState();
}

class _AppZoomControlsState extends ConsumerState<AppZoomControls> {
  bool _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    final zoom = ref.watch(appZoomProvider);
    final controller = ref.read(appZoomProvider.notifier);
    final canZoomOut = zoom.scale > AppZoomController.levels.first + 0.001;
    final canZoomIn = zoom.scale < AppZoomController.levels.last - 0.001;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_menuOpen) ...[
          Material(
            elevation: 8,
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 112,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final level in AppZoomController.levels)
                    TextButton(
                      onPressed: () async {
                        await controller.setZoom(level);
                        if (mounted) {
                          setState(() => _menuOpen = false);
                        }
                      },
                      child: Text('${(level * 100).round()} %'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Material(
          elevation: 8,
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  label: 'Zoom -',
                  button: true,
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: canZoomOut
                        ? () {
                            controller.zoomOut();
                          }
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _menuOpen = !_menuOpen),
                  child: Text('${zoom.percent} %'),
                ),
                Semantics(
                  label: 'Zoom +',
                  button: true,
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: canZoomIn
                        ? () {
                            controller.zoomIn();
                          }
                        : null,
                    icon: const Icon(Icons.add),
                  ),
                ),
                Semantics(
                  label: 'Zuruecksetzen auf 100 %',
                  button: true,
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: zoom.scale == 1.0
                        ? null
                        : () {
                            controller.resetZoom();
                          },
                    icon: const Icon(Icons.restart_alt),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
