import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:variable_font_generator/src/geometry/bezier.dart';
import 'package:variable_font_generator/src/geometry/path.dart';
import 'package:variable_font_generator/src/geometry/polygon.dart';
import 'package:variable_font_generator/src/geometry/stroke_style.dart';
import 'package:variable_font_generator/src/geometry/stroke_template.dart';
import 'package:variable_font_generator/src/geometry/vec2.dart';

/// A single line or quadratic piece of a stroked centre line, together with the
/// unit tangents at its ends.
typedef _Element = ({
  Vec2 start,
  Vec2? control,
  Vec2 end,
  Vec2 startTangent,
  Vec2 endTangent,
});

/// A point of a contour under construction.
typedef _SidePoint = ({Vec2 position, bool onCurve});

/// A stretch of centre line between two cuts, and whether each of its ends is
/// a cut rather than a real end of the artwork.
typedef _Run = ({List<_Element> elements, bool startsAtCut, bool endsAtCut});

/// The corner geometry of a join the stroke turns into, as a closed loop.
typedef _Wedge = List<_SidePoint>;

/// Converts stroked centre lines into filled outlines.
///
/// Every point the stroker emits is an affine function of the stroke's half
/// width, so the whole outline is produced twice — once at a half width of zero
/// and once at one — and the two runs are subtracted to recover that function.
/// Because the number of points and every branch taken depend only on the
/// centre line's shape, re-stroking an icon at another weight can never change
/// its topology. That invariant is what makes the result storable as `gvar`
/// deltas.
@immutable
final class Stroker {
  /// Creates a stroker.
  const Stroker({
    this.cap = StrokeCap.butt,
    this.join = StrokeJoin.miter,
    this.miterLimit = 4,
    this.maxTurnAngle = defaultMaxTurnAngle,
    this.maxArcAngle = defaultMaxArcAngle,
    this.cubicTolerance = 0.005,
    this.cornerTolerance = 1e-4,
    this.innerJoinLimit = defaultInnerJoinLimit,
  });

  /// The default [maxTurnAngle].
  ///
  /// A quadratic is split until it bends by no more than 30 degrees, which
  /// keeps the control-point offset construction accurate.
  static const defaultMaxTurnAngle = math.pi / 6;

  /// The default [maxArcAngle].
  ///
  /// Round joins and caps are drawn as arcs spanning at most 45 degrees, which
  /// a single quadratic reproduces to within 0.3% of the radius.
  static const defaultMaxArcAngle = math.pi / 4;

  /// The default [innerJoinLimit].
  static const defaultInnerJoinLimit = 2.0;

  /// The half width the two sides of a closed sub path are told apart at.
  ///
  /// Small enough that no artwork is narrower than it, so that the side
  /// enclosing more area is always the outer one.
  static const _orientingHalfWidth = 1 / 64;

  /// How the ends of open sub paths are drawn.
  final StrokeCap cap;

  /// How corners are filled in.
  final StrokeJoin join;

  /// The largest ratio of miter length to stroke width before a [StrokeJoin]
  /// of [StrokeJoin.miter] falls back to [StrokeJoin.bevel].
  final double miterLimit;

  /// The largest angle, in radians, a single quadratic may bend by before it is
  /// split.
  final double maxTurnAngle;

  /// The largest angle, in radians, spanned by one quadratic of a round join or
  /// cap.
  final double maxArcAngle;

  /// How far, in the source coordinate system, a quadratic may deviate from the
  /// cubic it replaces.
  final double cubicTolerance;

  /// The smallest tangent change, in radians, still treated as a corner rather
  /// than as a smooth continuation.
  final double cornerTolerance;

  /// The largest ratio of inner-join spike length to half width before the
  /// inner corner point is dropped.
  ///
  /// On the inside of a turn the two offset lines cross; the crossing point is
  /// the exact inner corner, but it runs off to infinity as a path doubles back
  /// on itself, so very sharp reversals fall back to leaving the two offset
  /// points joined directly.
  final double innerJoinLimit;

  /// Strokes every sub path of [path] with a half width of one unit.
  ///
  /// [filled] mirrors the SVG `fill` property: when the shape is painted as
  /// well as stroked, a closed sub path becomes a single solid contour covering
  /// both the interior and the stroke, instead of an outline with a hole.
  StrokeTemplate strokePath(
    Path path, {
    bool filled = false,
    bool knockedOutWhenFilled = false,
  }) {
    var template = StrokeTemplate.empty;
    for (final subPath in path.subPaths) {
      template += strokeSubPath(
        subPath,
        filled: filled,
        knockedOutWhenFilled: knockedOutWhenFilled,
      );
    }
    return template;
  }

