# SimpleSpeedometer

一个使用 Flutter 编写的多平台实时速度计应用。应用通过设备 GPS 获取定位数据，显示当前速度，并记录测速过程中的时间、距离和平均速度。

## 功能

- 实时显示速度，单位为 km/h
- 仪表盘显示速度刻度、渐变区间和指针
- 记录测速时长、行驶距离和平均速度
- 支持暂停、继续和结束测速
- 显示当前 GPS 坐标
- 支持 Android、iOS、macOS、Linux、Windows 和 Web 等 Flutter 平台

## 环境要求

- Flutter 3.41.3
- Dart 3.11.1
- Android 构建需要 Android SDK 和 Java 17 或更高版本

## 本地运行

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

首次使用时，需要允许应用访问设备位置。模拟器或没有 GPS 的设备可能无法提供有效速度。

## 构建 Android APK

构建通用 release APK：

```bash
flutter build apk --release
```

构建按 CPU 架构拆分的 APK：

```bash
flutter build apk --release --split-per-abi
```

构建产物位于 `build/app/outputs/flutter-apk/`。大多数现代 Android 手机使用 `app-arm64-v8a-release.apk`。

## GitHub Actions

推送 `v*` 格式的 tag（例如 `v1.0.0`）或在 GitHub Actions 页面手动运行 `Build APK & Publish Release`，工作流会自动构建 universal APK 和 split-per-abi APK，并发布到 GitHub Release。

Release 签名需要在仓库的 Actions secrets 中配置：

- `ANDROID_KEYSTORE_BASE64`
- `KEYSTORE_PASSWORD`
- `KEY_PASSWORD`

## 权限与隐私

本应用需要位置权限来计算实时速度、距离和平均速度。定位数据仅用于应用内测速功能，具体行为仍取决于运行平台和系统权限设置。

## 开源协议

本项目采用 [MIT License](LICENSE) 开源。你可以自由使用、复制、修改和分发本项目，但须保留原始版权和许可声明。