part of isar;

/// Specifies how an index is stored in Isar.
enum IndexType {
  /// Stores the value as-is in the index.
  value,

  /// Strings or Lists can be hashed to reduce the storage required by the
  /// index. The disadvantage of hash indexes is that they can't be used for
  /// prefix scans (`startsWith()` where clauses). String and list indexes are
  /// hashed by default.
  hash,

  /// `List<String>` can hash its elements.
  hashElements,
}

/// Annotate properties to build an index.
@Target({TargetKind.field, TargetKind.getter})
class Index {
  /// Annotate properties to build an index.
  const Index({
    this.name,
    this.composite = const [],
    this.unique = false,
    this.type,
    this.caseSensitive,
  });

  /// Name of the index. By default, the names of the properties are
  /// concatenated using "_"
  final String? name;

  /// Specify up to two other properties to build a composite index.
  final List<String> composite;

  /// A unique index ensures the index does not contain any duplicate values.
  /// Any attempt to insert or update data into the unique index that causes a
  /// duplicate will result in an error.
  final bool unique;

  /// Specifies how an index is stored in Isar.
  ///
  /// Defaults to:
  /// - `IndexType.hash` for `String`s and `List`s
  /// - `IndexType.value` for all other types
  final IndexType? type;

  /// String or `List<String>` indexes can be case sensitive (default) or case
  /// insensitive.
  final bool? caseSensitive;
}
