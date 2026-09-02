import 'package:meta/meta.dart';
import 'package:variable_font_generator/src/font/tables/fvar_table.dart';
import 'package:variable_font_generator/src/font/tables/stat_table.dart';
import 'package:variable_font_generator/src/variations/font_axis.dart';
import 'package:variable_font_generator/src/variations/variation_model.dart';

/// An axis of a generated icon font, together with what it does to the artwork.
///
/// Stroke-based icons have two things worth varying: how thick the strokes are
/// and whether the shapes they outline are filled in. Every axis drives one of
/// those two, which is what keeps the design space small enough to describe
/// exactly with a handful of masters.
@immutable
final class IconAxis {
  /// Creates an axis that changes the stroke width.
  const IconAxis({
    required this.axis,
    required this.strokeScaleAtMinimum,
    required this.strokeScaleAtMaximum,
  }) : controlsFill = false;

  /// Creates an axis that fills the shapes in rather than changing their
  /// stroke width.
  const IconAxis.fill(this.axis)
    : strokeScaleAtMinimum = 1,
      strokeScaleAtMaximum = 1,
      controlsFill = true;

  /// The axis as it appears in `fvar`.
  final FontAxis axis;

  /// How thick the strokes are at the axis's minimum, as a multiple of the
  /// artwork's own stroke width.
  final double strokeScaleAtMinimum;

  /// How thick the strokes are at the axis's maximum.
  final double strokeScaleAtMaximum;

  /// Whether this axis closes the shapes' holes instead of changing the stroke
  /// width.
  final bool controlsFill;

  /// This axis's contribution at a normalised coordinate.
  double strokeScaleContribution(double normalized) {
    if (controlsFill || normalized == 0) {
      return 0;
    }
    return normalized < 0
        ? -normalized * (strokeScaleAtMinimum - 1)
        : normalized * (strokeScaleAtMaximum - 1);
  }

  @override
  String toString() => 'IconAxis(${axis.tag})';
}

/// The set of axes a generated icon font offers.
///
/// [material] matches the four axes Flutter's `Icon` widget can drive, so an
/// icon generated with it responds to `fill`, `weight`, `grade` and
/// `opticalSize` with no extra work on the application's side.
@immutable
final class IconAxisSet {
  /// Creates an axis set.
  const IconAxisSet(this.axes);

  /// The `FILL` axis, which closes the holes in outlined shapes.
  ///
  /// Flutter's `Icon.fill` drives it and requires it to run from 0 to 1.
  static const fillAxis = IconAxis.fill(
    FontAxis(
      tag: 'FILL',
      name: 'Fill',
      minimum: 0,
      defaultValue: 0,
      maximum: 1,
    ),
  );

  /// The `wght` axis, which changes stroke thickness over a wide range.
  ///
  /// The range matches Material Symbols so that an application can use the same
  /// numbers for both.
  static const weightAxis = IconAxis(
    axis: FontAxis(
      tag: 'wght',
      name: 'Weight',
      minimum: 100,
      defaultValue: 400,
      maximum: 700,
    ),
    strokeScaleAtMinimum: 0.5,
    strokeScaleAtMaximum: 1.5,
  );

  /// The `GRAD` axis, a finer adjustment to stroke thickness.
  ///
  /// Grade exists so that an icon can be nudged to match the weight of the text
  /// beside it, or compensated when it is drawn light-on-dark, without moving
  /// as far as a weight change would.
  static const gradeAxis = IconAxis(
    axis: FontAxis(
      tag: 'GRAD',
      name: 'Grade',
      minimum: -50,
      defaultValue: 0,
      maximum: 200,
    ),
    strokeScaleAtMinimum: 0.92,
    strokeScaleAtMaximum: 1.3,
  );

  /// The `opsz` axis, which compensates for the size an icon is drawn at.
  ///
  /// A shape drawn small needs proportionally thicker strokes to stay legible,
  /// and one drawn large needs thinner ones to avoid looking heavy, so the
  /// stroke scale runs the opposite way to the axis.
  static const opticalSizeAxis = IconAxis(
    axis: FontAxis(
      tag: 'opsz',
      name: 'Optical size',
      minimum: 20,
      defaultValue: 24,
      maximum: 48,
    ),
    strokeScaleAtMinimum: 1.06,
    strokeScaleAtMaximum: 0.78,
  );

