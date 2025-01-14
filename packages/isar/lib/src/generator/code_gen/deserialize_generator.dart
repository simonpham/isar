// ignore_for_file: use_string_buffers, no_default_cases

part of isar_generator;

String _generateDeserialize(ObjectInfo object) {
  var code = '''
  @isarProtected
  ${object.dartName} deserialize${object.dartName}(IsarReader reader) {''';

  final propertiesByMode = {
    DeserializeMode.none: <PropertyInfo>[],
    DeserializeMode.assign: <PropertyInfo>[],
    DeserializeMode.positionalParam: <PropertyInfo>[],
    DeserializeMode.namedParam: <PropertyInfo>[],
  };
  for (final property in object.properties) {
    propertiesByMode[property.mode]!.add(property);
  }

  final positional = propertiesByMode[DeserializeMode.positionalParam]!;
  positional.sort(
    (p1, p2) => p1.constructorPosition!.compareTo(p2.constructorPosition!),
  );
  final named = propertiesByMode[DeserializeMode.namedParam]!;

  for (final p in [...positional, ...named]) {
    code += 'final ${p.dartType} _${p.dartName};';
    code += _deserializeProperty(object, p, (value) {
      return '_${p.dartName} = $value;';
    });
  }

  code += 'final object = ${object.dartName}(';

  for (final p in positional) {
    code += '_${p.dartName},';
  }

  for (final p in named) {
    code += '${p.dartName}: _${p.dartName},';
  }

  code += ');';

  final assign = propertiesByMode[DeserializeMode.assign]!;
  for (final p in assign) {
    code += _deserializeProperty(object, p, (value) {
      return 'object.${p.dartName} = $value;';
    });
  }

  return '''
    $code
    return object;
  }''';
}

String _generateDeserializeProp(ObjectInfo object) {
  var code = '''
    @isarProtected
    dynamic deserialize${object.dartName}Prop(IsarReader reader, int property) {
      switch (property) {''';
  for (final p in object.properties) {
    final deser = _deserializeProperty(object, p, (value) {
      return 'return $value;';
    });
    code += 'case ${p.index}: $deser';
  }

  return '''
      $code
      default:
        throw ArgumentError('Unknown property: \$property');
      }
    }
    ''';
}

String _deserializeProperty(
  ObjectInfo object,
  PropertyInfo p,
  String Function(String value) result,
) {
  return _deserialize(
    index: p.index.toString(),
    isId: p.isId,
    typeClassName: p.typeClassName,
    type: p.type,
    elementDartType: p.scalarDartType,
    defaultValue: p.defaultValue,
    elementDefaultValue: p.elementDefaultValue,
    utc: p.utc,
    transform: (value) {
      if (p.isEnum && !p.type.isList) {
        return result(
          '${p.enumMapName(object)}[$value] ?? ${p.defaultValue}',
        );
      } else {
        return result(value);
      }
    },
    transformElement: (value) {
      if (p.isEnum) {
        return '${p.enumMapName(object)}[$value] ?? ${p.elementDefaultValue}';
      } else {
        return value;
      }
    },
  );
}

