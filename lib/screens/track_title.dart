import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';

/// Il titolo del brano nella AppBar.
///
/// Scorre solo quando non ci sta. Marquee affianca sempre copie del testo,
/// anche quando ce n'e' una sola che basta: un titolo corto come "Numb"
/// finiva ripetuto per tutta la larghezza della barra.
///
/// E' un widget a se' per lo stesso motivo di [LyricsTextSizeButton]: dentro
/// PlayerScreen si potrebbe provare solo montando l'intera schermata.
class TrackTitle extends StatelessWidget {
  final String text;

  /// Rimonta il Marquee a ogni traccia, cosi' riparte da capo.
  final String trackId;

  const TrackTitle({super.key, required this.text, required this.trackId});

  static const style = TextStyle(
    color: Colors.white,
    fontSize: 16,
    fontWeight: FontWeight.bold,
  );

  /// Vero quando il titolo non ci sta nella larghezza data.
  ///
  /// La direzione del testo non cambia la larghezza, quindi non la chiede.
  @visibleForTesting
  static bool serveMarquee(
    String text,
    double larghezza, [
    TextScaler scala = TextScaler.noScaling,
  ]) {
    if (text.isEmpty) return false;
    final misura = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: scala,
    )..layout();
    return misura.width > larghezza;
  }

  @override
  Widget build(BuildContext context) {
    // Marquee non accetta testo vuoto.
    if (text.isEmpty) return const Text('', style: style);

    return LayoutBuilder(
      builder: (context, constraints) {
        final scala = MediaQuery.textScalerOf(context);

        if (!serveMarquee(text, constraints.maxWidth, scala)) {
          return Text(text, style: style, maxLines: 1, textScaler: scala);
        }

        return Marquee(
          key: ValueKey(trackId),
          text: text,
          style: style,
          scrollAxis: Axis.horizontal,
          blankSpace: 50,
          velocity: 30,
          pauseAfterRound: const Duration(seconds: 2),
          startPadding: 0,
          accelerationDuration: const Duration(seconds: 1),
          accelerationCurve: Curves.linear,
          decelerationDuration: const Duration(milliseconds: 500),
          decelerationCurve: Curves.easeOut,
        );
      },
    );
  }
}
