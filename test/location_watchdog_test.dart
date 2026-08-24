import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

import 'package:simplespeedometer/main.dart';

/// 复现"定位流不再产生数据"的模拟定位平台。
///
/// - [getPositionStream] 不产生任何位置数据（`_lastPositionUpdate` 保持为空）
/// - [getCurrentPosition] 由看门狗调用，返回一个 speed=36 m/s（129.6 km/h）
///   的"行驶中"位置，用于验证看门狗会持续主动拉取并刷新速度
class _MockGeolocatorPlatform extends GeolocatorPlatform {
  int currentPositionCalls = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.always;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.always;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    return const Stream<Position>.empty();
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    currentPositionCalls++;
    return Position(
      longitude: 121.4737,
      latitude: 31.2304,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 36, // 36 m/s = 129.6 km/h
      speedAccuracy: 1,
    );
  }
}

void main() {
  testWidgets('定位流无数据时，看门狗会持续拉取并刷新速度', (WidgetTester tester) async {
    final original = GeolocatorPlatform.instance;
    final mock = _MockGeolocatorPlatform();
    GeolocatorPlatform.instance = mock;
    addTearDown(() => GeolocatorPlatform.instance = original);

    await tester.pumpWidget(const SpeedometerApp());

    // 点击“开始测速”
    await tester.tap(find.text('开始测速'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 定位流无数据，此时尚未触发主动拉取，速度显示 0.0
    expect(find.text('0.0'), findsOneWidget);
    expect(mock.currentPositionCalls, 0);

    // 让看门狗（周期 1s）运行 2 秒：
    // 因为定位流一直没有数据，看门狗每个周期都会主动 getCurrentPosition 拉取
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(mock.currentPositionCalls, greaterThan(0),
        reason: '定位流无数据时看门狗应主动拉取当前位置');
    expect(find.text('129.6'), findsOneWidget,
        reason: '看门狗拉取到 36 m/s 的位置后，速度应刷新为 129.6 km/h');

    // 状态应保持"测速中"
    expect(find.text('测速中...'), findsOneWidget);
  });
}
