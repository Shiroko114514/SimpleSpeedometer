import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

import 'package:simplespeedometer/main.dart';

/// 最小化的定位 mock：权限放行；每次订阅返回全新、保持打开但不产生数据的流。
class _MockGeolocatorPlatform extends GeolocatorPlatform {
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
    return StreamController<Position>().stream;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    return Position(
      longitude: 121.4737,
      latitude: 31.2304,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}

void main() {
  testWidgets('暂停测速后显示“继续测速”和“结束测速”两个按钮', (WidgetTester tester) async {
    final original = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = _MockGeolocatorPlatform();
    addTearDown(() => GeolocatorPlatform.instance = original);

    await tester.pumpWidget(const SpeedometerApp());

    // 初始只有“开始测速”
    expect(find.text('开始测速'), findsOneWidget);
    expect(find.text('暂停测速'), findsNothing);
    expect(find.text('继续测速'), findsNothing);

    Future<void> press(String label) async {
      final button = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text(label),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      // onPressed 实际返回 Future<void>，转型后在真实异步环境中等待完成
      final handler = button.onPressed! as Future<void> Function();
      await tester.runAsync(() => handler());
      await tester.pump();
    }

    // 开始 → 暂停测速 + 结束测速
    await press('开始测速');
    expect(find.text('暂停测速'), findsOneWidget);
    expect(find.text('结束测速'), findsOneWidget);

    // 暂停 → 保留 继续测速 + 结束测速（核心需求）
    await press('暂停测速');
    expect(find.text('继续测速'), findsOneWidget);
    expect(find.text('结束测速'), findsOneWidget);
    expect(find.text('开始测速'), findsNothing);

    // 继续 → 回到 暂停测速 + 结束测速
    await press('继续测速');
    expect(find.text('暂停测速'), findsOneWidget);
    expect(find.text('结束测速'), findsOneWidget);

    // 结束 → 回到 开始测速
    await press('结束测速');
    expect(find.text('开始测速'), findsOneWidget);
    expect(find.text('继续测速'), findsNothing);
    expect(find.text('暂停测速'), findsNothing);
  });
}
