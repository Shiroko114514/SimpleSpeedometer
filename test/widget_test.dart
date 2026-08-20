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
}
