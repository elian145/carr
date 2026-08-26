import 'package:flutter/material.dart';

import '../dealer/dealer_socials.dart';

class DealerSocialBrandIcon extends StatelessWidget {
  const DealerSocialBrandIcon({
    super.key,
    required this.network,
    this.size = 36,
  });

  final DealerSocialNetwork network;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.28),
          gradient: _gradient,
          color: _gradient == null ? _background : null,
        ),
        child: Center(child: _glyph),
      ),
    );
  }

  Color get _background {
    switch (network) {
      case DealerSocialNetwork.facebook:
        return const Color(0xFF1877F2);
      case DealerSocialNetwork.instagram:
        return const Color(0xFFE4405F);
      case DealerSocialNetwork.tiktok:
        return const Color(0xFF111111);
    }
  }

  Gradient? get _gradient {
    if (network != DealerSocialNetwork.instagram) return null;
    return const LinearGradient(
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
      colors: [
        Color(0xFFF58529),
        Color(0xFFDD2A7B),
        Color(0xFF8134AF),
        Color(0xFF515BD4),
      ],
    );
  }

  Widget get _glyph {
    final glyphSize = size * 0.58;
    switch (network) {
      case DealerSocialNetwork.facebook:
        return Icon(Icons.facebook, size: glyphSize, color: Colors.white);
      case DealerSocialNetwork.instagram:
        return SizedBox(
          width: glyphSize,
          height: glyphSize,
          child: const CustomPaint(painter: _InstagramGlyphPainter()),
        );
      case DealerSocialNetwork.tiktok:
        return SizedBox(
          width: glyphSize,
          height: glyphSize,
          child: const CustomPaint(painter: _TikTokGlyphPainter()),
        );
    }
  }
}

class _InstagramGlyphPainter extends CustomPainter {
  const _InstagramGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.11
      ..strokeCap = StrokeCap.round;
    final pad = size.width * 0.08;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(pad, pad, size.width - pad * 2, size.height - pad * 2),
        Radius.circular(size.width * 0.22),
      ),
      stroke,
    );
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width * 0.18,
      stroke,
    );
    canvas.drawCircle(
      Offset(size.width * 0.72, size.height * 0.28),
      size.width * 0.055,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TikTokGlyphPainter extends CustomPainter {
  const _TikTokGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.14
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final note = Path()
      ..moveTo(size.width * 0.42, size.height * 0.78)
      ..quadraticBezierTo(
        size.width * 0.18,
        size.height * 0.62,
        size.width * 0.42,
        size.height * 0.48,
      )
      ..lineTo(size.width * 0.42, size.height * 0.16)
      ..quadraticBezierTo(
        size.width * 0.68,
        size.height * 0.22,
        size.width * 0.78,
        size.height * 0.42,
      );
    canvas.drawPath(note, white);
    canvas.drawCircle(
      Offset(size.width * 0.38, size.height * 0.74),
      size.width * 0.16,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
