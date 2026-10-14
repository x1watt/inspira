import 'package:flutter/material.dart';

import '../data/image_repository.dart';

/// Full-screen artwork with a slow zoom and a dark gradient for legible
/// text. Without art it falls back to a gradient.
class ArtBackground extends StatefulWidget {
  const ArtBackground({super.key, required this.art, required this.seed});

  final ArtImage? art;

  /// Picks the fallback colors and the zoom direction.
  final int seed;

  @override
  State<ArtBackground> createState() => _ArtBackgroundState();
}

class _ArtBackgroundState extends State<ArtBackground>
    with SingleTickerProviderStateMixin {
  // One slow zoom per page view, not repeating, so the page settles.
  late final _zoom = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 25),
  )..forward();

  static const _fallbacks = [
    [Color(0xFF3E2723), Color(0xFF0D0D0D)],
    [Color(0xFF1A237E), Color(0xFF0D0D0D)],
    [Color(0xFF004D40), Color(0xFF0D0D0D)],
    [Color(0xFF4A148C), Color(0xFF0D0D0D)],
    [Color(0xFF263238), Color(0xFF0D0D0D)],
  ];

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final art = widget.art;
    final align = widget.seed.isEven ? Alignment.topCenter : Alignment.center;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (art == null)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _fallbacks[widget.seed % _fallbacks.length],
              ),
            ),
          )
        else
          ScaleTransition(
            scale: Tween(
              begin: 1.0,
              end: 1.12,
            ).animate(CurvedAnimation(parent: _zoom, curve: Curves.easeOut)),
            alignment: align,
            child: Image.asset(
              art.asset,
              fit: BoxFit.cover,
              alignment: align,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
            ),
          ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              // Dark at the top for the streak bar; the text has its own
              // dimmed panel, so the rest of the picture stays bright.
              stops: [0, 0.2, 0.7, 1],
              colors: [
                Color(0x99000000),
                Color(0x00000000),
                Color(0x00000000),
                Color(0x66000000),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
