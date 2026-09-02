import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:variable_font_generator/src/font/binary_writer.dart';
import 'package:variable_font_generator/src/variations/variation_model.dart';

/// How far one point moves in one master, in design units.
typedef PointDelta = ({int x, int y});

/// One master's contribution to one glyph: the region it applies over and how
/// far every point moves inside it.
///
/// The delta list covers the glyph's outline points followed by the four
/// phantom points, in that order.
typedef GlyphVariationTuple = ({
  MasterSupport support,
  List<PointDelta> deltas,
});

/// Flags of the `tupleVariationCount` field.
abstract final class TupleCountFlag {
  /// One list of point numbers is stored once and shared by every tuple that
  /// does not bring its own.
  static const sharedPointNumbers = 0x8000;

  /// The bits holding the actual number of tuples.
  static const countMask = 0x0FFF;
}

/// Flags of a tuple variation header's `tupleIndex` field.
abstract final class TupleIndexFlag {
  /// The peak tuple follows the header instead of being looked up in the
  /// shared tuple array.
  static const embeddedPeakTuple = 0x8000;

  /// The region's start and end follow the peak, because they are not the ones
  /// implied by the peak alone.
  static const intermediateRegion = 0x4000;

  /// This tuple brings its own list of point numbers.
  static const privatePointNumbers = 0x2000;

  /// The bits holding the index into the shared tuple array.
  static const indexMask = 0x0FFF;
}

/// The number of phantom points every glyph has: the two horizontal ones
/// carrying the side bearings and advance width, and the two vertical ones.
const phantomPointCount = 4;

/// Builds the `gvar` table.
///
/// [glyphTuples] holds one list of tuples per glyph, in glyph ID order; a glyph
/// with no variation gets an empty list. [axisOrder] fixes the order axis
/// coordinates are written in and must match the `fvar` table.
Uint8List buildGvarTable({
  required List<List<GlyphVariationTuple>> glyphTuples,
  required List<String> axisOrder,
}) {
  // Every glyph varies over the same handful of regions, so the peaks are
  // collected once into the shared tuple array and referenced by index. That
  // saves two bytes per axis per tuple per glyph, which over a full icon set is
  // most of a megabyte.
  final sharedPeaks = <List<double>>[];
  final sharedIndex = <String, int>{};
  for (final tuples in glyphTuples) {
    for (final tuple in tuples) {
      final peak = _peakOf(tuple.support, axisOrder);
      sharedIndex.putIfAbsent(_keyOf(peak), () {
        sharedPeaks.add(peak);
        return sharedPeaks.length - 1;
      });
    }
  }
  if (sharedPeaks.length > TupleIndexFlag.indexMask) {
    throw StateError(
      'A font may share at most ${TupleIndexFlag.indexMask} tuples but '
      '${sharedPeaks.length} distinct regions were used',
    );
  }

  final glyphData = [
    for (final tuples in glyphTuples)
      _buildGlyphVariationData(tuples, axisOrder, sharedIndex),
  ];

  // Glyph entries are laid out relative to the start of the data array, and
  // every one begins on a four byte boundary. That matters twice over: the
  // short offset form stores half of each offset, so an odd one could not be
  // expressed at all, and the array's own base has to be aligned too or the
  // relative offsets would not land where a reader computes them.
  final dataArray = BinaryWriter();
  final offsets = <int>[0];
  for (final data in glyphData) {
    dataArray
      ..bytes(data)
      ..align(4);
    offsets.add(dataArray.length);
  }
  final longOffsets = offsets.last > 0x1FFFE;

  final headerSize = 20 + (glyphData.length + 1) * (longOffsets ? 4 : 2);
  final sharedTuplesOffset = headerSize;
  final sharedTuplesSize = sharedPeaks.length * axisOrder.length * 2;
  final unaligned = sharedTuplesOffset + sharedTuplesSize;
  final dataArrayOffset = unaligned + (4 - unaligned % 4) % 4;

  final writer = BinaryWriter()
    ..uint16(1) // majorVersion
    ..uint16(0) // minorVersion
    ..uint16(axisOrder.length)
    ..uint16(sharedPeaks.length)
    ..uint32(sharedTuplesOffset)
    ..uint16(glyphData.length)
    ..uint16(longOffsets ? 1 : 0)
    ..uint32(dataArrayOffset);
  for (final offset in offsets) {
    if (longOffsets) {
      writer.uint32(offset);
    } else {
      writer.uint16(offset ~/ 2);
    }
  }
  for (final peak in sharedPeaks) {
    peak.forEach(writer.f2dot14);
  }
  writer
    ..zeros(dataArrayOffset - unaligned)
    ..bytes(dataArray.toBytes());
  return writer.toBytes();
}

