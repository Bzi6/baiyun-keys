# 包子的key - Flutter 蓝牙门禁 App

## 项目简介

基于 Flutter 开发的蓝牙门禁管理 App，支持扫描蓝牙设备、连接门禁、发送加密开锁指令。

核心功能：
- 蓝牙设备扫描与连接
- DES 加密通信协议
- 多门禁配置管理
- 一键开锁

## 项目结构

```
lib/
├── main.dart                    # 主入口
├── models/
│   └── lock_config.dart         # 门禁配置模型
├── services/
│   ├── des_service.dart         # DES 加密服务
│   ├── lock_protocol.dart       # 蓝牙协议（握手/密钥/时间同步/开锁）
│   └── ble_service.dart         # 蓝牙服务（扫描/连接/通信）
└── screens/
    ├── home_screen.dart         # 首页（门禁列表+开锁）
    └── config_screen.dart       # 配置页（添加/编辑门禁）
```

## 环境要求

- Flutter SDK >= 3.0.0
- Dart SDK >= 3.0.0
- Android Studio（安卓开发）
- Xcode（iOS 开发，需要 Mac）
- 苹果开发者账号（打包 IPA）

## 安装步骤

### 1. 安装 Flutter SDK

Windows:
1. 下载 Flutter SDK: https://docs.flutter.dev/get-started/install/windows
2. 解压到 `C:\src\flutter`
3. 添加到系统 PATH: `C:\src\flutter\bin`
4. 运行 `flutter doctor` 检查依赖

### 2. 安装依赖

```bash
cd baiyun_keys_flutter
flutter pub get
```

### 3. 运行安卓版

```bash
flutter run
```

### 4. 构建安卓 APK

```bash
flutter build apk --release
```

输出路径: `build/app/outputs/flutter-apk/app-release.apk`

## 打包 iOS IPA

### 方式一：Mac + Xcode（推荐）

1. 将项目拷贝到 Mac
2. 安装 CocoaPods:
   ```bash
   sudo gem install cocoapods
   cd ios
   pod install
   ```
3. 用 Xcode 打开 `ios/Runner.xcworkspace`
4. 配置签名（Team + Bundle ID）
5. 菜单: Product → Archive
6. 导出 IPA

### 方式二：云构建（Codemagic / Appcircle）

无需 Mac，在 Windows 上也能打包 iOS：

1. 注册 Codemagic: https://codemagic.io
2. 连接 GitHub 仓库（或上传项目 zip）
3. 配置构建流程：
   - Flutter 版本: stable
   - 构建命令: `flutter build ipa --release`
4. 上传苹果开发者证书（.p12 + .mobileprovision）
5. 触发构建，下载 IPA

### 方式三：GitHub Actions

在项目根目录创建 `.github/workflows/ios.yml`：

```yaml
name: iOS Build
on: [push]
jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'
      - run: flutter pub get
      - run: cd ios && pod install
      - run: flutter build ipa --release --no-codesign
      - uses: actions/upload-artifact@v3
        with:
          name: ios-app
          path: build/ios/ipa/*.ipa
```

## 蓝牙协议说明

开锁流程：
1. **握手** - 发送随机数 + 设备ID，用 Product Key 加密
2. **获取通信密钥** - 用 Product Key 加密随机数，获取会话密钥
3. **时间同步** - 用会话密钥加密当前时间
4. **开锁** - 用开锁密钥加密种子，发送开锁指令
5. **解析结果** - 解密回执，判断是否成功

加密算法: DES (ECB 模式，无填充)

## 配置说明

添加门禁时需要填写：
- **门禁名称**: 自定义名称
- **MAC 地址**: 门禁设备蓝牙 MAC (AA:BB:CC:DD:EE:FF)
- **蓝牙名称**: 设备广播名称 (可由 MAC 自动推导)
- **产品密钥**: 16位十六进制加密密钥
- **开锁密钥**: 可选，与产品密钥相同可留空

## 注意事项

1. iOS 13+ 需要蓝牙权限，已在 Info.plist 配置
2. 安卓 6.0+ 需要位置权限才能扫描蓝牙
3. 首次使用需要授权蓝牙和位置权限
4. 确保门禁设备已开启且在蓝牙范围内
5. 开锁过程中保持手机与设备连接

## 常见问题

**Q: 扫描不到设备？**
A: 检查蓝牙是否开启、位置权限是否授权、设备是否在范围内。

**Q: 连接失败？**
A: 确保设备未被其他 App 连接，重启蓝牙后重试。

**Q: 开锁失败？**
A: 检查 Product Key 和 MAC 地址是否正确，确认设备支持该协议。
