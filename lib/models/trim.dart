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
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      modelId: (json['modelId'] ?? json['model_id'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'modelId': modelId};
}

