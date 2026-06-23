import '../../../models/chat_message.dart';
import '../../../models/listing.dart';
import '../../../models/user_profile.dart';

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
