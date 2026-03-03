class CarModel {
  const CarModel({
    required this.id,
    required this.name,
    required this.brandId,
  });

  final String id;
  final String name;
  final String brandId;

  factory CarModel.fromJson(Map<String, dynamic> json) {
    return CarModel(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      brandId: (json['brandId'] ?? json['brand_id'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'brandId': brandId};
}