/// Serialises the tuples of one glyph.
Uint8List _buildGlyphVariationData(
  List<GlyphVariationTuple> tuples,
  List<String> axisOrder,
  Map<String, int> sharedIndex,
) {
  if (tuples.isEmpty) {
    return Uint8List(0);
  }

  // A tuple only has to carry the points it actually moves. Working out that
  // set first is what keeps the fill axis cheap: it only ever moves the inner
  // contour of a shape, so its tuples list a fraction of the glyph's points.
  final pointSets = [for (final tuple in tuples) _movedPoints(tuple.deltas)];
  final live = [
    for (var index = 0; index < tuples.length; index++)
      if (pointSets[index].isNotEmpty) index,
  ];
  if (live.isEmpty) {
    return Uint8List(0);
  }

  // The point set most tuples agree on is stored once at the front; the others
  // bring their own.
  final counts = <String, int>{};
  for (final index in live) {
    counts.update(
      _pointsKey(pointSets[index]),
      (value) => value + 1,
      ifAbsent: () => 1,
    );
  }
  final sharedKey = counts.entries
      .sorted((a, b) => b.value.compareTo(a.value))
      .first;
  final useShared = sharedKey.value > 1;
  final sharedPoints = useShared
      ? pointSets[live.firstWhere(
          (index) => _pointsKey(pointSets[index]) == sharedKey.key,
        )]
      : const <int>[];

  final headers = BinaryWriter();
  final data = BinaryWriter();
  if (useShared) {
    data.bytes(_packPointNumbers(sharedPoints, tuples.first.deltas.length));
  }

  for (final index in live) {
    final tuple = tuples[index];
    final points = pointSets[index];
    final private = !useShared || _pointsKey(points) != sharedKey.key;

    final body = BinaryWriter();
    if (private) {
      body.bytes(_packPointNumbers(points, tuple.deltas.length));
    }
    body
      ..bytes(_packDeltas([for (final point in points) tuple.deltas[point].x]))
      ..bytes(_packDeltas([for (final point in points) tuple.deltas[point].y]));

    final peak = _peakOf(tuple.support, axisOrder);
    final intermediate = _intermediateOf(tuple.support, axisOrder, peak);
    var tupleIndex = sharedIndex[_keyOf(peak)]!;
    if (private) {
      tupleIndex |= TupleIndexFlag.privatePointNumbers;
    }
    if (intermediate != null) {
      tupleIndex |= TupleIndexFlag.intermediateRegion;
    }
    headers
      ..uint16(body.length)
      ..uint16(tupleIndex);
    if (intermediate != null) {
      intermediate.start.forEach(headers.f2dot14);
      intermediate.end.forEach(headers.f2dot14);
    }
    data.bytes(body.toBytes());
  }

  final headerBytes = headers.toBytes();
  final writer = BinaryWriter()
    ..uint16(live.length | (useShared ? TupleCountFlag.sharedPointNumbers : 0))
    ..uint16(4 + headerBytes.length) // dataOffset
    ..bytes(headerBytes)
    ..bytes(data.toBytes());
  return writer.toBytes();
}

/// The indices of the points a tuple actually moves.
List<int> _movedPoints(List<PointDelta> deltas) => [
  for (var index = 0; index < deltas.length; index++)
    if (deltas[index].x != 0 || deltas[index].y != 0) index,
];

String _pointsKey(List<int> points) => points.join(',');

List<double> _peakOf(MasterSupport support, List<String> axisOrder) => [
  for (final axis in axisOrder) support[axis]?.peak ?? 0,
];

