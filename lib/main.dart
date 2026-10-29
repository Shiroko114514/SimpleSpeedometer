import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  runApp(const SpeedometerApp());
}

/// 深色仪表盘配色：低亮度底色 + 青色强调色，减少夜间读数时的眩光。
abstract final class _AppColors {
  static const Color bgTop = Color(0xFF0A1017);
  static const Color bgBottom = Color(0xFF14202F);
  static const Color card = Color(0x14FFFFFF);
  static const Color border = Color(0x1FFFFFFF);
  static const Color textPrimary = Color(0xFFECF2FF);
  static const Color textMuted = Color(0xFF8395B0);
  static const Color accent = Color(0xFF31E1C4);
  static const Color track = Color(0x1FFFFFFF);
  static const Color arcLow = Color(0xFF31E1C4);
  static const Color arcMid = Color(0xFFFFC857);
  static const Color arcHigh = Color(0xFFFF5470);
}

class SpeedometerApp extends StatelessWidget {
  const SpeedometerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _AppColors.accent,
        brightness: Brightness.dark,
      ).copyWith(
        primary: _AppColors.accent,
        onPrimary: const Color(0xFF04211D),
        surface: _AppColors.bgBottom,
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SimpleSpeedometer',
      theme: base.copyWith(
        scaffoldBackgroundColor: _AppColors.bgTop,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        textTheme: base.textTheme.apply(
          bodyColor: _AppColors.textPrimary,
          displayColor: _AppColors.textPrimary,
        ),
      ),
      home: const SpeedometerPage(),
    );
  }
}

class SpeedometerPage extends StatefulWidget {
  const SpeedometerPage({super.key});

  @override
  State<SpeedometerPage> createState() => _SpeedometerPageState();
}

class _SpeedometerPageState extends State<SpeedometerPage> {
  static const double _maxSpeedKmh = 400;

  /// 用位移推算速度时可接受的定位时间差范围（秒）。
  /// 过小说明是重复/同批数据，过大说明中间断流，两种情况推算都不可信。
  static const double _minDeriveSeconds = 0.1;
  static const double _maxDeriveSeconds = 5.0;

  StreamSubscription<Position>? _positionSubscription;
  Timer? _ticker;
  Timer? _watchdog;
  final Stopwatch _stopwatch = Stopwatch();

  Position? _lastPosition;
  Position? _lastTrackedPosition;
  DateTime? _lastTimestamp;
  DateTime? _lastPositionUpdate;
  bool _isFetchingPosition = false;