  /// Strokes a single [subPath].
  ///
  /// See [strokePath] for the meaning of [filled].
  StrokeTemplate strokeSubPath(
    SubPath subPath, {
    bool filled = false,
    bool knockedOutWhenFilled = false,
  }) {
    if (knockedOutWhenFilled) {
      // Something sitting inside a shape that the fill axis is about to make
      // solid. Drawn as it is, it would merge into the fill and vanish; instead
      // it is faded away as the fill closes while a reversed copy takes its
      // place, so that at full fill it reads as a gap cut out of the solid.
      final drawn = strokeSubPath(subPath, filled: filled);
      if (!subPath.closed && !_isImplicitlyClosed(_toElements(subPath))) {
        // An open stroke has no area once its width reaches zero, so narrowing
        // it is enough to make it disappear.
        return StrokeTemplate([
          for (final contour in drawn.contours)
            contour.withBehaviour(ContourFillBehaviour.fadeOut),
          for (final contour in drawn.contours)
            contour.reversed.withBehaviour(ContourFillBehaviour.knockOut),
        ]);
      }
      // A closed shape still encloses area with no stroke width left, so it is
      // shrunk onto a point instead, and the copy that replaces it is the shape
      // filled rather than merely outlined.
      final centre = _centroidOf(_toElements(subPath));
      final outer = drawn.contours.first;
      return StrokeTemplate([
        for (final contour in drawn.contours)
          contour.withBehaviour(ContourFillBehaviour.shrink, target: centre),
        outer.reversed.withBehaviour(ContourFillBehaviour.grow, target: centre),
      ]);
    }
    final elements = _toElements(subPath);
    if (elements.isEmpty) {
      // Every segment collapsed to a point. SVG still draws such a sub path as
      // a dot as long as its cap has an area, which icon sets use for details
      // too small to be worth a real shape.
      return subPath.segments.isEmpty
          ? StrokeTemplate.empty
          : _dot(subPath.start);
    }

    final runs = _splitAtSelfIntersections(
      elements,
      closed: subPath.closed || _isImplicitlyClosed(elements),
    );
    if (runs != null) {
      // The centre line crosses itself. Stroking it in one piece would make the
      // outline cross itself too, and the non-zero fill rule would then punch a
      // hole exactly where the two passes overlap. Cutting the path at every
      // crossing turns it into simple pieces whose outlines merely overlap,
      // which fills correctly. The round caps added at each cut sit inside the
      // stroke the neighbouring piece already draws, so nothing changes shape.
      var template = StrokeTemplate.empty;
      for (final run in runs) {
        template += StrokeTemplate([
          _orientSolid(
            _templateFromRuns(
              (halfWidth) => _openContour(
                run.elements,
                halfWidth,
                startCap: run.startsAtCut ? StrokeCap.round : cap,
                endCap: run.endsAtCut ? StrokeCap.round : cap,
              ),
            ),
          ),
          for (final sign in const [1, -1])
            ..._wedgesFromRuns(
              (halfWidth, wedges) =>
                  _openSide(run.elements, sign, halfWidth, wedges: wedges),
            ),
        ]);
      }
      return template;
    }

    if (!(subPath.closed || _isImplicitlyClosed(elements))) {
      final contour = _templateFromRuns(
        (halfWidth) =>
            _openContour(elements, halfWidth, startCap: cap, endCap: cap),
      );
      return StrokeTemplate([
        _orientSolid(contour),
        for (final sign in const [1, -1])
          ..._wedgesFromRuns(
            (halfWidth, wedges) =>
                _openSide(elements, sign, halfWidth, wedges: wedges),
          ),
      ]);
    }

    final first = _templateFromRuns(
      (halfWidth) => _closedSide(elements, 1, halfWidth),
    );
    final second = _templateFromRuns(
      (halfWidth) => _closedSide(elements, -1, halfWidth),
    );

    // Which side is which is read off a narrow stroke rather than the unit-wide
    // one the sides were built at. A shape no wider than the stroke has both
    // sides meeting in its middle, where neither encloses anything and there is
    // nothing to tell them apart by; drawn thinly, every shape still has an
    // inside.
    final firstArea = _templateArea(first, at: _orientingHalfWidth);
    final secondArea = _templateArea(second, at: _orientingHalfWidth);
    final outerIsFirst = firstArea.abs() >= secondArea.abs();
    final outer = outerIsFirst ? first : second;
    final inner = outerIsFirst ? second : first;

    // Only the outer side's corners are handed out. The inner side's would fill
    // in the hole they sit in rather than the ink.
    final corners = _wedgesFromRuns(
      (halfWidth, wedges) => _closedSide(
        elements,
        outerIsFirst ? 1 : -1,
        halfWidth,
        wedges: wedges,
      ),
    );

    if (filled || _hasSwallowedItsInside(elements, inner)) {
      // Either the shape is painted, so it has no hole to begin with, or the
      // stroke is thick enough to have covered the whole inside of it. Both
      // mean one solid boundary: it already covers the interior and the stroke
      // together.
      return StrokeTemplate([_orientSolid(outer), ...corners]);
    }

    // The side enclosing less area is the hole the fill axis closes. It is
    // reversed so that it winds against the outer boundary and so punches
    // through it rather than adding to it.
    return StrokeTemplate([
      _orientSolid(outer),
      ...corners,
      _orientHole(
        StrokeContourTemplate(
          points: inner.reversed.points,
          behaviour: ContourFillBehaviour.collapse,
          collapseTarget: _centroidOf(elements),
        ),
      ),
    ]);
  }

