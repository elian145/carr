/// Authenticated user profile from API `/api/users/me` and auth responses.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    this.email,
    this.phone,
    this.firstName,
    this.lastName,
    this.isVerified = false,
    this.isAdmin = false,
    this.accountType,
    this.dealerName,
    this.raw = const {},
  });

  final String id;
  final String username;
  final String? email;
  final String? phone;
  final String? firstName;
  final String? lastName;
  final bool isVerified;
  final bool isAdmin;
  final String? accountType;
  final String? dealerName;
  final Map<String, dynamic> raw;

  String get displayName {
    final parts = [firstName, lastName]
        .where((s) => s != null && s.trim().isNotEmpty)
        .map((s) => s!.trim())
        .toList();
    if (parts.isNotEmpty) return parts.join(' ');
    return username;
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    return UserProfile(
      id: id?.toString() ?? '',
      username: (json['username'] ?? '').toString(),
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      firstName: json['first_name']?.toString(),
      lastName: json['last_name']?.toString(),
      isVerified: json['is_verified'] == true,
      isAdmin: json['is_admin'] == true,
      accountType: json['account_type']?.toString(),
      dealerName: json['dealer_name']?.toString(),
      raw: Map<String, dynamic>.from(json),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    if (email != null) 'email': email,
    if (phone != null) 'phone': phone,
    if (firstName != null) 'first_name': firstName,
    if (lastName != null) 'last_name': lastName,
    'is_verified': isVerified,
    'is_admin': isAdmin,
    if (accountType != null) 'account_type': accountType,
    if (dealerName != null) 'dealer_name': dealerName,
  };
}
