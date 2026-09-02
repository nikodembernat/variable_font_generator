import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// A position in the design space, as normalised coordinates keyed by axis tag.
///
/// Axes left out of the map sit at their default, which is zero once
/// normalised.
typedef AxisLocation = Map<String, double>;

/// The part of an axis over which one master has any influence: it fades in
/// from its `start`, reaches full strength at its `peak` and fades back out at
/// its `end`.
typedef AxisRegion = ({double start, double peak, double end});

/// The support region of one master, keyed by axis tag.
typedef MasterSupport = Map<String, AxisRegion>;

/// Works out how to express a set of masters as deltas from the default one.
///
/// This is the piece that makes `gvar` possible. Given outlines drawn at a
/// handful of positions in the design space, it computes one delta set per
/// position such that adding up every delta, each scaled by how strongly its
/// region applies, reproduces the original outlines exactly at those positions
/// and interpolates smoothly in between.
///
/// The construction follows the OpenType specification's model: masters are
/// ordered from simplest to most specific, each one's region is narrowed so it
/// does not reach past a master that already covers part of it, and each
/// delta is what remains of a master once the masters before it have had their
/// say.
@immutable
final class VariationModel {
  /// Builds a model for [locations].
  ///
  /// The first location must be the default, that is, the one where every axis
  /// sits at zero. [axisOrder] fixes the order axes are compared in so the
  /// result does not depend on map iteration order.
  factory VariationModel(
    List<AxisLocation> locations, {
    required List<String> axisOrder,
  }) {
    if (locations.isEmpty) {
      throw ArgumentError.value(
        locations,
        'locations',
        'A model needs at least the default location',
      );
    }
    final cleaned = [
      for (final location in locations)
        <String, double>{
          for (final entry in location.entries)
            if (entry.value != 0) entry.key: entry.value,
        },
    ];
    if (cleaned.first.isNotEmpty) {
      throw ArgumentError.value(
        locations,
        'locations',
        'The first location must be the default, with every axis at zero',
      );
    }
    final seen = <String>{};
    for (final location in cleaned) {
      final key = _keyOf(location, axisOrder);
      if (!seen.add(key)) {
        throw ArgumentError.value(
          locations,
          'locations',
          'Duplicate master location $location',
        );
      }
    }

    final order = _sortOrder(cleaned, axisOrder);
    final sorted = [for (final index in order) cleaned[index]];
    final supports = _computeSupports(sorted, axisOrder);
    final weights = <Map<int, double>>[];
    for (var i = 0; i < sorted.length; i++) {
      final row = <int, double>{};
      for (var j = 0; j < i; j++) {
        final scalar = supportScalar(sorted[i], supports[j]);
        if (scalar != 0) {
          row[j] = scalar;
        }
      }
      weights.add(row);
    }
    return VariationModel._(
      axisOrder: axisOrder,
      originalOrder: order,
      sortedLocations: sorted,
      supports: supports,
      deltaWeights: weights,
    );
  }

  const VariationModel._({
    required this.axisOrder,
    required this.originalOrder,
    required this.sortedLocations,
    required this.supports,
    required this.deltaWeights,
  });

  /// The order axes are compared in.
  final List<String> axisOrder;

  /// For each master in model order, its index in the list the caller passed.
  final List<int> originalOrder;

  /// The master locations, ordered from simplest to most specific.
  final List<AxisLocation> sortedLocations;

  /// The support region of each master, in the same order as
  /// [sortedLocations].
  final List<MasterSupport> supports;

  /// For each master, how strongly each earlier master already contributes at
  /// its location.
  final List<Map<int, double>> deltaWeights;

  /// The number of masters.
  int get masterCount => sortedLocations.length;

  /// Solves for the delta of each master, in model order.
  ///
  /// [masterValues] must be in the order the locations were passed to the
  /// constructor, not the order [sortedLocations] puts them in; the reordering
  /// happens here. [subtract] and [scale] let the same solver work for
  /// any value type, which is how a list of points and a single advance width
  /// share one implementation.
  ///
  /// [normalize] is applied to each delta as it is solved, before it is used to
  /// solve the ones after it. Rounding there rather than at the end is what
  /// makes a master reproduce exactly: the deltas that go into the font are the
  /// same ones the solver worked with.
  List<T> solveDeltas<T>(
    List<T> masterValues, {
    required T Function(T a, T b) subtract,
    required T Function(T value, double factor) scale,
    T Function(T value)? normalize,
  }) {
    if (masterValues.length != masterCount) {
      throw ArgumentError.value(
        masterValues,
        'masterValues',
        'Expected $masterCount values, one per master',
      );
    }
    final deltas = <T>[];
    for (var i = 0; i < masterCount; i++) {
      var delta = masterValues[originalOrder[i]];
      for (final entry in deltaWeights[i].entries) {
        delta = subtract(delta, scale(deltas[entry.key], entry.value));
      }
      deltas.add(normalize == null ? delta : normalize(delta));
    }
    return deltas;
  }

