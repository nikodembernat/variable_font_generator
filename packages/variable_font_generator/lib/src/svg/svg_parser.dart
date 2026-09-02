import 'package:variable_font_generator/src/geometry/arc.dart';
import 'package:variable_font_generator/src/geometry/path.dart';
import 'package:variable_font_generator/src/geometry/path_parser.dart';
import 'package:variable_font_generator/src/geometry/stroke_style.dart';
import 'package:variable_font_generator/src/geometry/vec2.dart';
import 'package:variable_font_generator/src/svg/svg_icon.dart';
import 'package:variable_font_generator/src/svg/svg_transform.dart';
import 'package:xml/xml.dart';

/// Thrown when an SVG document cannot be turned into an [SvgIcon].
final class SvgParseException implements Exception {
  /// Creates an exception with [message] describing what went wrong in the
  /// document named [source].
  const SvgParseException(this.message, this.source);

  /// What went wrong.
  final String message;

  /// The name of the document the failure happened in.
  final String source;

  @override
  String toString() => 'SvgParseException in $source: $message';
}

/// The property values SVG starts from before a document says anything.
const _initialContext = (
  fill: 'black',
  stroke: 'none',
  strokeWidth: 1.0,
  cap: StrokeCap.butt,
  join: StrokeJoin.miter,
  miterLimit: 4.0,
  transform: AffineTransform.identity,
);

/// The painting properties inherited down the SVG element tree.
typedef _Context = ({
  String fill,
  String stroke,
  double strokeWidth,
  StrokeCap cap,
  StrokeJoin join,
  double miterLimit,
  AffineTransform transform,
});

/// Parses an SVG document into an [SvgIcon] named [name].
///
/// Only the static subset of SVG that icon sets actually use is understood:
/// `path`, `circle`, `ellipse`, `rect`, `line`, `polyline`, `polygon` and `g`,
/// with presentation attributes inherited down the tree and `transform`
/// applied. Anything else in the document is ignored, so gradients, filters and
/// text do not break a build; they simply do not contribute geometry.
SvgIcon parseSvgIcon(String document, {required String name}) {
  final XmlDocument xml;
  try {
    xml = XmlDocument.parse(document);
  } on XmlException catch (error) {
    throw SvgParseException('Malformed XML: ${error.message}', name);
  }

  final root = xml.rootElement;
  if (root.name.local != 'svg') {
    throw SvgParseException(
      'Expected an <svg> root element but found <${root.name.local}>',
      name,
    );
  }

  final viewBox = _parseViewBox(root, name);
  final shapes = <SvgShape>[];
  // The root's own attributes are read exactly the way a group's are,
  // `style` included, so that the same declaration means the same thing
  // wherever it sits.
  _collect(root, _inherit(_initialContext, root), shapes);

  return SvgIcon(
    name: name,
    viewBoxX: viewBox.x,
    viewBoxY: viewBox.y,
    viewBoxWidth: viewBox.width,
    viewBoxHeight: viewBox.height,
    shapes: shapes,
  );
}

({double x, double y, double width, double height}) _parseViewBox(
  XmlElement root,
  String name,
) {
  final attribute = root.getAttribute('viewBox');
  if (attribute != null) {
    final numbers = [
      for (final match in RegExp(
        r'[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?',
      ).allMatches(attribute))
        double.parse(match.group(0)!),
    ];
    if (numbers.length >= 4 && numbers[2] > 0 && numbers[3] > 0) {
      return (
        x: numbers[0],
        y: numbers[1],
        width: numbers[2],
        height: numbers[3],
      );
    }
  }
  final width = _parseLength(root.getAttribute('width'));
  final height = _parseLength(root.getAttribute('height'));
  if (width != null && height != null && width > 0 && height > 0) {
    return (x: 0, y: 0, width: width, height: height);
  }
  throw SvgParseException(
    'The <svg> element needs a viewBox or a width and height',
    name,
  );
}

