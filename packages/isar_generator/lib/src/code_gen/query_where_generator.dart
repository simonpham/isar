import 'package:isar/isar.dart';
import 'package:isar_generator/src/object_info.dart';
import 'package:dartx/dartx.dart';

class WhereGenerator {
  final ObjectInfo object;
  final String objName;
  final existing = <String>{};

  WhereGenerator(this.object) : objName = object.dartName;

  String generate() {
    final primaryIndex = ObjectIndex(
      name: '_id',
      unique: true,
      replace: true,
      properties: [
        ObjectIndexProperty(
          property: object.idProperty,
          type: IndexType.hash,
          caseSensitive: false,
        ),
      ],
    );

    var code =
        'extension ${objName}QueryWhereSort on QueryBuilder<$objName, $objName, QWhere> {';

    for (var i = -1; i < object.indexes.length; i++) {
      final index = i == -1 ? primaryIndex : object.indexes[i];
      code += generateAny(index.name, index.properties);
    }

    code += '''
  }

  extension ${objName}QueryWhere on QueryBuilder<$objName, $objName, QWhereClause> {
  ''';

    for (var index in object.indexes) {
      for (var n = 0; n < index.properties.length; n++) {
        var properties = index.properties.sublist(0, n + 1);

        final firstProperties = properties.sublist(0, n);
        final lastProperty = properties.last;
        if (!firstProperties.any((it) => it.isarType.isFloatDouble)) {
          code += generateWhereEqualTo(index.name, properties);
          code += generateWhereNotEqualTo(index.name, properties);
        }

        if (lastProperty.scalarType == IsarType.Int ||
            lastProperty.scalarType == IsarType.Long ||
            lastProperty.scalarType.isFloatDouble) {
          code += generateWhereGreaterThan(index.name, properties);
          code += generateWhereLessThan(index.name, properties);
        }

        if (lastProperty.scalarType == IsarType.String &&
            lastProperty.type != IndexType.hash) {
          code += generateWhereStartsWith(index.name, properties);
        }

        if (lastProperty.scalarType != IsarType.Bool) {
          code += generateWhereBetween(index.name, properties);
        }

        if (index.properties.length == 1 && lastProperty.property.nullable) {
          code += generateWhereIsNull(index.name, lastProperty);
          code += generateWhereIsNotNull(index.name, lastProperty);
        }
      }
    }

    return '$code}';
  }

  String joinToName(List<ObjectIndexProperty> properties, bool firstEqualTo) {
    String propertyName(ObjectIndexProperty p, int i) {
      if (i == 0) {
        return p.property.dartName.decapitalize();
      } else {
        return p.property.dartName.capitalize();
      }
    }

    var firstPropertiesName = properties
        .sublist(0, properties.length - 1)
        .mapIndexed((i, p) => propertyName(p, i))
        .join('');

    if (firstPropertiesName.isNotEmpty && firstEqualTo) {
      firstPropertiesName += 'EqualTo';
    }

    firstPropertiesName += propertyName(properties.last, properties.lastIndex);

    return firstPropertiesName;
  }

  String joinToParams(List<ObjectIndexProperty> properties) {
    return properties.map((it) {
      if (it.property.isarType.isList && it.type != IndexType.hash) {
        return '${it.property.dartType} ${it.property.dartName}Element';
      } else {
        return '${it.property.dartType} ${it.property.dartName}';
      }
    }).join(',');
  }

  String joinToValues(List<ObjectIndexProperty> properties) {
    final values = properties.map((it) {
      if (it.property.isarType.isList && it.type != IndexType.hash) {
        return '${it.property.dartName}Element';
      } else {
        return it.property.toIsar(it.property.dartName, object);
      }
    }).join(', ');
    return values;
  }

  String generateAny(String indexName, List<ObjectIndexProperty> properties) {
    final name = 'any' + joinToName(properties, false).capitalize();
    if (!existing.add(name)) return '';
    return '''
  QueryBuilder<$objName, $objName, QAfterWhere> $name() {
    return addWhereClause(WhereClause(indexName: '$indexName'));
  }
  ''';
  }

  String generateWhereEqualTo(
      String indexName, List<ObjectIndexProperty> properties) {
    final name = joinToName(properties, false) + 'EqualTo';
    if (!existing.add(name)) return '';

    final values = joinToValues(properties);
    final params = joinToParams(properties);
    return '''
  QueryBuilder<$objName, $objName, QAfterWhereClause> $name($params) {
    return addWhereClause(WhereClause(
      indexName: '$indexName',
      lower: [$values],
      includeLower: true,
      upper: [$values],
      includeUpper: true,
    ));
  }
  ''';
  }

