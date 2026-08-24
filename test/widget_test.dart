import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:simplespeedometer/main.dart';

void main() {
  testWidgets('应用启动后显示标题和初始状态', (WidgetTester tester) async {
    await tester.pumpWidget(const SpeedometerApp());

    // 应用栏标题
    expect(find.text('SimpleSpeedometer'), findsOneWidget);

    // 初始状态提示
    expect(find.text('点击“开始测速”开始'), findsOneWidget);

    // 开始测速按钮
    expect(find.text('开始测速'), findsOneWidget);

    // 速度计显示 0.0
    expect(find.text('0.0'), findsOneWidget);
  });

  testWidgets('矮屏（比例不瘦长）上功能按钮无需滚动即可见', (WidgetTester tester) async {
    // 模拟 360x640 的逻辑分辨率（较矮的屏幕）
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const SpeedometerApp());

    // 开始测速按钮存在
    final startButton = find.text('开始测速');
    expect(startButton, findsOneWidget);

    // 按钮底部在屏幕范围内，无需滚动即可见
    final rect = tester.getRect(startButton);
    final screenHeight = tester.view.physicalSize.height;
    expect(rect.bottom, lessThanOrEqualTo(screenHeight),
        reason: '开始按钮应在屏幕内一屏可见，实际底部=${rect.bottom}，屏幕高=$screenHeight');

    // 速度数值也应可见
    final speedRect = tester.getRect(find.text('0.0'));
    expect(speedRect.top, greaterThanOrEqualTo(0));
  });
}