void _collect(XmlElement element, _Context context, List<SvgShape> shapes) {
  for (final child in element.childElements) {
    final childContext = _inherit(context, child);
    final path = _pathOf(child);
    if (path != null) {
      final filled = _isPainted(childContext.fill);
      final stroked = _isPainted(childContext.stroke);
      if ((filled || stroked) && !path.isEmpty) {
        final transform = childContext.transform;
        shapes.add(
          SvgShape(
            path: transform.isIdentity
                ? path
                : path.transformed(transform.apply),
            filled: filled,
            stroked: stroked,
            strokeWidth: childContext.strokeWidth * transform.strokeScale,
            cap: childContext.cap,
            join: childContext.join,
            miterLimit: childContext.miterLimit,
          ),
        );
      }
    }
    _collect(child, childContext, shapes);
  }
}

_Context _inherit(_Context parent, XmlElement element) {
  final style = _parseStyle(element.getAttribute('style'));
  String? attribute(String name) => style[name] ?? element.getAttribute(name);

  final elementTransform = _transformOf(element);
  return (
    fill: attribute('fill') ?? parent.fill,
    stroke: attribute('stroke') ?? parent.stroke,
    strokeWidth: _parseLength(attribute('stroke-width')) ?? parent.strokeWidth,
    cap: switch (attribute('stroke-linecap')) {
      final value? => StrokeCap.parse(value),
      null => parent.cap,
    },
    join: switch (attribute('stroke-linejoin')) {
      final value? => StrokeJoin.parse(value),
      null => parent.join,
    },
    miterLimit:
        _parseLength(attribute('stroke-miterlimit')) ?? parent.miterLimit,
    transform: elementTransform.isIdentity
        ? parent.transform
        : parent.transform.multiply(elementTransform),
  );
}

AffineTransform _transformOf(XmlElement element) {
  final value = element.getAttribute('transform');
  return value == null ? AffineTransform.identity : parseSvgTransform(value);
}

Map<String, String> _parseStyle(String? style) {
  if (style == null || style.isEmpty) {
    return const {};
  }
  final result = <String, String>{};
  for (final declaration in style.split(';')) {
    final colon = declaration.indexOf(':');
    if (colon > 0) {
      result[declaration.substring(0, colon).trim()] = declaration
          .substring(colon + 1)
          .trim();
    }
  }
  return result;
}

/// Whether a `fill` or `stroke` value paints anything.
bool _isPainted(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized != 'none' && normalized != 'transparent';
}

/// Converts a shape element into a [Path], or returns `null` for elements that
/// carry no geometry.
Path? _pathOf(XmlElement element) => switch (element.name.local) {
  'path' => switch (element.getAttribute('d')) {
    final d? when d.trim().isNotEmpty => parseSvgPath(d),
    _ => Path.empty,
  },
  'circle' => _ellipsePath(
    centreX: _attribute(element, 'cx'),
    centreY: _attribute(element, 'cy'),
    radiusX: _attribute(element, 'r'),
    radiusY: _attribute(element, 'r'),
  ),
  'ellipse' => _ellipsePath(
    centreX: _attribute(element, 'cx'),
    centreY: _attribute(element, 'cy'),
    radiusX: _attribute(element, 'rx'),
    radiusY: _attribute(element, 'ry'),
  ),
  'rect' => _rectPath(element),
  'line' => _linePath(element),
  'polyline' => _polyPath(element, closed: false),
  'polygon' => _polyPath(element, closed: true),
  _ => null,
};

double _attribute(XmlElement element, String name) =>
    _parseLength(element.getAttribute(name)) ?? 0;

/// Builds an ellipse from four quarter arcs.
///
/// The magic constant is the one that makes a cubic Bézier match a quarter
/// circle to within 0.03% of its radius.
Path _ellipsePath({
  required double centreX,
  required double centreY,
  required double radiusX,
  required double radiusY,
}) {
  if (radiusX <= 0 || radiusY <= 0) {
    return Path.empty;
  }
  const kappa = 0.5522847498307933;
  final offsetX = radiusX * kappa;
  final offsetY = radiusY * kappa;
  final left = centreX - radiusX;
  final right = centreX + radiusX;
  final top = centreY - radiusY;
  final bottom = centreY + radiusY;
  return Path([
    SubPath(
      start: Vec2(right, centreY),
      closed: true,
      segments: [
        CubicSegment(
          Vec2(right, centreY + offsetY),
          Vec2(centreX + offsetX, bottom),
          Vec2(centreX, bottom),
        ),
        CubicSegment(
          Vec2(centreX - offsetX, bottom),
          Vec2(left, centreY + offsetY),
          Vec2(left, centreY),
        ),
        CubicSegment(
          Vec2(left, centreY - offsetY),
          Vec2(centreX - offsetX, top),
          Vec2(centreX, top),
        ),
        CubicSegment(
          Vec2(centreX + offsetX, top),
          Vec2(right, centreY - offsetY),
          Vec2(right, centreY),
        ),
      ],
    ),
  ]);
}

