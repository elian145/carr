import '../../../models/chat_message.dart';
import '../../../models/listing.dart';
import '../../../models/user_profile.dart';

/// Normalize API list payloads to [ListingSummary] rows.
List<ListingSummary> listingSummariesFromList(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map(
        (m) => ListingSummary.fromJson(
          Map<String, dynamic>.from(
            m.map((k, v) => MapEntry(k.toString(), v)),
          ),
        ),
      )
      .where((s) => s.id.isNotEmpty)
      .toList(growable: false);
}

/// Parses API listing rows, drops invalid ids, normalizes keys and core fields.
List<Map<String, dynamic>> listingMapsFromApiList(Object? raw) {
  if (raw is! List) return const [];
  final out = <Map<String, dynamic>>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final map = Map<String, dynamic>.from(
      item.map((k, v) => MapEntry(k.toString(), v)),
    );
    final summary = ListingSummary.fromJson(map);
    if (summary.id.isEmpty) continue;
    map['id'] = summary.id;
    final title = summary.title.trim();
    if (title.isNotEmpty) {
      map['title'] = title;
    }
    out.add(map);
  }
  return out;
}

/// Accepts a decoded JSON body (`List` or `{cars: [...]}`).
List<Map<String, dynamic>> listingMapsFromApiResponse(Object? decoded) {
  if (decoded is List) return listingMapsFromApiList(decoded);
  if (decoded is Map && decoded['cars'] is List) {
    return listingMapsFromApiList(decoded['cars']);
  }
  return const [];
}

/// Typed listing summary for cards and list rows.
typedef ListingMap = Map<String, dynamic>;

extension ListingMapX on ListingMap {
  ListingSummary toListingSummary() => ListingSummary.fromJson(this);
}

/// Normalize API maps to [UserProfile].
UserProfile? userProfileFromMap(Object? raw) {
  if (raw is! Map) return null;
  return UserProfile.fromJson(
    Map<String, dynamic>.from(
      raw.map((k, v) => MapEntry(k.toString(), v)),
    ),
  );
}

/// Normalize API maps to [ChatMessage].
ChatMessage? chatMessageFromMap(Object? raw) {
  if (raw is! Map) return null;
  return ChatMessage.fromJson(
    Map<String, dynamic>.from(
      raw.map((k, v) => MapEntry(k.toString(), v)),
    ),
  );
}