String _deserialize({
  required String index,
  required bool isId,
  required String typeClassName,
  required PropertyType type,
  String? elementDartType,
  required String defaultValue,
  String? elementDefaultValue,
  required bool utc,
  required String Function(String value) transform,
  String Function(String value)? transformElement,
}) {
  switch (type) {
    case PropertyType.bool:
      if (defaultValue == 'false') {
        return transform('IsarCore.readBool(reader, $index)');
      } else {
        return '''
        {
          if (IsarCore.readNull(reader, $index)) {
            ${transform(defaultValue)}
          } else {
            ${transform('IsarCore.readBool(reader, $index)')}
          }
        }''';
      }
    case PropertyType.byte:
      if (defaultValue == '0') {
        return transform('IsarCore.readByte(reader, $index)');
      } else {
        return '''
        {
          final value = IsarCore.readByte(reader, $index);
          if (value == $_nullByte) {
            ${transform(defaultValue)}
          } else {
            ${transform('value')}
          }
        }''';
      }
    case PropertyType.int:
      if (defaultValue == '$_nullInt') {
        return transform('IsarCore.readInt(reader, $index)');
      } else {
        return '''
        {
          final value = IsarCore.readInt(reader, $index);
          if (value == $_nullInt) {
            ${transform(defaultValue)}
          } else {
            ${transform('value')}
          }
        }''';
      }
    case PropertyType.float:
      if (defaultValue == 'double.nan') {
        return transform('IsarCore.readFloat(reader, $index)');
      } else {
        return '''
        {
          final value = IsarCore.readFloat(reader, $index);
          if (value.isNaN) {
            ${transform(defaultValue)}
          } else {
            ${transform('value')}
          }
        }''';
      }
    case PropertyType.long:
      if (isId) {
        return transform('IsarCore.readId(reader)');
      } else if (defaultValue == '$_nullLong') {
        return transform('IsarCore.readLong(reader, $index)');
      } else {
        return '''
        {
          final value = IsarCore.readLong(reader, $index);
          if (value == $_nullLong) {
            ${transform(defaultValue)}
          } else {
            ${transform('value')}
          }
        }''';
      }
    case PropertyType.dateTime:
      final toLocal = utc ? '' : '.toLocal()';
      return '''
        {
          final value = IsarCore.readLong(reader, $index);
          if (value == $_nullLong) {
            ${transform(defaultValue)}
          } else {
            ${transform('DateTime.fromMicrosecondsSinceEpoch(value, isUtc: true)$toLocal')}
          }
        }''';

    case PropertyType.double:
      if (defaultValue == 'double.nan') {
        return transform('IsarCore.readDouble(reader, $index)');
      } else {
        return '''
        {
          final value = IsarCore.readDouble(reader, $index);
          if (value.isNaN) {
            ${transform(defaultValue)}
          } else {
            ${transform('value')}
          }
        }''';
      }
    case PropertyType.string:
      if (defaultValue == 'null') {
        return transform('IsarCore.readString(reader, $index)');
      } else {
        return transform(
          'IsarCore.readString(reader, $index) ?? $defaultValue',
        );
      }

    case PropertyType.object:
      return '''
      {
        final objectReader = IsarCore.readObject(reader, $index);
        if (objectReader.isNull) {
          ${transform(defaultValue)}
        } else {
          final embedded = deserialize$typeClassName(objectReader);
          IsarCore.freeReader(objectReader);
          ${transform('embedded')}
        }
      }''';
    case PropertyType.boolList:
    case PropertyType.byteList:
    case PropertyType.intList:
    case PropertyType.floatList:
    case PropertyType.longList:
    case PropertyType.dateTimeList:
    case PropertyType.doubleList:
    case PropertyType.stringList:
    case PropertyType.objectList:
      final deser = _deserialize(
        index: 'i',
        isId: false,
        typeClassName: typeClassName,
        type: type.scalarType,
        defaultValue: elementDefaultValue!,
        utc: utc,
        transform: (value) => 'list[i] = ${transformElement!(value)};',
      );
      return '''
      {
        final length = IsarCore.readList(reader, $index, IsarCore.readerPtrPtr);
        {
          final reader = IsarCore.readerPtr;
          if (reader.isNull) {
            ${transform(defaultValue)}
          } else {
            final list = List<$elementDartType>.filled(length, $elementDefaultValue, growable: true);
            for (var i = 0; i < length; i++) {
              $deser
            }
            IsarCore.freeReader(reader);
            ${transform('list')}
          }
        }
      }''';
    case PropertyType.json:
      if (typeClassName == 'dynamic') {
        return transform(
          'isarJsonDecode(IsarCore.readString(reader, $index) '
          "?? 'null') ?? $defaultValue",
        );
      } else {
        return '''
        {
          final json = isarJsonDecode(IsarCore.readString(reader, $index) ?? 'null');
          if (json is ${typeClassName == 'List' ? 'List' : 'Map<String, dynamic>'}) {
            ${typeClassName == 'List' || typeClassName == 'Map' ? transform('json') : transform('$typeClassName.fromJson(json)')}
          } else {
            ${transform(defaultValue)}
          }
        }''';
      }
  }
}
