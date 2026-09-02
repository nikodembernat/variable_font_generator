import 'package:variable_font_generator/src/geometry/arc.dart';
import 'package:variable_font_generator/src/geometry/path.dart';
import 'package:variable_font_generator/src/geometry/vec2.dart';

/// Thrown when SVG path data cannot be parsed.
final class PathParseException implements FormatException {
  /// Creates an exception describing a failure at [offset] in [source].
  const PathParseException(this.message, this.source, this.offset);

  @override
  final String message;

  @override
  final String source;

  @override
  final int offset;

  @override
  String toString() =>
      'PathParseException: $message at offset $offset in "$source"';
}

/// Parses the `d` attribute of an SVG `<path>` element.
///
/// The full SVG 1.1 path grammar is supported, including relative commands,
/// implicit repeated commands, the smooth curve shorthands `S`/`T` and
/// elliptical arcs. Arcs are converted to cubic Bézier segments on the fly, so
/// the returned [Path] only ever contains lines and Bézier segments.
Path parseSvgPath(String d) => _PathDataParser(d).parse();

/// Scans SVG path data into numbers, flags and command letters.
final class _PathDataParser {
  _PathDataParser(this.source);

  final String source;
  int _offset = 0;

  /// The current point.
  Vec2 _current = Vec2.zero;

  /// The start point of the sub path being built.
  Vec2 _subPathStart = Vec2.zero;

  /// The control point to reflect for a following `S`/`T` command, in absolute
  /// coordinates, or `null` when the previous command was not a curve of the
  /// matching kind.
  Vec2? _lastCubicControl;
  Vec2? _lastQuadraticControl;

  final List<SubPath> _subPaths = [];
  List<PathSegment> _segments = [];
  bool _hasOpenSubPath = false;

  Path parse() {
    _skipWhitespaceAndCommas();
    if (_offset >= source.length) {
      return Path.empty;
    }
    if (!_isCommand(source.codeUnitAt(_offset))) {
      throw PathParseException(
        'Path data must start with a command',
        source,
        0,
      );
    }

    var command = 0;
    while (true) {
      _skipWhitespaceAndCommas();
      if (_offset >= source.length) {
        break;
      }
      final codeUnit = source.codeUnitAt(_offset);
      if (_isCommand(codeUnit)) {
        command = codeUnit;
        _offset++;
      } else if (command == 0) {
        throw PathParseException('Expected a command', source, _offset);
      } else {
        // An implicitly repeated command. `M`/`m` repeats as `L`/`l`.
        command = switch (command) {
          _charM => _charL,
          _charm => _charl,
          _ => command,
        };
      }
      _runCommand(command);
    }

    _flushSubPath(closed: false);
    return Path(_subPaths);
  }

  void _runCommand(int command) {
    switch (command) {
      case _charM:
      case _charm:
        final target = _readPoint(relative: command == _charm);
        _flushSubPath(closed: false);
        _current = target;
        _subPathStart = target;
        _hasOpenSubPath = true;
        _clearReflections();
      case _charZ:
      case _charz:
        _flushSubPath(closed: true);
        _current = _subPathStart;
        _clearReflections();
      case _charL:
      case _charl:
        _lineTo(_readPoint(relative: command == _charl));
        _clearReflections();
      case _charH:
      case _charh:
        final x = _readNumber();
        _lineTo(Vec2(command == _charh ? _current.x + x : x, _current.y));
        _clearReflections();
      case _charV:
      case _charv:
        final y = _readNumber();
        _lineTo(Vec2(_current.x, command == _charv ? _current.y + y : y));
        _clearReflections();
      case _charC:
      case _charc:
        final relative = command == _charc;
        final control1 = _readPoint(relative: relative);
        final control2 = _readPoint(relative: relative);
        final end = _readPoint(relative: relative);
        _cubicTo(control1, control2, end);
      case _charS:
      case _chars:
        final relative = command == _chars;
        final control1 = _reflected(_lastCubicControl);
        final control2 = _readPoint(relative: relative);
        final end = _readPoint(relative: relative);
        _cubicTo(control1, control2, end);
      case _charQ:
      case _charq:
        final relative = command == _charq;
        final control = _readPoint(relative: relative);
        final end = _readPoint(relative: relative);
        _quadraticTo(control, end);
      case _charT:
      case _chart:
        final control = _reflected(_lastQuadraticControl);
        final end = _readPoint(relative: command == _chart);
        _quadraticTo(control, end);
      case _charA:
      case _chara:
        final relative = command == _chara;
        final radiusX = _readNumber();
        final radiusY = _readNumber();
        final rotationDegrees = _readNumber();
        final largeArc = _readFlag();
        final sweep = _readFlag();
        final end = _readPoint(relative: relative);
        _arcTo(radiusX, radiusY, rotationDegrees, largeArc, sweep, end);
      default:
        throw PathParseException(
          'Unsupported command "${String.fromCharCode(command)}"',
          source,
          _offset,
        );
    }
  }

  void _lineTo(Vec2 end) {
    _requireOpenSubPath();
    // Zero length segments are kept on purpose: SVG draws them as a dot when
    // the line cap is round or square, and the stroker relies on seeing them.
    _segments.add(LineSegment(end));
    _current = end;
  }

  void _cubicTo(Vec2 control1, Vec2 control2, Vec2 end) {
    _requireOpenSubPath();
    _segments.add(CubicSegment(control1, control2, end));
    _current = end;
    _lastCubicControl = control2;
    _lastQuadraticControl = null;
  }

  void _quadraticTo(Vec2 control, Vec2 end) {
    _requireOpenSubPath();
    _segments.add(QuadraticSegment(control, end));
    _current = end;
    _lastQuadraticControl = control;
    _lastCubicControl = null;
  }