  String _statusMessage = '点击“开始测速”开始';
  bool _isTracking = false;
  bool _hasSession = false;
  double _speedMps = 0;
  double _distanceMeters = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _watchdog?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_isTracking) {
        return;
      }
      setState(() {});
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  LocationSettings get _locationSettings {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
      );
    }
    return LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );
  }

  /// 当定位流超过 3 秒没有产生新数据时，主动拉取一次当前位置，
  /// 避免部分设备上定位流只上报一次就不再更新的问题。
  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted || !_isTracking) {
        return;
      }
      final lastUpdate = _lastPositionUpdate;
      if (lastUpdate != null &&
          DateTime.now().difference(lastUpdate) <
              const Duration(seconds: 3)) {
        return;
      }
      await _fetchCurrentPosition();
    });
  }

  void _stopWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
  }

  Future<void> _fetchCurrentPosition() async {
    if (_isFetchingPosition || !_isTracking) {
      return;
    }
    _isFetchingPosition = true;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 3),
        ),
      );
      if (mounted && _isTracking) {
        _onPosition(position);
      }
    } catch (_) {
      // 获取失败（如超时），由后续轮询自动重试
    } finally {
      _isFetchingPosition = false;
    }
  }

  Future<void> _startTracking() async {
    if (_isTracking) {
      return;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _statusMessage = '定位服务未开启，请在系统设置中打开';
        _isTracking = false;
      });
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() {
        _statusMessage = '定位权限被拒绝，请在设置中允许访问位置';
        _isTracking = false;
      });
      return;
    }

    _positionSubscription?.cancel();
    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: _locationSettings)
            .listen(
              _onPosition,
              onError: (Object error) {
                _stopwatch.stop();
                _stopTicker();
                _stopWatchdog();
                _positionSubscription?.cancel();
                _positionSubscription = null;
                setState(() {
                  _statusMessage = '定位数据流错误: $error';
                  _isTracking = false;
                  _speedMps = 0;
                  _lastTimestamp = null;
                  _lastPosition = null;
                  _lastTrackedPosition = null;
                });
              },
            );

    _stopwatch.start();
    _startTicker();
    _startWatchdog();

    setState(() {
      _statusMessage = '测速中...';
      _isTracking = true;
      _hasSession = true;
    });
  }

  Future<void> _pauseTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    _stopwatch.stop();
    _stopTicker();
    _stopWatchdog();

    setState(() {
      _isTracking = false;
      _speedMps = 0;
      _lastTimestamp = null;
      _lastTrackedPosition = null;
      _statusMessage = '测速已暂停';
    });
  }

  Future<void> _endTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    _stopwatch
      ..stop()
      ..reset();
    _stopTicker();
    _stopWatchdog();

    setState(() {
      _isTracking = false;
      _hasSession = false;
      _speedMps = 0;
      _distanceMeters = 0;
      _lastTimestamp = null;
      _lastPosition = null;
      _lastTrackedPosition = null;
      _statusMessage = '点击“开始测速”开始';
    });
  }

  /// 相邻两次定位之间的大圆距离（米）。
  double _stepMeters(Position from, Position to) => Geolocator.distanceBetween(
    from.latitude,
    from.longitude,
    to.latitude,
    to.longitude,
  );

  /// 位移是否仍落在 GPS 噪声范围内。
  ///
  /// `accuracy` 是定位的 68% 置信半径；两次定位间的位移小于该半径时，无法与
  /// 静止时的坐标抖动区分，因此既不能累加距离，也不能用来推算速度。
  /// accuracy 缺失（<=0）时不做过滤，退回原有行为。
  bool _isWithinNoise(Position from, Position to, double stepMeters) {
    final noise = math.max(from.accuracy, to.accuracy);
    return noise > 0 && stepMeters <= noise;
  }

  /// 当前速度（m/s）。
  ///
  /// 优先采用系统给出的 `speed`；当其为 0/NaN/负值（部分设备不提供该字段）时，
  /// 用相邻两次定位的位移除以两次**定位时间戳**之差推算。
  ///
  /// 这里必须用 `position.timestamp` 而非数据到达时间：定位数据可能成批到达，
  /// 到达时间差会趋近于 0，从而把速度放大到几千 km/h 的荒谬量级。
  double _resolveSpeedMps(Position position) {
    final reported = position.speed;
    if (reported.isFinite && reported > 0) {
      return reported;
    }

    final previous = _lastPosition;
    final previousTime = _lastTimestamp;
    if (previous == null || previousTime == null) {
      return 0;
    }

    final dt = position.timestamp.difference(previousTime).inMilliseconds / 1000;
    // 时间差过小（重复或同批数据）或过大（中间断流）时，推算没有意义
    if (dt < _minDeriveSeconds || dt > _maxDeriveSeconds) {
      return 0;
    }

    final step = _stepMeters(previous, position);
    if (_isWithinNoise(previous, position, step)) {
      return 0;
    }
    return step / dt;
  }

  void _onPosition(Position position) {
    _lastPositionUpdate = DateTime.now();

    if (_isTracking) {
      final trackedPrev = _lastTrackedPosition;
      if (trackedPrev != null) {
        final step = _stepMeters(trackedPrev, position);
        // 静止时 GPS 坐标抖动会逐帧累加出虚假里程，进而抬高平均速度
        if (!_isWithinNoise(trackedPrev, position, step)) {
          _distanceMeters += step;
        }
      }
      _lastTrackedPosition = position;
    }

    final speedMps = _resolveSpeedMps(position);

    _lastPosition = position;
    _lastTimestamp = position.timestamp;

    setState(() {
      // 钳制到表盘量程，避免读数超出表盘刻度的最大值
      _speedMps = speedMps.clamp(0.0, _maxSpeedMps);
      _statusMessage = '测速中...';
      _isTracking = true;
    });
  }

  double get _speedKmh => _speedMps * 3.6;

  /// 表盘量程对应的 m/s 上限，用于钳制速度读数
  double get _maxSpeedMps => _maxSpeedKmh / 3.6;

  Duration get _elapsed => _stopwatch.elapsed;

  double get _averageSpeedKmh {
    final seconds = _elapsed.inMilliseconds / 1000;
    if (seconds <= 0) {
      return 0;
    }
    return (_distanceMeters / seconds) * 3.6;
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }
    return '${meters.toStringAsFixed(0)} m';
  }

  // 注意：ButtonStyle.textStyle 会整体替换主题文字样式而非合并，
  // 因此必须显式基于主题样式派生，否则会丢失主题字体族。
  TextStyle _buttonTextStyle(
    BuildContext context, {
    required FontWeight weight,
  }) {
    final base = Theme.of(context).textTheme.labelLarge ?? const TextStyle();
    return base.copyWith(
      fontSize: 15,
      fontWeight: weight,
      letterSpacing: 0.6,
    );
  }

  ButtonStyle _primaryButtonStyle(BuildContext context) =>
      FilledButton.styleFrom(
        backgroundColor: _AppColors.accent,
        foregroundColor: const Color(0xFF04211D),
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: _buttonTextStyle(context, weight: FontWeight.w700),
      );

  ButtonStyle _secondaryButtonStyle(BuildContext context) =>
      OutlinedButton.styleFrom(
        foregroundColor: _AppColors.textPrimary,
        backgroundColor: _AppColors.card,
        side: const BorderSide(color: _AppColors.border),
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: _buttonTextStyle(context, weight: FontWeight.w600),
      );

  Widget _card({required Widget child, required EdgeInsets padding}) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: _AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _AppColors.border),
      ),
      child: child,
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _AppColors.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: 1.2,
            color: _AppColors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _statsCard() {
    return _card(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
      child: Row(
        children: [
          Expanded(child: _stat('时间', _formatDuration(_elapsed))),
          const _StatDivider(),
          Expanded(child: _stat('距离', _formatDistance(_distanceMeters))),
          const _StatDivider(),
          Expanded(
            child: _stat(
              '平均速度',
              '${_averageSpeedKmh.toStringAsFixed(1)} km/h',
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill() {
    final Color color = _isTracking
        ? _AppColors.accent
        : (_hasSession ? _AppColors.arcMid : _AppColors.textMuted);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.9), blurRadius: 9),
              ],
            ),
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              _statusMessage,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _coordinates() {
    final position = _lastPosition;
    final lat = position?.latitude.toStringAsFixed(6) ?? '-';
    final lng = position?.longitude.toStringAsFixed(6) ?? '-';

    return Text(
      'LAT $lat   LNG $lng',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 0.6,
        color: _AppColors.textMuted,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }

  Widget _speedReadout(double speedKmh) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // FittedBox 兜底：极窄屏或超大系统字号下把读数整体等比缩小，避免溢出
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                speedKmh.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 52,
                  height: 1.05,
                  fontWeight: FontWeight.w300,
                  letterSpacing: -1.0,
                  color: _AppColors.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'km/h',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                  color: _AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          '实时速度',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 3.0,
            color: _AppColors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _controls(BuildContext context) {
    if (_isTracking) {
      return SizedBox(
        width: double.infinity,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: _secondaryButtonStyle(context),
                onPressed: _pauseTracking,
                icon: const Icon(Icons.pause_rounded, size: 20),
                label: const Text('暂停测速'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                style: _primaryButtonStyle(context),
                onPressed: _endTracking,
                icon: const Icon(Icons.stop_rounded, size: 20),
                label: const Text('结束测速'),
              ),
            ),
          ],
        ),
      );
    }

    if (_hasSession) {
      return SizedBox(
        width: double.infinity,
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: _primaryButtonStyle(context),
                onPressed: _startTracking,
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('继续测速'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                style: _secondaryButtonStyle(context),
                onPressed: _endTracking,
                icon: const Icon(Icons.stop_rounded, size: 20),
                label: const Text('结束测速'),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: _primaryButtonStyle(context),
        onPressed: _startTracking,
        icon: const Icon(Icons.play_arrow_rounded, size: 20),
        label: const Text('开始测速'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final speedKmh = _speedKmh;

    return Scaffold(
      backgroundColor: _AppColors.bgTop,
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          'SimpleSpeedometer',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 2.8,
            color: _AppColors.textMuted,
          ),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_AppColors.bgTop, _AppColors.bgBottom],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final contentWidth = math.min(constraints.maxWidth, 420.0);
              final viewportHeight = constraints.maxHeight;

              // 表盘以外内容（读数/统计/状态/坐标/按钮及间距）的估算高度，
              // 用于在矮屏上优先压缩表盘，保证功能按钮一屏可见；高屏上限制上限，
              // 避免表盘被拉伸后四周留白过多。
              const double fixedContentHeight = 300.0;
              const double gaugeBlockMinHeight = 168.0;
              const double gaugeBlockMaxHeight = 340.0;
              final gaugeBlockHeight = (viewportHeight - fixedContentHeight)
                  .clamp(gaugeBlockMinHeight, gaugeBlockMaxHeight);

              return SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: contentWidth,
                      minHeight: math.max(0, viewportHeight - 16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            height: gaugeBlockHeight,
                            child: SpeedGauge(
                              speedKmh: speedKmh,
                              maxSpeedKmh: _maxSpeedKmh,
                            ),
                          ),
                          _speedReadout(speedKmh),
                          const SizedBox(height: 14),
                          _statsCard(),
                          const SizedBox(height: 12),
                          _statusPill(),
                          const SizedBox(height: 8),
                          _coordinates(),
                          const SizedBox(height: 14),
                          _controls(context),
                          const SizedBox(height: 6),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: _AppColors.border,
    );
  }
}

class SpeedGauge extends StatelessWidget {
  const SpeedGauge({
    super.key,
    required this.speedKmh,
    required this.maxSpeedKmh,
  });

  final double speedKmh;
  final double maxSpeedKmh;

  @override
  Widget build(BuildContext context) {
    final clampedSpeed = speedKmh.clamp(0.0, maxSpeedKmh);

    return LayoutBuilder(
      builder: (context, constraints) {
        // 直接把可用空间交给画笔：表盘的宽高限制由 _SpeedGaugePainter 内部
        // 按弧形真实比例求解，避免固定宽高比盒子里出现成片无效留白。
        final maxWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 340.0;
        final maxHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 260.0;
        final gaugeSize = Size(maxWidth, maxHeight);

        return Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: clampedSpeed),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            builder: (context, animatedSpeed, _) {
              return SizedBox(
                width: gaugeSize.width,
                height: gaugeSize.height,
                child: ClipRect(
                  child: CustomPaint(
                    size: gaugeSize,
                    painter: _SpeedGaugePainter(
                      speedKmh: animatedSpeed,
                      maxSpeedKmh: maxSpeedKmh,
                      fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _SpeedGaugePainter extends CustomPainter {
  _SpeedGaugePainter({
    required this.speedKmh,
    required this.maxSpeedKmh,
    this.fontFamily,
  });

  final double speedKmh;
  final double maxSpeedKmh;

  /// 刻度文字字体，取主题字体以保证与界面其余文字一致
  final String? fontFamily;

  static const double _startAngle = math.pi * 0.75;
  static const double _sweepAngle = math.pi * 1.5;

  // 非线性刻度：0-160 km/h 展开（占 72% 的弧长），160-400 km/h 压缩（占 28%）
  static const double _breakpointKmh = 160;
  static const double _breakpointFraction = 0.72;

  /// 把速度 km/h 映射到表盘的弧长比例 [0, 1]
  double _speedToFraction(double kmh) {
    final s = kmh.clamp(0.0, maxSpeedKmh);
    if (s <= _breakpointKmh) {
      return (s / _breakpointKmh) * _breakpointFraction;
    }
    return _breakpointFraction +
        ((s - _breakpointKmh) / (maxSpeedKmh - _breakpointKmh)) *
            (1 - _breakpointFraction);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 表盘纵向占用 1.707r（顶端指针刻度到两端弧口的距离）加描边与外发光留白。
    final radius = math.min(
      size.width / 2 - 26,
      math.max(0.0, (size.height - 44) / 1.707),
    );
    final center = Offset(size.width / 2, radius + 22);

    final arcRect = Rect.fromCircle(center: center, radius: radius);
    final value = _speedToFraction(speedKmh);
    final needleAngle = _startAngle + _sweepAngle * value;

    // 轨道弧
    canvas.drawArc(
      arcRect,
      _startAngle,
      _sweepAngle,
      false,
      Paint()
        ..color = _AppColors.track
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.round,
    );

    // 进度弧：渐变 + 外发光
    if (value > 0.004) {
      final gradient = const SweepGradient(
        startAngle: _startAngle,
        endAngle: _startAngle + _sweepAngle,
        colors: [_AppColors.arcLow, _AppColors.arcMid, _AppColors.arcHigh],
        stops: [0.0, 0.62, 1.0],
      ).createShader(arcRect);

      final arcPaint = Paint()
        ..shader = gradient
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        arcRect,
        _startAngle,
        _sweepAngle * value,
        false,
        Paint()
          ..shader = gradient
          ..style = PaintingStyle.stroke
          ..strokeWidth = 18
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
      canvas.drawArc(arcRect, _startAngle, _sweepAngle * value, false, arcPaint);
    }

    // 主刻度：0-160 每 20 km/h（展开、刻度更密），160-400 稀疏
    const List<double> majorTickSpeeds = [
      0, 20, 40, 60, 80, 100, 120, 140, 160, 200, 250, 300, 350, 400,
    ];
    // 次刻度：仅在 0-160 内，每 10 km/h
    const List<double> minorTickSpeeds = [10, 30, 50, 70, 90, 110, 130, 150];

    final minorTickPaint = Paint()
      ..color = const Color(0x2EFFFFFF)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    // 刻度全部画在弧带内侧：弧带占 radius±9，因此刻度从 radius-11 起向内延伸，
    // 避免刻度压在彩色进度弧上形成"划痕"。
    for (final tickSpeed in minorTickSpeeds) {
      final angle = _startAngle + _sweepAngle * _speedToFraction(tickSpeed);
      canvas.drawLine(
        _pointOnCircle(center, radius - 11, angle),
        _pointOnCircle(center, radius - 19, angle),
        minorTickPaint,
      );
    }

    for (final tickSpeed in majorTickSpeeds) {
      final t = _speedToFraction(tickSpeed);
      final angle = _startAngle + _sweepAngle * t;
      final isActive = t <= value;

      canvas.drawLine(
        _pointOnCircle(center, radius - 11, angle),
        _pointOnCircle(center, radius - 26, angle),
        Paint()
          ..color = isActive
              ? _AppColors.textPrimary
              : const Color(0x59FFFFFF)
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round,
      );

      _drawCenteredText(
        canvas,
        tickSpeed.round().toString(),
        _pointOnCircle(center, radius - 39, angle),
        TextStyle(
          color: isActive ? _AppColors.textPrimary : _AppColors.textMuted,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          fontFamily: fontFamily,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    }

    // 指针：从中心轴射出的等腰三角形，根部完全藏在中心轴之下。
    // 不再额外绘制配重尾针——细长的尾针在 11px 轴心外会露出单边尖刺。
    final normal = Offset(-math.sin(needleAngle), math.cos(needleAngle));
    final tip = _pointOnCircle(center, radius - 26, needleAngle);
    const double baseHalfWidth = 5.0;

    final needlePath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        center.dx + normal.dx * baseHalfWidth,
        center.dy + normal.dy * baseHalfWidth,
      )
      ..lineTo(
        center.dx - normal.dx * baseHalfWidth,
        center.dy - normal.dy * baseHalfWidth,
      )
      ..close();

    canvas.drawPath(
      needlePath,
      Paint()
        ..color = _AppColors.accent
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(needlePath, Paint()..color = _AppColors.accent);

    // 中心轴
    canvas.drawCircle(center, 11, Paint()..color = _AppColors.bgBottom);
    canvas.drawCircle(
      center,
      11,
      Paint()
        ..color = _AppColors.accent.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(center, 4.2, Paint()..color = _AppColors.textPrimary);
  }

  Offset _pointOnCircle(Offset center, double radius, double angle) {
    return Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );
  }

  void _drawCenteredText(
    Canvas canvas,
    String text,
    Offset center,
    TextStyle style,
  ) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final offset = Offset(
      center.dx - textPainter.width / 2,
      center.dy - textPainter.height / 2,
    );
    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _SpeedGaugePainter oldDelegate) {
    return oldDelegate.speedKmh != speedKmh ||
        oldDelegate.maxSpeedKmh != maxSpeedKmh ||
        oldDelegate.fontFamily != fontFamily;
  }
}
