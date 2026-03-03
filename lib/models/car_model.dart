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
      id: json['id'] as String,
      name: json['name'] as String,
      brandId: json['brandId'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'brandId': brandId,
    };
  }
}
