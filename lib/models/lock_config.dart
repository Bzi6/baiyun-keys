/// 门禁配置模型
class LockConfig {
  String doorName;
  String mac;
  String bluetoothName;
  String productKey;
  String? unlockKey;

  LockConfig({
    required this.doorName,
    required this.mac,
    required this.bluetoothName,
    required this.productKey,
    this.unlockKey,
  });

  Map<String, dynamic> toJson() => {
        'doorName': doorName,
        'mac': mac,
        'bluetoothName': bluetoothName,
        'productKey': productKey,
        'unlockKey': unlockKey,
      };

  factory LockConfig.fromJson(Map<String, dynamic> json) => LockConfig(
        doorName: json['doorName'] ?? '',
        mac: json['mac'] ?? '',
        bluetoothName: json['bluetoothName'] ?? '',
        productKey: json['productKey'] ?? '',
        unlockKey: json['unlockKey'],
      );
}
