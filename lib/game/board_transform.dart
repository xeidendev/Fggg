import 'dart:math' as math;
import 'dart:ui';

/// The camera view over the puzzle board (Unity CameraManager parity):
/// `center` in world space and `ortho` = half-height of the visible world.
typedef GameViewport = ({Offset center, double ortho});

/// Single source of truth for mapping between world space (the puzzle
/// engine's coordinate system) and screen space (Flutter logical pixels).
///
/// The painter AND the gesture handler MUST both be built from the same
/// BoardTransform instance (same view, same board size). That guarantees a
/// tap always lands exactly on the arrow you see under your finger.
///
/// v5.0 FATAL FIX: the old code computed the tap mapping with
/// `scale = ortho*2 / boardHeight` while the painter drew with
/// `scale = max(ortho*2/width, ortho*2/height)`. On any portrait phone
/// (height > width) those differ by factor height/width (~2.2x), so every
/// tap away from the board center was mapped far too close to the center
/// and activated the WRONG arrow. Both sides now share this class.
class BoardTransform {
  BoardTransform({required this.view, required this.boardSize});

  final GameViewport view;
  final Size boardSize;

  /// World units per logical pixel — identical to the painter's scale:
  /// the world is letterboxed inside the board, preserving aspect ratio.
  late final double scale = () {
    final worldToSize = view.ortho * 2;
    final scaleY = worldToSize / boardSize.height;
    final scaleX = worldToSize / boardSize.width;
    return math.max(scaleX, scaleY);
  }();

  /// Board pixel height covered by the visible world band.
  late final double worldBandHeight = view.ortho * 2 / scale;
  late final double worldBandWidth = view.ortho * 2 / scale;

  Offset worldToScreen(Offset p) {
    final dx = (p.dx - view.center.dx) / scale;
    final dy = -(p.dy - view.center.dy) / scale;
    return Offset(boardSize.width / 2 + dx, boardSize.height / 2 + dy);
  }

  Offset screenToWorld(Offset s) {
    final dx = (s.dx - boardSize.width / 2) * scale;
    final dy = -(s.dy - boardSize.height / 2) * scale;
    return Offset(view.center.dx + dx, view.center.dy + dy);
  }

  /// World-space distance that corresponds to [pixels] on screen.
  double pxToWorld(double pixels) => pixels * scale;

  /// Pixel-space distance that corresponds to [world] world units.
  double worldToPx(double world) => world / scale;
}