  /// The four axes Flutter's `Icon` widget knows how to drive.
  static const material = IconAxisSet([
    fillAxis,
    weightAxis,
    gradeAxis,
    opticalSizeAxis,
  ]);

  /// The axes, in the order `fvar` and `gvar` list them.
  final List<IconAxis> axes;

  /// The axes as `fvar` records them.
  List<FontAxis> get fontAxes => [for (final axis in axes) axis.axis];

  /// The axis tags, in font order.
  List<String> get tags => [for (final axis in axes) axis.axis.tag];

  /// The stroke scale and fill amount at a normalised design-space position.
  ({double strokeScale, double fill}) resolve(AxisLocation location) {
    var strokeScale = 1.0;
    var fill = 0.0;
    for (final axis in axes) {
      final normalized = location[axis.axis.tag] ?? 0;
      if (axis.controlsFill) {
        fill += normalized.clamp(0, 1);
      } else {
        strokeScale += axis.strokeScaleContribution(normalized);
      }
    }
    return (strokeScale: strokeScale, fill: fill.clamp(0, 1));
  }

  /// The master positions needed to reproduce [resolve] exactly everywhere.
  ///
  /// The outline of an icon is affine in the stroke scale and affine in the
  /// fill amount, but the product of the two is not: filling a shape moves its
  /// inner boundary onto a point, and how far each point has to travel depends
  /// on how thick the stroke was to begin with. Interpolation is linear, so the
  /// design space needs a master at every corner where those two effects meet —
  /// the default, each axis on its own at both ends, and each stroke axis
  /// combined with a full fill.
  List<AxisLocation> get masterLocations {
    final scaleAxes = [
      for (final axis in axes)
        if (!axis.controlsFill) axis,
    ];
    final fillAxes = [
      for (final axis in axes)
        if (axis.controlsFill) axis,
    ];

    List<double> extremesOf(IconAxis axis) => [
      if (axis.axis.minimum < axis.axis.defaultValue) -1.0,
      if (axis.axis.maximum > axis.axis.defaultValue) 1.0,
    ];

    return [
      const <String, double>{},
      for (final axis in scaleAxes)
        for (final extreme in extremesOf(axis)) {axis.axis.tag: extreme},
      for (final fillAxis in fillAxes)
        for (final fillExtreme in extremesOf(fillAxis)) ...[
          {fillAxis.axis.tag: fillExtreme},
          for (final axis in scaleAxes)
            for (final extreme in extremesOf(axis))
              {fillAxis.axis.tag: fillExtreme, axis.axis.tag: extreme},
        ],
    ];
  }

  /// The variation model for [masterLocations].
  VariationModel buildModel() =>
      VariationModel(masterLocations, axisOrder: tags);

  /// A reasonable set of named instances for a font with these axes.
  ///
  /// Only the weight axis gets named instances: those are the styles a font
  /// picker can meaningfully offer, whereas grade and optical size are meant to
  /// be driven by the application rather than chosen by a person.
  List<NamedInstance> get defaultInstances {
    final weight = axes
        .where((axis) => axis.axis.tag == 'wght')
        .firstOrNull
        ?.axis;
    if (weight == null) {
      return const [];
    }
    const named = {
      100: 'Thin',
      200: 'ExtraLight',
      300: 'Light',
      400: 'Regular',
      500: 'Medium',
      600: 'SemiBold',
      700: 'Bold',
    };
    return [
      for (final entry in named.entries)
        if (entry.key >= weight.minimum && entry.key <= weight.maximum)
          NamedInstance(
            name: entry.value,
            coordinates: {weight.tag: entry.key.toDouble()},
          ),
    ];
  }

  /// The `STAT` entries describing the named positions on each axis.
  List<AxisValueName> get defaultAxisValueNames => [
    for (final instance in defaultInstances)
      AxisValueName(
        axisTag: 'wght',
        name: instance.name,
        value: instance.coordinates['wght']!,
        isDefault: instance.name == 'Regular',
        isElidable: instance.name == 'Regular',
      ),
    for (final axis in axes)
      if (axis.axis.tag != 'wght')
        AxisValueName(
          axisTag: axis.axis.tag,
          name: 'Regular',
          value: axis.axis.defaultValue,
          isDefault: true,
          isElidable: true,
        ),
  ];

  @override
  String toString() => 'IconAxisSet(${tags.join(', ')})';
}
