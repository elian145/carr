class Trim {
  const Trim({
    required this.id,
    required this.name,
    required this.modelId,
  });

  final String id;
  final String name;
  final String modelId;

  factory Trim.fromJson(Map<String, dynamic> json) {
    return Trim(
      id: json['id'] as String,
      name: json['name'] as String,
      modelId: json['modelId'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'modelId': modelId,
    };
  }
}