  /// Whether the stroke is thick enough to have covered the whole inside of
  /// the shape, leaving no room for a hole.
  ///
  /// Offsetting a boundary inwards only makes sense while the shape is wider
  /// than the offset. Past that the inner boundary turns itself inside out and
  /// starts tracing a shape again — a circle of radius `r` offset inwards by
  /// `h > r` comes back as a circle of radius `h - r`, whose area is perfectly
  /// respectable and gives no hint that anything is wrong. Punching that
  /// through the outer boundary leaves a hole in the middle of what should be
  /// solid ink.
  ///
  /// What actually decides it is how much room the shape has: a hole can only
  /// exist where some point inside the centre line is further than the half
  /// width from it. So the inner boundary's own points are measured against the
  /// centre line, along with the centroid, and if none of them has that much
  /// room the hole is dropped. Points at a corner sit right on the centre line
  /// by construction, which is why this asks for the largest clearance rather
  /// than the smallest.
  ///
  /// The judgement is made once, at a half width of one, and holds at every
  /// weight. That is deliberate: the alternative is a shape whose number of
  /// contours depends on how heavily it is drawn, which is exactly what
  /// variation deltas cannot express.
  bool _hasSwallowedItsInside(
    List<_Element> elements,
    StrokeContourTemplate inner,
  ) {
    const halfWidth = 1.0;
    final centreLine = [for (final element in elements) element.start];
    if (centreLine.length < 3) {
      return false;
    }

    // A shape several stroke widths across cannot have been swallowed, and
    // measuring every point against every edge is the expensive part.
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final point in centreLine) {
      minX = math.min(minX, point.x);
      minY = math.min(minY, point.y);
      maxX = math.max(maxX, point.x);
      maxY = math.max(maxY, point.y);
    }
    if (math.min(maxX - minX, maxY - minY) > 4 * halfWidth) {
      return false;
    }

    var clearance = 0.0;
    void consider(Vec2 point) {
      if (!isPointInPolygon(point, centreLine)) {
        return;
      }
      clearance = math.max(clearance, distanceToPolygon(point, centreLine));
    }

