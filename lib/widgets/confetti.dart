import 'dart:math';

import 'package:flutter/material.dart';

/// A burst of confetti that falls once and then stays still.
class Confetti extends StatefulWidget {
  const Confetti({super.key, this.count = 120});

  final int count;

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..forward();
  late final List<_Piece> _pieces;

  static const _colors = [
    Color(0xFFFFC107),
    Color(0xFFFF5722),
    Color(0xFF4CAF50),
    Color(0xFF2196F3),
    Color(0xFFE91E63),
    Color(0xFFFFFFFF),
  ];

  @override
  void initState() {
    super.initState();
    final r = Random();
    _pieces = [
      for (var i = 0; i < widget.count; i++)
        _Piece(
          x: r.nextDouble(),
          vx: (r.nextDouble() - 0.5) * 0.6,
          vy: 0.4 + r.nextDouble() * 0.9,
          spin: (r.nextDouble() - 0.5) * 20,
          size: 5 + r.nextDouble() * 7,
          color: _colors[r.nextInt(_colors.length)],
        ),
    ];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      painter: _ConfettiPainter(_pieces, _controller),
      size: Size.infinite,
    ),
  );
}

class _Piece {
  _Piece({
    required this.x,
    required this.vx,
    required this.vy,
    required this.spin,
    required this.size,
    required this.color,
  });

  final double x, vx, vy, spin, size;
  final Color color;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.t) : super(repaint: t);

  final List<_Piece> pieces;
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    final fade = v < 0.75 ? 1.0 : (1 - v) / 0.25;
    final paint = Paint();
    for (final p in pieces) {
      final x = (p.x + p.vx * v) * size.width;
      // Start above the screen, fall with a little gravity.
      final y = (-0.1 + p.vy * v + 0.5 * v * v) * size.height;
      paint.color = p.color.withValues(alpha: fade);
      canvas
        ..save()
        ..translate(x, y)
        ..rotate(p.spin * v)
        ..drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 0.5,
          ),
          paint,
        )
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}
