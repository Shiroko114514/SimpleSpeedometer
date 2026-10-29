import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:simplespeedometer/main.dart';

/// 可按需投递定位数据的模拟定位平台。
///
/// [getCurrentPosition] 永不返回数据，确保速度变化只来自测试显式投递的定位，
/// 不会被看门狗拉取的兜底位置干扰。
class _MockGeolocatorPlatform extends GeolocatorPlatform {
  final StreamController<Position> controller =
      StreamController<Position>.broadcast();

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.always;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.always;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      controller.stream;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async => throw UnimplementedError('测试中不应调用');
}

Position _position({
  required double latitude,
  required double longitude,
  required double speed,
  required DateTime timestamp,
  double accuracy = 5,
}) {
  return Position(
    longitude: longitude,
    latitude: latitude,
    timestamp: timestamp,
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: speed,
    speedAccuracy: 0,
  );
}

void main() {
  late _MockGeolocatorPlatform mock;

  setUp(() {
    mock = _MockGeolocatorPlatform();
    GeolocatorPlatform.instance = mock;
  });

  tearDown(() {
    final platform = GeolocatorPlatform.instance;
    if (platform is _MockGeolocatorPlatform) {
      platform.controller.close();
    }
  });

  /// 启动测速。直接 tap + pump，使定位订阅与事件投递都落在同一个 fake-async
  /// 环境里；用 runAsync 启动会让订阅跨 zone，投递的事件永远收不到。
  Future<void> start(WidgetTester tester) async {
    await tester.pumpWidget(const SpeedometerApp());
    await tester.tap(find.text('开始测速'));
    await tester.pump();
  }

  /// 投递一条定位并让界面刷新。
  ///
  /// 广播流的投递是微任务，且 setState 可能在当前帧之后才被处理，
  /// 因此需要多泵两次才能让读数反映到已渲染的组件树上。
  Future<void> emit(WidgetTester tester, Position position) async {
    mock.controller.add(position);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('兜底速度按定位时间戳推算，与数据到达快慢无关', (WidgetTester tester) async {
    await start(tester);

    // 两次定位相隔 1 秒、相距约 10 米，系统给出的 speed 为 0（需要兜底推算）。
    // 两条数据在测试里几乎同时到达，若按到达时间算 dt，速度会被放大到荒谬量级。
    final first = DateTime(2024, 1, 1, 12, 0, 0);
    final second = first.add(const Duration(seconds: 1));
    const lat1 = 31.230400;
    const lng1 = 121.473700;
    const lat2 = 31.230490; // 约 10 米

    await emit(
      tester,
      _position(
        latitude: lat1,
        longitude: lng1,
        speed: 0,
        timestamp: first,
      ),
    );
    await emit(
      tester,
      _position(
        latitude: lat2,
        longitude: lng1,
        speed: 0,
        timestamp: second,
      ),
    );

    final meters = Geolocator.distanceBetween(lat1, lng1, lat2, lng1);
    final expectedKmh = (meters / 1.0 * 3.6).toStringAsFixed(1);

    expect(
      find.text(expectedKmh),
      findsOneWidget,
      reason: '应按 1 秒的定位时间差推算速度（$expectedKmh km/h），'
          '而不是按几乎同时的到达时间',
    );
  });

  testWidgets('静止时的定位抖动不会产生虚假速度和距离', (WidgetTester tester) async {
    await start(tester);

    // 静止但 GPS 位置在 ±2 米内漂移，精度 5 米 —— 位移完全在噪声范围内
    final t0 = DateTime(2024, 1, 1, 12, 0, 0);
    const lat = 31.230400;
    const lng = 121.473700;

    for (var i = 0; i < 5; i++) {
      final jitter = (i.isEven ? 1 : -1) * 0.00002; // 约 ±2.2 米
      await emit(
        tester,
        _position(
          latitude: lat + jitter,
          longitude: lng,
          speed: 0,
          timestamp: t0.add(Duration(seconds: i)),
        ),
      );
    }

    expect(
      find.text('0.0'),
      findsOneWidget,
      reason: '抖动幅度低于定位精度时不应推算速度',
    );
    expect(
      find.text('0 m'),
      findsOneWidget,
      reason: '抖动幅度低于定位精度时不应累加距离',
    );
  });

  testWidgets('真实位移超过定位精度时正常累计距离', (WidgetTester tester) async {
    await start(tester);

    // 每次约 33 米，远大于 5 米精度
    final t0 = DateTime(2024, 1, 1, 12, 0, 0);
    const lat = 31.230400;
    const lng = 121.473700;
    const stepLat = 0.0003;

    await emit(
      tester,
      _position(latitude: lat, longitude: lng, speed: 0, timestamp: t0),
    );
    await emit(
      tester,
      _position(
        latitude: lat + stepLat,
        longitude: lng,
        speed: 0,
        timestamp: t0.add(const Duration(seconds: 1)),
      ),
    );
    await emit(
      tester,
      _position(
        latitude: lat + stepLat * 2,
        longitude: lng,
        speed: 0,
        timestamp: t0.add(const Duration(seconds: 2)),
      ),
    );

    final meters = Geolocator.distanceBetween(
      lat,
      lng,
      lat + stepLat * 2,
      lng,
    );
    final expected = '${meters.toStringAsFixed(0)} m';

    expect(
      find.text(expected),
      findsOneWidget,
      reason: '两段真实位移都应累加，合计约 $expected',
    );
  });

  testWidgets('速度读数不超过表盘量程', (WidgetTester tester) async {
    await start(tester);

    // 系统给出的速度远超表盘上限 400 km/h（500 m/s = 1800 km/h）
    await emit(
      tester,
      _position(
        latitude: 31.230400,
        longitude: 121.473700,
        speed: 500,
        timestamp: DateTime(2024, 1, 1, 12, 0, 0),
      ),
    );

    expect(
      find.text('400.0'),
      findsOneWidget,
      reason: '读数应钳制到表盘量程 400 km/h，与表盘保持一致',
    );
    expect(find.text('1800.0'), findsNothing);
  });
}
