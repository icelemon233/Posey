typedef Json = Map<String, dynamic>;
Json objectOf(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<String> stringsOf(dynamic value) =>
    value is List ? value.whereType<String>().toList() : <String>[];
int integerOf(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