/// The explicit region bounds, or `null` when they are the ones a reader
/// derives from the peak on its own.
({List<double> start, List<double> end})? _intermediateOf(
  MasterSupport support,
  List<String> axisOrder,
  List<double> peak,
) {
  final start = <double>[];
  final end = <double>[];
  var needed = false;
  for (var index = 0; index < axisOrder.length; index++) {
    final region = support[axisOrder[index]];
    final peakValue = peak[index];
    final impliedStart = peakValue < 0 ? peakValue : 0.0;
    final impliedEnd = peakValue > 0 ? peakValue : 0.0;
    final actualStart = region?.start ?? 0;
    final actualEnd = region?.end ?? 0;
    start.add(actualStart);
    end.add(actualEnd);
    if (actualStart != impliedStart || actualEnd != impliedEnd) {
      needed = true;
    }
  }
  return needed ? (start: start, end: end) : null;
}

String _keyOf(List<double> tuple) =>
    tuple.map((value) => (value * 16384).round()).join(',');

/// Packs a sorted list of point numbers into the run-length form `gvar` uses.
///
/// A count of zero is the special case meaning every point in the glyph, which
/// costs a single byte instead of a full list.
Uint8List _packPointNumbers(List<int> points, int totalPoints) {
  final writer = BinaryWriter();
  if (points.length == totalPoints) {
    writer.uint8(0);
    return writer.toBytes();
  }
  if (points.length < 0x80) {
    writer.uint8(points.length);
  } else {
    writer
      ..uint8(0x80 | (points.length >> 8))
      ..uint8(points.length & 0xFF);
  }

  // Numbers are stored as differences from the one before, which for a run of
  // consecutive points is a run of ones.
  final deltas = <int>[];
  var previous = 0;
  for (final point in points) {
    deltas.add(point - previous);
    previous = point;
  }

  var index = 0;
  while (index < deltas.length) {
    final asWords = deltas[index] > 0xFF;
    var runLength = 1;
    while (index + runLength < deltas.length &&
        runLength < 128 &&
        (deltas[index + runLength] > 0xFF) == asWords) {
      runLength++;
    }
    writer.uint8((asWords ? 0x80 : 0) | (runLength - 1));
    for (var step = 0; step < runLength; step++) {
      if (asWords) {
        writer.uint16(deltas[index + step]);
      } else {
        writer.uint8(deltas[index + step]);
      }
    }
    index += runLength;
  }
  return writer.toBytes();
}

/// Flags of a packed delta run's control byte.
abstract final class DeltaRunFlag {
  /// The run's deltas are all zero and nothing follows the control byte.
  static const zero = 0x80;

  /// The run's deltas are stored as 16 bit values.
  static const words = 0x40;

  /// The bits holding the run length, one less than the real length.
  static const countMask = 0x3F;
}

/// Packs delta values into the run-length form `gvar` uses.
///
/// Three kinds of run are available — all zero, one byte each, two bytes each —
/// and the encoder greedily takes the longest run of whichever kind starts at
/// the current position.
Uint8List _packDeltas(List<int> values) {
  final writer = BinaryWriter();
  var index = 0;
  while (index < values.length) {
    if (values[index] == 0) {
      var runLength = 1;
      while (index + runLength < values.length &&
          runLength < 64 &&
          values[index + runLength] == 0) {
        runLength++;
      }
      writer.uint8(DeltaRunFlag.zero | (runLength - 1));
      index += runLength;
      continue;
    }
    final asWords = values[index] < -128 || values[index] > 127;
    var runLength = 1;
    while (index + runLength < values.length &&
        runLength < 64 &&
        values[index + runLength] != 0 &&
        (values[index + runLength] < -128 || values[index + runLength] > 127) ==
            asWords) {
      runLength++;
    }
    writer.uint8((asWords ? DeltaRunFlag.words : 0) | (runLength - 1));
    for (var step = 0; step < runLength; step++) {
      if (asWords) {
        writer.int16(values[index + step]);
      } else {
        writer.int8(values[index + step]);
      }
    }
    index += runLength;
  }
  return writer.toBytes();
}
