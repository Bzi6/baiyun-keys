import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/lock_config.dart';
import 'lock_protocol.dart';
/// 蓝牙开锁服务
class BleService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;
  StreamSubscription<List<int>>? _notifySubscription;
  final StreamController<String> _logController = StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;
  void _log(String msg) {
    _logController.add(msg);
  }
  /// 扫描并连接设备
  Future<bool> connectToDevice(LockConfig config, {Duration timeout = const Duration(seconds: 10)}) async {
    try {
      _log('开始扫描蓝牙设备...');
      // 先停止之前的扫描
      await FlutterBluePlus.stopScan();
      // 扫描设备（startScan 1.18.2+ 返回 void）
      FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: true,
      );
      // 等待扫描结果
      await Future.delayed(const Duration(seconds: 3));
      // 停止扫描
      await FlutterBluePlus.stopScan();
      // 从 Stream 获取扫描结果列表
      final scanResults = await FlutterBluePlus.scanResults.first;
      // 查找目标设备
      BluetoothDevice? targetDevice;
      final targetName = LockProtocol.normalizeBluetoothName(config.bluetoothName);
      final derivedName = LockProtocol.deriveBluetoothNameFromMac(config.mac);
      for (final result in scanResults) {
        final deviceName = result.device.platformName.toUpperCase();
        final advName = result.advertisementData.advName.toUpperCase();
        // 按蓝牙名称匹配
        if (targetName.isNotEmpty && (deviceName.contains(targetName) || advName.contains(targetName))) {
          targetDevice = result.device;
          _log('找到设备（按名称）: ${result.device.platformName}');
          break;
        }
        // 按推导名称匹配
        if (derivedName.isNotEmpty && (deviceName.contains(derivedName) || advName.contains(derivedName))) {
          targetDevice = result.device;
          _log('找到设备（按推导名称）: ${result.device.platformName}');
          break;
        }
      }
      if (targetDevice == null) {
        _log('未找到目标设备，请确认设备已开启且在附近');
        return false;
      }
      _device = targetDevice;
      _log('正在连接设备: ${targetDevice.platformName}');
      // 连接设备
      await targetDevice.connect(timeout: timeout);
      _log('设备连接成功');
      // 发现服务
      _log('正在发现服务...');
      final services = await targetDevice.discoverServices();
      for (final service in services) {
        for (final char in service.characteristics) {
          // 查找可写特征值
          if (char.properties.write || char.properties.writeWithoutResponse) {
            _writeChar = char;
            _log('找到写入特征值: ${char.uuid}');
          }
          // 查找可通知特征值
          if (char.properties.notify || char.properties.indicate) {
            _notifyChar = char;
            _log('找到通知特征值: ${char.uuid}');
          }
        }
      }
      if (_writeChar == null) {
        _log('未找到可写入的蓝牙特征值');
        return false;
      }
      // 启用通知
      if (_notifyChar != null) {
        await _notifyChar!.setNotifyValue(true);
        _notifySubscription = _notifyChar!.lastValueStream.listen((data) {
          _handleNotification(Uint8List.fromList(data), config);
        });
        _log('已启用通知监听');
      }
      return true;
    } catch (e) {
      _log('连接失败: $e');
      return false;
    }
  }
  /// 处理通知数据
  void _handleNotification(Uint8List data, LockConfig config) {
    final hex = LockProtocol.bytesToHex(data);
    _log('收到数据: $hex');
    // 解析开锁结果
    if (hex.length >= 36) {
      final result = LockProtocol.decodeOpenResult(hex, config.productKey);
      _log('开锁结果: ${result['message']}');
    }
  }
  /// 执行完整开锁流程
  Future<String> unlock(LockConfig config) async {
    try {
      if (_device == null || _writeChar == null) {
        return '设备未连接';
      }
      // 1. 生成随机数
      final random = _generateRandomBytes(4);
      _log('生成随机数: ${LockProtocol.bytesToHex(random)}');
      // 2. 发送握手指令
      _log('发送握手指令...');
      final handshakeCmd = LockProtocol.buildHandshakeCommand(
        random,
        config.bluetoothName,
        config.productKey,
      );
      await _writeData(handshakeCmd);
      await Future.delayed(const Duration(milliseconds: 500));
      // 3. 发送通信密钥指令
      _log('发送通信密钥指令...');
      final derivedName = LockProtocol.deriveBluetoothNameFromMac(config.mac);
      final commKeyCmd = LockProtocol.buildCommKeyCommand(
        random,
        derivedName.isNotEmpty ? derivedName : config.bluetoothName,
        config.productKey,
      );
      await _writeData(commKeyCmd);
      await Future.delayed(const Duration(milliseconds: 500));
      // 4. 时间同步
      _log('发送时间同步指令...');
      final timeHex = LockProtocol.generateTimeHex();
      final timeBytes = LockProtocol.hexToBytes(timeHex);
      final timeSyncCmd = LockProtocol.buildTimeSyncCommand(
        timeBytes,
        derivedName.isNotEmpty ? derivedName : config.bluetoothName,
        config.productKey, // 这里应该用 sessionKey，但简化处理先用 productKey
      );
      await _writeData(timeSyncCmd);
      await Future.delayed(const Duration(milliseconds: 500));
      // 5. 发送开锁指令
      _log('发送开锁指令...');
      final unlockKey = config.unlockKey ?? config.productKey;
      final unlockCmd = LockProtocol.encryptUnlockCommand(
        random,
        config.mac,
        unlockKey,
      );
      await _writeData(unlockCmd);
      // 等待回执
      await Future.delayed(const Duration(seconds: 2));
      _log('开锁指令已发送');
      return '开锁指令已发送';
    } catch (e) {
      _log('开锁失败: $e');
      return '开锁失败: $e';
    }
  }
  /// 写入数据
  Future<void> _writeData(Uint8List data) async {
    if (_writeChar == null) return;
    _log('发送: ${LockProtocol.bytesToHex(data)}');
    await _writeChar!.write(data.toList(), withoutResponse: true);
  }
  /// 生成随机字节
  Uint8List _generateRandomBytes(int length) {
    final random = Uint8List(length);
    for (var i = 0; i < length; i++) {
      random[i] = DateTime.now().microsecondsSinceEpoch % 256;
      // 简单的伪随机
    }
    return random;
  }
  /// 断开连接
  Future<void> disconnect() async {
    await _notifySubscription?.cancel();
    _notifySubscription = null;
    if (_device != null) {
      await _device!.disconnect();
      _log('设备已断开');
    }
    _device = null;
    _writeChar = null;
    _notifyChar = null;
  }
  /// 释放资源
  void dispose() {
    _logController.close();
    disconnect();
  }
}
