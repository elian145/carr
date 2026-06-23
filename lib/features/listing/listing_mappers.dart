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
