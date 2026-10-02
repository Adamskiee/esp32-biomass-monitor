class Device {
  Device(this.id, this.name, this.ipAddress, this.macAddress);

  final String id;
  String name;
  String ipAddress;
  String macAddress;

  factory Device.fromJson(Map<String, dynamic> json) => Device(
    json['id'] as String,
    json['name'] as String,
    json['ipAddress'] as String,
    json['macAddress'] as String,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'ipAddress': ipAddress,
    'macAddress': macAddress,
  };
}