  String generateWhereNotEqualTo(
      String indexName, List<ObjectIndexProperty> properties) {
    final name = joinToName(properties, false) + 'NotEqualTo';
    if (!existing.add(name)) return '';

    final values = joinToValues(properties);
    final params = joinToParams(properties);
    return '''
  QueryBuilder<$objName, $objName, QAfterWhereClause> $name($params) {
    return addWhereClause(WhereClause(
      indexName: '$indexName',
      upper: [$values],
      includeUpper: false,
    )).addWhereClause(WhereClause(
      indexName: '$indexName',
      lower: [$values],
      includeLower: false,
    ));
  }
  ''';
  }

  String generateWhereGreaterThan(
      String indexName, List<ObjectIndexProperty> properties) {
    final name = joinToName(properties, true) + 'GreaterThan';
    if (!existing.add(name)) return '';

    final values = joinToValues(properties);
    final params = joinToParams(properties);
    return '''
  QueryBuilder<$objName, $objName, QAfterWhereClause> $name($params) {
    return addWhereClause(WhereClause(
      indexName: '$indexName',
      lower: [$values],
      includeLower: false,
    ));
  }
  ''';
  }

  String generateWhereLessThan(
      String indexName, List<ObjectIndexProperty> properties) {
    final name = joinToName(properties, true) + 'LessThan';
    if (!existing.add(name)) return '';

    final params = joinToParams(properties);
    final values = joinToValues(properties);
    return '''
  QueryBuilder<$objName, $objName, QAfterWhereClause> $name($params) {
    return addWhereClause(WhereClause(
      indexName: '$indexName',
      upper: [$values],
      includeUpper: false,
    ));
  }
  ''';
  }

  String generateWhereBetween(
      String indexName, List<ObjectIndexProperty> properties) {
    final firstPs = properties.sublist(0, properties.length - 1);
    final lastP = properties.last.property;
    final lowerName = 'lower${lastP.dartName.capitalize()}';
    final upperName = 'upper${lastP.dartName.capitalize()}';
    final name = joinToName(properties, true) + 'Between';
    if (!existing.add(name)) return '';

    var params = joinToParams(firstPs);
    if (params.isNotEmpty) {
      params += ',';
    }
    params += '${lastP.dartType} $lowerName, ${lastP.dartType} $upperName';
    var values = joinToValues(firstPs);
    if (values.isNotEmpty) {
      values += ',';
    }
    return '''
  QueryBuilder<$objName, $objName, QAfterWhereClause> $name($params) {
    return addWhereClause(WhereClause(
      indexName: '$indexName',
      lower: [$values $lowerName],
      includeLower: true,
      upper: [$values $upperName],
      includeUpper: true,
    ));
  }
  ''';
  }

  String generateWhereIsNull(
      String indexName, ObjectIndexProperty indexProperty) {
    final name = joinToName([indexProperty], false) + 'IsNull';
    if (!existing.add(name)) return '';

    return '''
  QueryBuilder<$objName, $objName, QAfterWhereClause> $name() {
    return addWhereClause(WhereClause(
      indexName: '$indexName',
      upper: [null],
      includeUpper: true,
      lower: [null],
      includeLower: true,
    ));
  }
  ''';
  }

  String generateWhereIsNotNull(
      String indexName, ObjectIndexProperty indexProperty) {
    final name = joinToName([indexProperty], false) + 'IsNotNull';
    if (!existing.add(name)) return '';

    return '''
  QueryBuilder<$objName, $objName, QAfterWhereClause> $name() {
    return addWhereClause(WhereClause(
      indexName: '$indexName',
      lower: [null],
      includeLower: false,
    ));
  }
  ''';
  }

  String generateWhereStartsWith(
      String indexName, List<ObjectIndexProperty> properties) {
    final firsPs = properties.sublist(0, properties.length - 1);
    final lastP = properties.last.property;
    final name = joinToName(properties, true) + 'StartsWith';
    if (!existing.add(name)) return '';

    var params = joinToParams(firsPs);
    if (params.isNotEmpty) {
      params += ',';
    }
    final lastName = '${lastP.dartName}Prefix';
    params +=
        '${lastP.converter == null ? 'String' : lastP.dartType} $lastName';
    var values = joinToValues(firsPs);
    if (values.isNotEmpty) {
      values += ',';
    }

    return '''
  QueryBuilder<$objName, $objName, QAfterWhereClause> $name($params) {
    return addWhereClause(WhereClause(
      indexName: '$indexName',
      lower: [$values '\$$lastName'],
      includeLower: true,
      upper: [$values '\$$lastName\\u{FFFFF}'],
      includeUpper: true,
    ));
  }
  ''';
  }
}