    consider(_centroidOf(elements));
    for (final point in inner.points) {
      consider(point.at(halfWidth));
    }
    // A little under the half width, so that rounding cannot turn a hole that
    // only just exists into one that only just does not.
    return clearance < halfWidth * 0.9;
  }

  /// The outline of a sub path that collapsed to a single point.
  StrokeTemplate _dot(Vec2 centre) {
    switch (cap) {
      case StrokeCap.butt:
        return StrokeTemplate.empty;
      case StrokeCap.square:
        return StrokeTemplate([
          _orientSolid(
            _templateFromRuns(
              (halfWidth) => [
                for (final corner in const [
                  Vec2(-1, -1),
                  Vec2(1, -1),
                  Vec2(1, 1),
                  Vec2(-1, 1),
                ])
                  (position: centre + corner * halfWidth, onCurve: true),
              ],
            ),
          ),
        ]);
      case StrokeCap.round:
        return StrokeTemplate([
          _orientSolid(
            _templateFromRuns((halfWidth) {
              final points = <_SidePoint>[];
              _appendArc(
                points,
                centre: centre,
                fromDirection: const Vec2(1, 0),
                sweep: 2 * math.pi,
                radius: halfWidth,
              );
              return points;
            }),
          ),
        ]);
    }
  }

  /// Runs [build] at a half width of zero and one and recovers the affine
  /// description of every point.
  StrokeContourTemplate _templateFromRuns(
    List<_SidePoint> Function(double halfWidth) build,
  ) => _templateFromPair(build(0), build(1));

  /// Recovers the affine description of a contour from the same points built at
  /// a half width of zero and of one.
  static StrokeContourTemplate _templateFromPair(
    List<_SidePoint> atZero,
    List<_SidePoint> atOne,
  ) {
    assert(
      atZero.length == atOne.length,
      'The stroker emitted ${atZero.length} points at a half width of zero but '
      '${atOne.length} at a half width of one. Every branch it takes must '
      'depend on the centre line alone.',
    );
    return StrokeContourTemplate(
      points: [
        for (var index = 0; index < atZero.length; index++)
          StrokePointTemplate(
            base: atZero[index].position,
            direction: atOne[index].position - atZero[index].position,
            onCurve: atZero[index].onCurve,
          ),
      ],
    );
  }

  /// The corners of the joins [build] turns into, each as its own contour.
  ///
  /// See [_appendJoin] for what they are for.
  List<StrokeContourTemplate> _wedgesFromRuns(
    void Function(double halfWidth, List<_Wedge> wedges) build,
  ) {
    final atZero = <_Wedge>[];
    final atOne = <_Wedge>[];
    build(0, atZero);
    build(1, atOne);
    return [
      for (var index = 0; index < atZero.length; index++)
        _orientSolid(_templateFromPair(atZero[index], atOne[index])),
    ];
  }

  // ---------------------------------------------------------------------------
  // Centre line preparation
  // ---------------------------------------------------------------------------

  /// Flattens [subPath] into lines and gently bending quadratics.
  List<_Element> _toElements(SubPath subPath) {
    final elements = <_Element>[];
    var current = subPath.start;

    void addLine(Vec2 start, Vec2 end) {
      if (start.isCloseTo(end, 1e-12)) {
        return;
      }
      final tangent = (end - start).normalized;
      elements.add((
        start: start,
        control: null,
        end: end,
        startTangent: tangent,
        endTangent: tangent,
      ));
    }

    void addQuadratic(Quadratic quadratic) {
      if (isQuadraticDegenerate(quadratic)) {
        addLine(quadratic.start, quadratic.end);
        return;
      }
      for (final piece in limitQuadraticTurn(quadratic, maxTurnAngle)) {
        if (isQuadraticDegenerate(piece)) {
          addLine(piece.start, piece.end);
          continue;
        }
        elements.add((
          start: piece.start,
          control: piece.control,
          end: piece.end,
          startTangent: (piece.control - piece.start).normalized,
          endTangent: (piece.end - piece.control).normalized,
        ));
      }
    }

    for (final segment in subPath.segments) {
      switch (segment) {
        case LineSegment():
          addLine(current, segment.end);
        case QuadraticSegment():
          addQuadratic((
            start: current,
            control: segment.control,
            end: segment.end,
          ));
        case CubicSegment():
          cubicToQuadratics((
            start: current,
            control1: segment.control1,
            control2: segment.control2,
            end: segment.end,
          ), tolerance: cubicTolerance).forEach(addQuadratic);
      }
      current = segment.end;
    }

    if (subPath.closed && elements.isNotEmpty) {
      addLine(current, subPath.start);
    }
    return elements;
  }

  /// How many straight pieces a curved element is sampled into when looking
  /// for crossings. The cut only has to land near the crossing — the round caps
  /// on either side of it cover any small error — so a coarse sampling is
  /// enough.
  static const _crossingSamples = 4;

  /// How close to an element's end a crossing has to be before it counts as
  /// landing on the join rather than inside the element.
  static const _jointTolerance = 1e-3;

  /// How close two sampled points have to be to count as the same point.
  static const _touchTolerance = 1e-6;

  /// Cuts [elements] apart wherever the centre line crosses itself.
  ///
  /// Returns `null` when there are no crossings, which is the common case and
  /// lets the caller keep the cheaper closed-contour treatment.
  List<_Run>? _splitAtSelfIntersections(
    List<_Element> elements, {
    required bool closed,
  }) {
    final samples = [for (final element in elements) _sample(element)];
    final splits = [
      for (var index = 0; index < elements.length; index++) <double>[],
    ];
    var found = false;

    for (var i = 0; i < elements.length; i++) {
      for (var j = i + 1; j < elements.length; j++) {
        if (!_boundsOverlap(samples[i], samples[j])) {
          continue;
        }
        final sharesEnd = j == i + 1;
        final sharesStart = closed && i == 0 && j == elements.length - 1;
        final left = samples[i];
        final right = samples[j];
        void record(double atI, double atJ) {
          // The join two neighbouring elements already share is not a crossing.
          if (sharesEnd && atI > 1 - _jointTolerance && atJ < _jointTolerance) {
            return;
          }
          if (sharesStart &&
              atI < _jointTolerance &&
              atJ > 1 - _jointTolerance) {
            return;
          }
          splits[i].add(atI);
          splits[j].add(atJ);
          found = true;
        }

        for (var a = 0; a + 1 < left.length; a++) {
          for (var b = 0; b + 1 < right.length; b++) {
            final crossing = _segmentCrossing(
              left[a],
              left[a + 1],
              right[b],
              right[b + 1],
            );
            if (crossing != null) {
              record(
                (a + crossing.$1) / (left.length - 1),
                (b + crossing.$2) / (right.length - 1),
              );
            }
          }
        }
        // A symmetric icon can cross itself exactly on a point both halves
        // share, where neither segment's interior contains the crossing.
        // Comparing the sampled points directly catches that case.
        for (var a = 0; a < left.length; a++) {
          for (var b = 0; b < right.length; b++) {
            if (left[a].isCloseTo(right[b], _touchTolerance)) {
              record(a / (left.length - 1), b / (right.length - 1));
            }
          }
        }
      }
    }
    if (!found) {
      return null;
    }

    // A crossing that lands on the join between two elements needs no split at
    // all: the cut simply goes where they already meet.
    final cutBefore = <int>{};
    final interior = [
      for (var index = 0; index < elements.length; index++) <double>[],
    ];
    for (var index = 0; index < elements.length; index++) {
      for (final parameter in splits[index]) {
        if (parameter <= _jointTolerance) {
          cutBefore.add(index);
        } else if (parameter >= 1 - _jointTolerance) {
          cutBefore.add(index + 1);
        } else {
          interior[index].add(parameter);
        }
      }
    }

    final pieces = <_Element>[];
    final cutAfter = <bool>[];
    for (var index = 0; index < elements.length; index++) {
      if (cutBefore.contains(index) && cutAfter.isNotEmpty) {
        cutAfter[cutAfter.length - 1] = true;
      }
      final parts = _splitElement(elements[index], _tidy(interior[index]));
      for (var part = 0; part < parts.length; part++) {
        pieces.add(parts[part]);
        cutAfter.add(part < parts.length - 1);
      }
    }
    if (cutBefore.contains(0) || cutBefore.contains(elements.length)) {
      cutAfter[cutAfter.length - 1] = true;
    }
    if (!cutAfter.contains(true)) {
      // Every crossing sat on a join the path already had, so on an open path
      // there is nothing to cut.
      return null;
    }

    var ordered = pieces;
    var orderedCuts = cutAfter;
    if (closed) {
      // Rotate so the list starts just after a cut; every run then begins and
      // ends at one, and the loop is fully broken.
      final first = orderedCuts.indexOf(true);
      final offset = (first + 1) % ordered.length;
      ordered = [...ordered.sublist(offset), ...ordered.sublist(0, offset)];
      orderedCuts = [
        ...orderedCuts.sublist(offset),
        ...orderedCuts.sublist(0, offset),
      ];
      orderedCuts[orderedCuts.length - 1] = true;
    }

    final runs = <_Run>[];
    var current = <_Element>[];
    var startsAtCut = closed;
    for (var index = 0; index < ordered.length; index++) {
      current.add(ordered[index]);
      final isLast = index == ordered.length - 1;
      if (orderedCuts[index] || isLast) {
        runs.add((
          elements: current,
          startsAtCut: startsAtCut,
          endsAtCut: orderedCuts[index],
        ));
        current = [];
        startsAtCut = true;
      }
    }
    return runs;
  }

  /// Samples an element into the points of a polyline approximating it.
  static List<Vec2> _sample(_Element element) {
    final control = element.control;
    if (control == null) {
      return [element.start, element.end];
    }
    return [
      element.start,
      for (var step = 1; step < _crossingSamples; step++)
        evaluateQuadratic((
          start: element.start,
          control: control,
          end: element.end,
        ), step / _crossingSamples),
      element.end,
    ];
  }

  static bool _boundsOverlap(List<Vec2> left, List<Vec2> right) {
    var leftMinX = double.infinity;
    var leftMinY = double.infinity;
    var leftMaxX = double.negativeInfinity;
    var leftMaxY = double.negativeInfinity;
    for (final point in left) {
      leftMinX = math.min(leftMinX, point.x);
      leftMinY = math.min(leftMinY, point.y);
      leftMaxX = math.max(leftMaxX, point.x);
      leftMaxY = math.max(leftMaxY, point.y);
    }
    var rightMinX = double.infinity;
    var rightMinY = double.infinity;
    var rightMaxX = double.negativeInfinity;
    var rightMaxY = double.negativeInfinity;
    for (final point in right) {
      rightMinX = math.min(rightMinX, point.x);
      rightMinY = math.min(rightMinY, point.y);
      rightMaxX = math.max(rightMaxX, point.x);
      rightMaxY = math.max(rightMaxY, point.y);
    }
    return leftMinX <= rightMaxX &&
        rightMinX <= leftMaxX &&
        leftMinY <= rightMaxY &&
        rightMinY <= leftMaxY;
  }

  /// Where two line segments cross, as a parameter along each, or `null` when
  /// they do not cross in their interiors.
  static (double, double)? _segmentCrossing(
    Vec2 a0,
    Vec2 a1,
    Vec2 b0,
    Vec2 b1,
  ) {
    final left = a1 - a0;
    final right = b1 - b0;
    final denominator = left.cross(right);
    if (denominator.abs() < 1e-12) {
      return null;
    }
    final offset = b0 - a0;
    final alongLeft = offset.cross(right) / denominator;
    final alongRight = offset.cross(left) / denominator;
    if (alongLeft <= 0 ||
        alongLeft >= 1 ||
        alongRight <= 0 ||
        alongRight >= 1) {
      return null;
    }
    return (alongLeft, alongRight);
  }

  /// Sorts split parameters and drops duplicates and ones at the very ends.
  static List<double> _tidy(List<double> parameters) {
    final sorted = parameters.toList()..sort();
    final result = <double>[];
    for (final parameter in sorted) {
      if (parameter <= 1e-4 || parameter >= 1 - 1e-4) {
        continue;
      }
      if (result.isEmpty || parameter - result.last > 1e-4) {
        result.add(parameter);
      }
    }
    return result;
  }

  /// Cuts [element] at each of [parameters], which must be sorted and strictly
  /// inside the unit interval.
  static List<_Element> _splitElement(
    _Element element,
    List<double> parameters,
  ) {
    if (parameters.isEmpty) {
      return [element];
    }
    final parts = <_Element>[];
    var remaining = element;
    var consumed = 0.0;
    for (final parameter in parameters) {
      final local = (parameter - consumed) / (1 - consumed);
      final (head, tail) = _cutElement(remaining, local);
      parts.add(head);
      remaining = tail;
      consumed = parameter;
    }
    parts.add(remaining);
    return parts;
  }

  static (_Element, _Element) _cutElement(_Element element, double t) {
    final control = element.control;
    if (control == null) {
      final middle = element.start.lerp(element.end, t);
      return (
        (
          start: element.start,
          control: null,
          end: middle,
          startTangent: element.startTangent,
          endTangent: element.endTangent,
        ),
        (
          start: middle,
          control: null,
          end: element.end,
          startTangent: element.startTangent,
          endTangent: element.endTangent,
        ),
      );
    }
    final (head, tail) = splitQuadratic((
      start: element.start,
      control: control,
      end: element.end,
    ), t);
    return (_elementOf(head), _elementOf(tail));
  }

  static _Element _elementOf(Quadratic quadratic) {
    final incoming = quadratic.control - quadratic.start;
    final outgoing = quadratic.end - quadratic.control;
    if (incoming.lengthSquared < 1e-24 || outgoing.lengthSquared < 1e-24) {
      final tangent = (quadratic.end - quadratic.start).normalized;
      return (
        start: quadratic.start,
        control: null,
        end: quadratic.end,
        startTangent: tangent,
        endTangent: tangent,
      );
    }
    return (
      start: quadratic.start,
      control: quadratic.control,
      end: quadratic.end,
      startTangent: incoming.normalized,
      endTangent: outgoing.normalized,
    );
  }

  bool _isImplicitlyClosed(List<_Element> elements) =>
      elements.length > 1 && elements.last.end.isCloseTo(elements.first.start);

  // ---------------------------------------------------------------------------
  // Contour construction
  // ---------------------------------------------------------------------------

  /// Builds the single contour of an open sub path: out along one side, around
  /// the far end, back along the other side and around the near end.
  List<_SidePoint> _openContour(
    List<_Element> elements,
    double halfWidth, {
    required StrokeCap startCap,
    required StrokeCap endCap,
  }) => [
    ..._openSide(elements, 1, halfWidth),
    ..._cap(
      style: endCap,
      vertex: elements.last.end,
      tangent: elements.last.endTangent,
      halfWidth: halfWidth,
    ),
    ..._openSide(elements, -1, halfWidth).reversed,
    ..._cap(
      style: startCap,
      vertex: elements.first.start,
      tangent: -elements.first.startTangent,
      halfWidth: halfWidth,
    ),
  ];

  /// Walks one side of an open sub path from its start to its end.
  List<_SidePoint> _openSide(
    List<_Element> elements,
    int sign,
    double halfWidth, {
    List<_Wedge>? wedges,
  }) {
    final points = <_SidePoint>[
      (
        position: _offsetPoint(
          elements.first.start,
          elements.first.startTangent,
          sign,
          halfWidth,
        ),
        onCurve: true,
      ),
    ];
    for (var index = 0; index < elements.length; index++) {
      _appendElement(points, elements[index], sign, halfWidth);
      if (index + 1 < elements.length) {
        _appendJoin(
          points,
          elements[index],
          elements[index + 1],
          sign,
          halfWidth,
          wedges: wedges,
        );
      }
    }
    return points;
  }

  /// Walks one side of a closed sub path all the way around.
  List<_SidePoint> _closedSide(
    List<_Element> elements,
    int sign,
    double halfWidth, {
    List<_Wedge>? wedges,
  }) {
    final points = <_SidePoint>[
      (
        position: _offsetPoint(
          elements.first.start,
          elements.first.startTangent,
          sign,
          halfWidth,
        ),
        onCurve: true,
      ),
    ];
    for (var index = 0; index < elements.length; index++) {
      _appendElement(points, elements[index], sign, halfWidth);
      final next = elements[(index + 1) % elements.length];
      if (index + 1 < elements.length) {
        _appendJoin(
          points,
          elements[index],
          next,
          sign,
          halfWidth,
          wedges: wedges,
        );
      } else {
        // The join that wraps back onto the contour's first point. The first
        // point is already there, so only the corner geometry is emitted.
        _appendJoin(
          points,
          elements[index],
          next,
          sign,
          halfWidth,
          emitNextStart: false,
          wedges: wedges,
        );
      }
    }
    return points;
  }

  /// Appends the offset image of [element]: its control point when it bends,
  /// then its end point.
  void _appendElement(
    List<_SidePoint> points,
    _Element element,
    int sign,
    double halfWidth,
  ) {
    if (element.control != null) {
      points.add((
        position: _offsetControl(element, sign, halfWidth),
        onCurve: false,
      ));
    }
    points.add((
      position: _offsetPoint(element.end, element.endTangent, sign, halfWidth),
      onCurve: true,
    ));
  }

  /// Appends the corner geometry between [current] and [next], followed by the
  /// offset start point of [next] unless [emitNextStart] says otherwise.
  void _appendJoin(
    List<_SidePoint> points,
    _Element current,
    _Element next,
    int sign,
    double halfWidth, {
    bool emitNextStart = true,
    List<_Wedge>? wedges,
  }) {
    final incoming = current.endTangent;
    final outgoing = next.startTangent;
    final turn = _signedAngle(incoming, outgoing);
    if (turn.abs() <= cornerTolerance) {
      // Smooth: the offset end point of one element already is the offset start
      // point of the next, so nothing is added and nothing is repeated.
      return;
    }

    final vertex = current.end;
    final startNormal = incoming.perpendicular * sign.toDouble();
    final convex = sign * turn < 0;

    if (convex) {
      switch (join) {
        case StrokeJoin.round:
          _appendArc(
            points,
            centre: vertex,
            fromDirection: startNormal,
            sweep: turn,
            radius: halfWidth,
          );
        case StrokeJoin.miter:
          final miter = _miterDirection(incoming, outgoing, sign);
          if (miter != null && miter.length <= miterLimit) {
            points.add((position: vertex + miter * halfWidth, onCurve: true));
          }
        case StrokeJoin.bevel:
          break;
      }
    } else {
      // The inside of the turn: the offset lines cross, and the crossing point
      // is the exact corner.
      final miter = _miterDirection(incoming, outgoing, sign);
      final apex = miter != null && miter.length <= innerJoinLimit
          ? vertex + miter * halfWidth
          : null;
      if (apex != null) {
        points.add((position: apex, onCurve: true));
      }
      // The corner is handed out again on its own, as a little loop from the
      // vertex out along one offset, round the crossing point and back along
      // the other.
      //
      // Where the artwork doubles back into a notch narrower than the stroke,
      // the offset leaving this corner curves round and crosses the offset
      // arriving at it. The lobe that crossing encloses winds against the
      // contour it belongs to, and under the non-zero rule that is a slit of
      // bare paper through solid ink — the one at the jaw of a skull drawn
      // heavy. A separate contour cannot be cancelled by anything, so the lobe
      // is inked whichever way the outline runs through it, and this one can
      // only ever add ink to ink: every point of it lies between the centre
      // line and the offset, with nowhere to spill.
      wedges?.add([
        (position: vertex, onCurve: true),
        (
          position: _offsetPoint(current.end, incoming, sign, halfWidth),
          onCurve: true,
        ),
        if (apex != null) (position: apex, onCurve: true),
        (
          position: _offsetPoint(next.start, outgoing, sign, halfWidth),
          onCurve: true,
        ),
      ]);
    }

    if (emitNextStart) {
      points.add((
        position: _offsetPoint(next.start, outgoing, sign, halfWidth),
        onCurve: true,
      ));
    }
  }

  /// Appends the geometry closing off one end of an open sub path.
  List<_SidePoint> _cap({
    required StrokeCap style,
    required Vec2 vertex,
    required Vec2 tangent,
    required double halfWidth,
  }) {
    switch (style) {
      case StrokeCap.butt:
        return const [];
      case StrokeCap.square:
        final normal = tangent.perpendicular;
        return [
          (position: vertex + (normal + tangent) * halfWidth, onCurve: true),
          (position: vertex + (tangent - normal) * halfWidth, onCurve: true),
        ];
      case StrokeCap.round:
        final points = <_SidePoint>[];
        _appendArc(
          points,
          centre: vertex,
          fromDirection: tangent.perpendicular,
          sweep: -math.pi,
          radius: halfWidth,
        );
        return points;
    }
  }

  /// Appends the off-curve points of a circular arc of [radius] around
  /// [centre], starting in the direction [fromDirection] and turning by
  /// [sweep] radians.
  ///
  /// Only control points are emitted. Consecutive quadratic control points of a
  /// uniformly divided circular arc have their shared on-curve point exactly at
  /// their midpoint, which TrueType infers for free, so the arc costs one point
  /// per piece instead of two.
  void _appendArc(
    List<_SidePoint> points, {
    required Vec2 centre,
    required Vec2 fromDirection,
    required double sweep,
    required double radius,
  }) {
    final pieces = math.max(1, (sweep.abs() / maxArcAngle).ceil());
    final pieceAngle = sweep / pieces;
    final controlRadius = radius / math.cos(pieceAngle / 2);
    final startAngle = fromDirection.angle;
    for (var piece = 0; piece < pieces; piece++) {
      final angle = startAngle + (piece + 0.5) * pieceAngle;
      points.add((
        position:
            centre + Vec2(math.cos(angle), math.sin(angle)) * controlRadius,
        onCurve: false,
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // Offset primitives
  // ---------------------------------------------------------------------------

  Vec2 _offsetPoint(Vec2 point, Vec2 tangent, int sign, double halfWidth) =>
      point + tangent.perpendicular * (sign * halfWidth);

  /// The offset image of a quadratic's control point: the crossing of the two
  /// offset tangent lines, which keeps the offset curve tangent to the offset
  /// of the original at both ends.
  Vec2 _offsetControl(_Element element, int sign, double halfWidth) {
    final startPoint = _offsetPoint(
      element.start,
      element.startTangent,
      sign,
      halfWidth,
    );
    final endPoint = _offsetPoint(
      element.end,
      element.endTangent,
      sign,
      halfWidth,
    );
    final denominator = element.startTangent.cross(element.endTangent);
    if (denominator.abs() < 1e-12) {
      return startPoint.lerp(endPoint, 0.5);
    }
    final t = (endPoint - startPoint).cross(element.endTangent) / denominator;
    return startPoint + element.startTangent * t;
  }

  /// The direction from a corner to its miter point, scaled so that its length
  /// is the ratio of miter length to stroke width.
  ///
  /// Returns `null` when the two tangents are opposed and the miter point runs
  /// off to infinity.
  Vec2? _miterDirection(Vec2 incoming, Vec2 outgoing, int sign) {
    final startNormal = incoming.perpendicular;
    final endNormal = outgoing.perpendicular;
    final denominator = 1 + startNormal.dot(endNormal);
    if (denominator.abs() < 1e-9) {
      return null;
    }
    return (startNormal + endNormal) * (sign / denominator);
  }

  /// The signed angle from [from] to [to], in the range `(-pi, pi]`.
  static double _signedAngle(Vec2 from, Vec2 to) =>
      math.atan2(from.cross(to), from.dot(to));

  // ---------------------------------------------------------------------------
  // Orientation
  // ---------------------------------------------------------------------------

  /// Twice the signed area a contour template encloses at a representative half
  /// width.
  static double _templateArea(StrokeContourTemplate contour, {double at = 1}) {
    final points = contour.points;
    var total = 0.0;
    for (var index = 0; index < points.length; index++) {
      final current = points[index].at(at);
      final next = points[(index + 1) % points.length].at(at);
      total += current.cross(next);
    }
    return total / 2;
  }

  /// Forces [contour] to wind clockwise in the SVG's Y-down space, which turns
  /// into the counter-clockwise winding TrueType wants for solid contours once
  /// the Y axis is flipped.
  static StrokeContourTemplate _orientSolid(StrokeContourTemplate contour) =>
      _templateArea(contour) > 0 ? contour.reversed : contour;

  /// The opposite of [_orientSolid], for contours that punch a hole.
  ///
  /// Measured at a narrow stroke, like the choice of which side is which and
  /// for the same reason: a hole that the stroke has already closed encloses
  /// nothing at a half width of one and so has no direction to read there,
  /// while every hole is a hole when the stroke is thin enough.
  static StrokeContourTemplate _orientHole(StrokeContourTemplate contour) =>
      _templateArea(contour, at: _orientingHalfWidth) < 0
      ? contour.reversed
      : contour;

  /// The area centroid of the polygon traced by the centre lines, used as the
  /// point an inner contour collapses onto when the fill axis closes it.
  ///
  /// Falls back to the average of the vertices for degenerate, zero-area
  /// outlines.
  static Vec2 _centroidOf(List<_Element> elements) {
    final vertices = [for (final element in elements) element.start];
    var area = 0.0;
    var x = 0.0;
    var y = 0.0;
    for (var index = 0; index < vertices.length; index++) {
      final current = vertices[index];
      final next = vertices[(index + 1) % vertices.length];
      final cross = current.cross(next);
      area += cross;
      x += (current.x + next.x) * cross;
      y += (current.y + next.y) * cross;
    }
    if (area.abs() < 1e-12) {
      if (vertices.isEmpty) {
        return Vec2.zero;
      }
      var sum = Vec2.zero;
      for (final vertex in vertices) {
        sum += vertex;
      }
      return sum / vertices.length.toDouble();
    }
    return Vec2(x / (3 * area), y / (3 * area));
  }
}