  void _arcTo(
    double radiusX,
    double radiusY,
    double rotationDegrees,
    bool largeArc,
    bool sweep,
    Vec2 end,
  ) {
    _requireOpenSubPath();
    final segments = arcToCubics(
      start: _current,
      end: end,
      radiusX: radiusX,
      radiusY: radiusY,
      rotationDegrees: rotationDegrees,
      largeArc: largeArc,
      sweep: sweep,
    );
    _segments.addAll(segments);
    _current = end;
    _clearReflections();
  }

  void _requireOpenSubPath() {
    if (!_hasOpenSubPath) {
      // SVG allows drawing commands after `Z` without a new `M`; the new sub
      // path then starts at the previous sub path's start point.
      _hasOpenSubPath = true;
      _subPathStart = _current;
    }
  }

  void _flushSubPath({required bool closed}) {
    if (_hasOpenSubPath && _segments.isNotEmpty) {
      _subPaths.add(
        SubPath(start: _subPathStart, segments: _segments, closed: closed),
      );
    }
    _segments = [];
    _hasOpenSubPath = false;
  }

  void _clearReflections() {
    _lastCubicControl = null;
    _lastQuadraticControl = null;
  }

  /// Reflects [control] about the current point, per the `S`/`T` shorthand.
  Vec2 _reflected(Vec2? control) =>
      control == null ? _current : _current * 2 - control;

  Vec2 _readPoint({required bool relative}) {
    final x = _readNumber();
    final y = _readNumber();
    return relative ? Vec2(_current.x + x, _current.y + y) : Vec2(x, y);
  }

  /// Reads an arc flag, which is always a single `0` or `1` digit and may be
  /// written without any separator before the following number.
  bool _readFlag() {
    _skipWhitespaceAndCommas();
    if (_offset >= source.length) {
      throw PathParseException('Expected a flag', source, _offset);
    }
    final codeUnit = source.codeUnitAt(_offset);
    if (codeUnit != _char0 && codeUnit != _char1) {
      throw PathParseException('Expected "0" or "1"', source, _offset);
    }
    _offset++;
    return codeUnit == _char1;
  }

  double _readNumber() {
    _skipWhitespaceAndCommas();
    final start = _offset;
    if (_offset < source.length) {
      final sign = source.codeUnitAt(_offset);
      if (sign == _charPlus || sign == _charMinus) {
        _offset++;
      }
    }
    var sawDigit = false;
    while (_offset < source.length && _isDigit(source.codeUnitAt(_offset))) {
      _offset++;
      sawDigit = true;
    }
    if (_offset < source.length && source.codeUnitAt(_offset) == _charDot) {
      _offset++;
      while (_offset < source.length && _isDigit(source.codeUnitAt(_offset))) {
        _offset++;
        sawDigit = true;
      }
    }
    if (!sawDigit) {
      throw PathParseException('Expected a number', source, start);
    }
    if (_offset < source.length) {
      final exponent = source.codeUnitAt(_offset);
      if (exponent == _charE || exponent == _chare) {
        final beforeExponent = _offset;
        _offset++;
        if (_offset < source.length) {
          final sign = source.codeUnitAt(_offset);
          if (sign == _charPlus || sign == _charMinus) {
            _offset++;
          }
        }
        var sawExponentDigit = false;
        while (_offset < source.length &&
            _isDigit(source.codeUnitAt(_offset))) {
          _offset++;
          sawExponentDigit = true;
        }
        if (!sawExponentDigit) {
          // Not actually an exponent, e.g. the `e` of a following command.
          _offset = beforeExponent;
        }
      }
    }
    final text = source.substring(start, _offset);
    final value = double.tryParse(text);
    if (value == null) {
      throw PathParseException('Invalid number "$text"', source, start);
    }
    return value;
  }

  void _skipWhitespaceAndCommas() {
    while (_offset < source.length) {
      final codeUnit = source.codeUnitAt(_offset);
      if (codeUnit == 0x20 ||
          codeUnit == 0x09 ||
          codeUnit == 0x0A ||
          codeUnit == 0x0D ||
          codeUnit == 0x0C ||
          codeUnit == _charComma) {
        _offset++;
      } else {
        break;
      }
    }
  }

  static bool _isDigit(int codeUnit) =>
      codeUnit >= _char0 && codeUnit <= _char9;

  static bool _isCommand(int codeUnit) => switch (codeUnit) {
    _charM ||
    _charm ||
    _charZ ||
    _charz ||
    _charL ||
    _charl ||
    _charH ||
    _charh ||
    _charV ||
    _charv ||
    _charC ||
    _charc ||
    _charS ||
    _chars ||
    _charQ ||
    _charq ||
    _charT ||
    _chart ||
    _charA ||
    _chara => true,
    _ => false,
  };
}

const _charComma = 0x2C;
const _charMinus = 0x2D;
const _charDot = 0x2E;
const _charPlus = 0x2B;
const _char0 = 0x30;
const _char1 = 0x31;
const _char9 = 0x39;
const _charA = 0x41;
const _charC = 0x43;
const _charE = 0x45;
const _charH = 0x48;
const _charL = 0x4C;
const _charM = 0x4D;
const _charQ = 0x51;
const _charS = 0x53;
const _charT = 0x54;
const _charV = 0x56;
const _charZ = 0x5A;
const _chara = 0x61;
const _charc = 0x63;
const _chare = 0x65;
const _charh = 0x68;
const _charl = 0x6C;
const _charm = 0x6D;
const _charq = 0x71;
const _chars = 0x73;
const _chart = 0x74;
const _charv = 0x76;
const _charz = 0x7A;
