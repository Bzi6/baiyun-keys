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
  BluetoothCharacteristic? _readChar;
  StreamSubscription<List<int>>? _notifySubscription;
  final StreamController<String> _logController = StreamController<String>.broadcast();
  Stream<String> get logStream => _logController.stream;
  Completer<String>? _unlockResult;

  void _log(String msg) {
    _logController.add(msg);
  }

  /// 扫描并连接设备
  Future<bool> connectToDevice(LockConfig config, {Duration timeout = const Duration(seconds: 10)}) async {
    try {
      _log('开始扫描蓝牙设备...');
      await FlutterBluePlus.stopScan();
      FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: true,
      );
      await Future.delayed(const Duration(seconds: 3));
      await FlutterBluePlus.stopScan();
      final scanResults = await FlutterBluePlus.scanResults.first;

      BluetoothDevice? targetDevice;
      final targetName = LockProtocol.normalizeBluetoothName(config.bluetoothName);
      final derivedName = LockProtocol.deriveBluetoothNameFromMac(config.mac);
      for (final result in scanResults) {
        final deviceName = result.device.platformName.toUpperCase();
        final advName = result.advertisementData.advName.toUpperCase();
        if (targetName.isNotEmpty && (deviceName.contains(targetName) || advName.contains(targetName))) {
          targetDevice = result.device;
          _log('找到设备（按名称）: ${result.device.platformName}');
          break;
        }
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
      await targetDevice.connect(timeout: timeout);
      _log('设备连接成功');

      _log('正在发现服务...');
      final services = await targetDevice.discoverServices();
      for (final service in services) {
        for (final char in service.characteristics) {
          if (char.properties.write || char.properties.writeWithoutResponse) {
            _writeChar = char;
            _log('找到写入特征值: ${char.uuid}');
          }
          if (char.properties.notify || char.properties.indicate) {
            _notifyChar = char;
            _log('找到通知特征值: ${char.uuid}');
          }
          if (char.properties.read) {
            _readChar = char;
            _log('找到读取特征值: ${char.uuid}');
          }
        }
      }

      if (_writeChar == null) {
        _log('未找到可写入的蓝牙特征值');
        return false;
      }
      if (_readChar == null) {
        _log('未找到可读取的蓝牙特征值');
        return false;
      }

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

    if (hex.length < 6) return;
    final command = hex.substring(4, 6).toUpperCase();

    // 忽略写入回显 (command=05，与发送的数据相同)
    if (command == '05') {
      _log('忽略写入回显，等待设备真正回执...');
      return;
    }

    // 握手指令回执 (command=04)
    if (command == '04') {
      final isSuccess = hex.length > 24;
      if (isSuccess) {
        _log('握手成功，门锁已执行开锁');
        _completeUnlock('握手成功，门锁已开启');
      } else {
        final statusField = hex.length >= 18 ? hex.substring(14, 18) : '';
        _log('握手失败，设备返回码: $statusField');
        _completeUnlock('握手失败，密码无效');
      }
      return;
    }

    // 其他类型通知（如开锁结果）
    if (hex.length >= 36) {
      final result = LockProtocol.decodeOpenResult(hex, config.productKey);
      _log('开锁结果: ${result['message']}');
      _completeUnlock(result['message'] ?? '未知结果');
    }
  }

  void _completeUnlock(String result) {
    if (_unlockResult != null && !_unlockResult!.isCompleted) {
      _unlockResult!.complete(result);
    }
  }

  /// 执行完整开锁流程（与小程序版一致：读随机数 → 发握手指令 → 等回执）
  Future<String> unlock(LockConfig config) async {
    try {
      if (_device == null || _writeChar == null || _readChar == null) {
        return '设备未连接';
      }

      // 1. 从设备读取随机数（4字节）
      _log('正在读取设备随机数...');
      final seed = await _readChar!.read();
      final seedBytes = Uint8List.fromList(seed);
      _log('随机数: ${LockProtocol.bytesToHex(seedBytes)}');

      // 2. 用 MAC 后 4 字节构建握手指令
      _log('发送握手指令...');
      final handshakeCmd = LockProtocol.buildHandshakeCommandWithMac(
        seedBytes,
        config.mac,
        config.productKey,
      );
      _log('发送: ${LockProtocol.bytesToHex(handshakeCmd)}');

      // 3. 发送握手指令（write with response，与小程序版一致）
      _unlockResult = Completer<String>();
      await _writeData(handshakeCmd);

      // 4. 等待设备回执（超时 8 秒，给设备足够响应时间）
      final result = await _unlockResult!.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => '等待门锁响应超时',
      );
      _log('开锁流程结束: $result');
      return result;
    } catch (e) {
      _log('开锁失败: $e');
      return '开锁失败: $e';
    }
  }

  /// 写入数据（write with response，与小程序版一致）
  Future<void> _writeData(Uint8List data) async {
    if (_writeChar == null) return;
    await _writeChar!.write(data.toList(), withoutResponse: false);
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
    _readChar = null;
    _unlockResult = null;
  }

  /// 释放资源
  void dispose() {
    _logController.close();
    disconnect();
  }
}