  /// How strongly the master with [support] applies at [location].
  ///
  /// Zero outside the support's range, one at its peak, and linear in between.
  static double supportScalar(AxisLocation location, MasterSupport support) {
    var scalar = 1.0;
    for (final entry in support.entries) {
      final (:start, :peak, :end) = entry.value;
      final value = location[entry.key] ?? 0;
      if (peak == 0 || value == peak) {
        continue;
      }
      if (value <= start || end <= value) {
        return 0;
      }
      scalar *= value < peak
          ? (value - start) / (peak - start)
          : (end - value) / (end - peak);
    }
    return scalar;
  }

  /// Orders masters from the simplest to the most specific.
  ///
  /// A master that moves fewer axes has to be applied first, because the ones
  /// that move more axes are corrections on top of it.
  static List<int> _sortOrder(
    List<AxisLocation> locations,
    List<String> axisOrder,
  ) {
    final indices = List.generate(locations.length, (index) => index)
      ..sort((a, b) {
        final left = locations[a];
        final right = locations[b];
        final byCount = left.length.compareTo(right.length);
        if (byCount != 0) {
          return byCount;
        }
        return _keyOf(left, axisOrder).compareTo(_keyOf(right, axisOrder));
      });
    return indices;
  }

  static String _keyOf(AxisLocation location, List<String> axisOrder) {
    final parts = <String>[];
    for (final axis in axisOrder) {
      final value = location[axis];
      if (value != null && value != 0) {
        parts.add('$axis=${value.toStringAsFixed(6)}');
      }
    }
    for (final entry in location.entries) {
      if (!axisOrder.contains(entry.key) && entry.value != 0) {
        parts.add('${entry.key}=${entry.value.toStringAsFixed(6)}');
      }
    }
    return parts.join(',');
  }

  /// Turns each location into the region it influences, narrowing regions that
  /// would otherwise reach past a master already covering part of them.
  static List<MasterSupport> _computeSupports(
    List<AxisLocation> sorted,
    List<String> axisOrder,
  ) {
    // How far each axis is used in either direction. A master's influence
    // reaches out to there, not merely to its own peak: a master halfway along
    // an axis has to keep contributing past itself, or everything between it
    // and the next one falls back towards the default.
    final lowest = <String, double>{};
    final highest = <String, double>{};
    for (final location in sorted) {
      for (final entry in location.entries) {
        lowest[entry.key] = math.min(
          entry.value,
          lowest[entry.key] ?? entry.value,
        );
        highest[entry.key] = math.max(
          entry.value,
          highest[entry.key] ?? entry.value,
        );
      }
    }

    final supports = <MasterSupport>[];
    for (final location in sorted) {
      final region = <String, AxisRegion>{
        for (final entry in location.entries)
          entry.key: (
            start: entry.value < 0 ? (lowest[entry.key] ?? entry.value) : 0,
            peak: entry.value,
            end: entry.value > 0 ? (highest[entry.key] ?? entry.value) : 0,
          ),
      };
      final axes = region.keys.toSet();
      for (final previous in supports) {
        if (!const SetEquality<String>().equals(previous.keys.toSet(), axes)) {
          continue;
        }
        // Only a master whose peak falls inside this region can shorten it.
        final relevant = region.entries.every((entry) {
          final previousPeak = previous[entry.key]!.peak;
          final here = entry.value;
          return previousPeak == here.peak ||
              (here.start < previousPeak && previousPeak < here.end);
        });
        if (!relevant) {
          continue;
        }
        // Cut along whichever axis loses the least, so the region stays as
        // wide as it can.
        var bestRatio = -1.0;
        final best = <String, AxisRegion>{};
        for (final entry in previous.entries) {
          final value = entry.value.peak;
          final here = region[entry.key]!;
          if (value == here.peak) {
            continue;
          }
          final double ratio;
          final AxisRegion narrowed;
          if (value < here.peak) {
            ratio = (value - here.peak) / (here.start - here.peak);
            narrowed = (start: value, peak: here.peak, end: here.end);
          } else {
            ratio = (value - here.peak) / (here.end - here.peak);
            narrowed = (start: here.start, peak: here.peak, end: value);
          }
          if (ratio > bestRatio) {
            bestRatio = ratio;
            best.clear();
          }
          if (ratio == bestRatio) {
            best[entry.key] = narrowed;
          }
        }
        region.addAll(best);
      }
      supports.add(region);
    }
    return supports;
  }
}