/// Builds a rectangle, honouring the SVG rules for rounded corners: a missing
/// `rx` takes the value of `ry` and the other way round, and both are clamped
/// to half the corresponding side.
Path _rectPath(XmlElement element) {
  final x = _attribute(element, 'x');
  final y = _attribute(element, 'y');
  final width = _attribute(element, 'width');
  final height = _attribute(element, 'height');
  if (width <= 0 || height <= 0) {
    return Path.empty;
  }

  final rawX = _parseLength(element.getAttribute('rx'));
  final rawY = _parseLength(element.getAttribute('ry'));
  var radiusX = rawX ?? rawY ?? 0;
  var radiusY = rawY ?? rawX ?? 0;
  radiusX = radiusX.clamp(0, width / 2);
  radiusY = radiusY.clamp(0, height / 2);

  if (radiusX == 0 || radiusY == 0) {
    return Path([
      SubPath(
        start: Vec2(x, y),
        closed: true,
        segments: [
          LineSegment(Vec2(x + width, y)),
          LineSegment(Vec2(x + width, y + height)),
          LineSegment(Vec2(x, y + height)),
        ],
      ),
    ]);
  }

  List<PathSegment> corner(Vec2 from, Vec2 to) => arcToCubics(
    start: from,
    end: to,
    radiusX: radiusX,
    radiusY: radiusY,
    rotationDegrees: 0,
    largeArc: false,
    sweep: true,
  );

  final start = Vec2(x + radiusX, y);
  final topRight = Vec2(x + width - radiusX, y);
  final rightTop = Vec2(x + width, y + radiusY);
  final rightBottom = Vec2(x + width, y + height - radiusY);
  final bottomRight = Vec2(x + width - radiusX, y + height);
  final bottomLeft = Vec2(x + radiusX, y + height);
  final leftBottom = Vec2(x, y + height - radiusY);
  final leftTop = Vec2(x, y + radiusY);

  return Path([
    SubPath(
      start: start,
      closed: true,
      segments: [
        LineSegment(topRight),
        ...corner(topRight, rightTop),
        LineSegment(rightBottom),
        ...corner(rightBottom, bottomRight),
        LineSegment(bottomLeft),
        ...corner(bottomLeft, leftBottom),
        LineSegment(leftTop),
        ...corner(leftTop, start),
      ],
    ),
  ]);
}

Path _linePath(XmlElement element) {
  final start = Vec2(_attribute(element, 'x1'), _attribute(element, 'y1'));
  final end = Vec2(_attribute(element, 'x2'), _attribute(element, 'y2'));
  // A zero length line is not nothing: with a round or square cap it draws a
  // dot, which several icon sets use for small details.
  return Path([
    SubPath(start: start, closed: false, segments: [LineSegment(end)]),
  ]);
}

Path _polyPath(XmlElement element, {required bool closed}) {
  final numbers = [
    for (final match in RegExp(
      r'[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?',
    ).allMatches(element.getAttribute('points') ?? ''))
      double.parse(match.group(0)!),
  ];
  if (numbers.length < 4) {
    return Path.empty;
  }
  final points = [
    for (var index = 0; index + 1 < numbers.length; index += 2)
      Vec2(numbers[index], numbers[index + 1]),
  ];
  return Path([
    SubPath(
      start: points.first,
      closed: closed,
      segments: [for (final point in points.skip(1)) LineSegment(point)],
    ),
  ]);
}

/// Parses an SVG length, ignoring any unit suffix.
///
/// Only absolute user-space units make sense inside an icon's view box, so a
/// `px` suffix is dropped and other units are treated as user units too.
double? _parseLength(String? value) {
  if (value == null) {
    return null;
  }
  final match = RegExp(r'^\s*([-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?)')
      .firstMatch(value);
  return match == null ? null : double.tryParse(match.group(1)!);
}
