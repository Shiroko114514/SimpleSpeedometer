import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  runApp(const SpeedometerApp());
}

class SpeedometerApp extends StatelessWidget {
  const SpeedometerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SimpleSpeedometer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
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
  static const double _maxSpeedKmh = 180;

  StreamSubscription<Position>? _positionSubscription;
  Timer? _ticker;
  final Stopwatch _stopwatch = Stopwatch();

  Position? _lastPosition;
  Position? _lastTrackedPosition;
  DateTime? _lastTimestamp;

  String _statusMessage = '点击“开始测速”开始';
  bool _isTracking = false;
  double _speedMps = 0;
  double _distanceMeters = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _ticker?.cancel();
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

  Future<void> _startTracking() async {
    if (_isTracking) {
      return;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _statusMessage = 'Location service is disabled';
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
        _statusMessage = 'Location permission denied';
        _isTracking = false;
      });
      return;
    }

    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
    );

    _positionSubscription?.cancel();
    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: settings).listen(
          _onPosition,
          onError: (Object error) {
            setState(() {
              _statusMessage = 'Location stream error: $error';
              _isTracking = false;
            });
            _stopwatch.stop();
            _stopTicker();
            _speedMps = 0;
            _lastTrackedPosition = null;
            _positionSubscription?.cancel();
            _positionSubscription = null;
          },
        );

    _stopwatch.start();
    _startTicker();

    setState(() {
      _statusMessage = '测速中...';
      _isTracking = true;
    });
  }

  Future<void> _pauseTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    _stopwatch.stop();
    _stopTicker();

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

    setState(() {
      _isTracking = false;
      _speedMps = 0;
      _distanceMeters = 0;
      _lastTimestamp = null;
      _lastPosition = null;
      _lastTrackedPosition = null;
      _statusMessage = '点击“开始测速”开始';
    });
  }

  void _onPosition(Position position) {
    if (_isTracking) {
      final trackedPrev = _lastTrackedPosition;
      if (trackedPrev != null) {
        _distanceMeters += Geolocator.distanceBetween(
          trackedPrev.latitude,
          trackedPrev.longitude,
          position.latitude,
          position.longitude,
        );
      }
      _lastTrackedPosition = position;
    }

    double speedMps = position.speed;

    if (speedMps.isNaN || speedMps.isNegative || speedMps == 0) {
      final prev = _lastPosition;
      final prevTime = _lastTimestamp;
      if (prev != null && prevTime != null) {
        final now = DateTime.now();
        final dt = now.difference(prevTime).inMilliseconds / 1000;
        if (dt > 0) {
          final distance = Geolocator.distanceBetween(
            prev.latitude,
            prev.longitude,
            position.latitude,
            position.longitude,
          );
          speedMps = distance / dt;
        }
        _lastTimestamp = now;
      } else {
        _lastTimestamp = DateTime.now();
      }
    } else {
      _lastTimestamp = DateTime.now();
    }

    _lastPosition = position;

    setState(() {
      _speedMps = speedMps.clamp(0, 999);
      _statusMessage = '测速中...';
      _isTracking = true;
    });
  }

  double get _speedKmh => _speedMps * 3.6;

  Duration get _elapsed => _stopwatch.elapsed;

  double get _averageSpeedKmh {
    final seconds = _elapsed.inMilliseconds / 1000;
    if (seconds <= 0) {
      return 0;
    }
    return (_distanceMeters / seconds) * 3.6;
  }

  bool get _hasSessionData => _distanceMeters > 0 || _elapsed.inSeconds > 0;

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

  Widget _metricRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const Spacer(),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final speedKmh = _speedKmh;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('SimpleSpeedometer')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final contentWidth = math.min(constraints.maxWidth, 420.0);

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: contentWidth,
                    minHeight: math.max(0, constraints.maxHeight - 56),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 20),
                        SpeedGauge(
                          speedKmh: speedKmh,
                          maxSpeedKmh: _maxSpeedKmh,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          speedKmh.toStringAsFixed(1),
                          style: Theme.of(context).textTheme.displayMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '实时速度 (km/h)',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 28),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            children: [
                              _metricRow(
                                context,
                                '时间',
                                _formatDuration(_elapsed),
                              ),
                              _metricRow(
                                context,
                                '距离',
                                _formatDistance(_distanceMeters),
                              ),
                              _metricRow(
                                context,
                                '平均速度',
                                '${_averageSpeedKmh.toStringAsFixed(1)} km/h',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            _statusMessage,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            'Lat: ${_lastPosition?.latitude.toStringAsFixed(6) ?? '-'}  '
                            'Lng: ${_lastPosition?.longitude.toStringAsFixed(6) ?? '-'}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(height: 44),
                        if (_isTracking)
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                  ),
                                  onPressed: _pauseTracking,
                                  icon: const Icon(Icons.pause_circle),
                                  label: const Text('暂停测速'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                  ),
                                  onPressed: _endTracking,
                                  icon: const Icon(Icons.stop_circle),
                                  label: const Text('结束测速'),
                                ),
                              ),
                            ],
                          )
                        else if (_hasSessionData)
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                  ),
                                  onPressed: _startTracking,
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('继续测速'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                  ),
                                  onPressed: _endTracking,
                                  icon: const Icon(Icons.stop_circle),
                                  label: const Text('结束测速'),
                                ),
                              ),
                            ],
                          )
                        else
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                              onPressed: _startTracking,
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('开始测速'),
                            ),
                          ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
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

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: clampedSpeed),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (context, animatedSpeed, _) {
        const gaugeSize = Size(340, 260);

        return SizedBox(
          width: gaugeSize.width,
          height: gaugeSize.height,
          child: ClipRect(
            child: CustomPaint(
              size: gaugeSize,
              painter: _SpeedGaugePainter(
                speedKmh: animatedSpeed,
                maxSpeedKmh: maxSpeedKmh,
                colorScheme: Theme.of(context).colorScheme,
              ),
            ),
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
    required this.colorScheme,
  });

  final double speedKmh;
  final double maxSpeedKmh;
  final ColorScheme colorScheme;

  static const double _startAngle = math.pi * 0.75;
  static const double _sweepAngle = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.58);
    final radius = math.min(size.width / 2 - 20, size.height * 0.46);

    final arcRect = Rect.fromCircle(center: center, radius: radius);
    final value = (speedKmh / maxSpeedKmh).clamp(0.0, 1.0);
    final needleAngle = _startAngle + _sweepAngle * value;

    final baseArcPaint = Paint()
      ..color = colorScheme.surfaceContainerHighest
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;

    final activeArcPaint = Paint()
      ..shader = SweepGradient(
        startAngle: _startAngle,
        endAngle: _startAngle + _sweepAngle,
        colors: const [Color(0xFF2E7D32), Color(0xFFF9A825), Color(0xFFC62828)],
      ).createShader(arcRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(arcRect, _startAngle, _sweepAngle, false, baseArcPaint);
    canvas.drawArc(
      arcRect,
      _startAngle,
      _sweepAngle * value,
      false,
      activeArcPaint,
    );

    final majorTickPaint = Paint()
      ..color = colorScheme.onSurface.withValues(alpha: 0.7)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    final majorTickActivePaint = Paint()
      ..color = colorScheme.onSurface
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    final minorTickPaint = Paint()
      ..color = colorScheme.onSurface.withValues(alpha: 0.38)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    const int majorTicks = 9;
    const int minorBetween = 4;

    for (int i = 0; i <= majorTicks; i++) {
      final t = i / majorTicks;
      final angle = _startAngle + _sweepAngle * t;
      final isActiveTick = t <= value;

      final pOuter = _pointOnCircle(center, radius + 2, angle);
      final pInner = _pointOnCircle(center, radius - 16, angle);
      canvas.drawLine(
        pOuter,
        pInner,
        isActiveTick ? majorTickActivePaint : majorTickPaint,
      );

      final labelSpeed = (maxSpeedKmh * t).round();
      final labelOffset = _pointOnCircle(center, radius - 34, angle);
      _drawCenteredText(
        canvas,
        labelSpeed.toString(),
        labelOffset,
        TextStyle(
          color: colorScheme.onSurface.withValues(alpha: 0.8),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      );

      if (i == majorTicks) {
        continue;
      }

      for (int j = 1; j <= minorBetween; j++) {
        final subT = (i + j / (minorBetween + 1)) / majorTicks;
        final subAngle = _startAngle + _sweepAngle * subT;
        final subOuter = _pointOnCircle(center, radius + 1, subAngle);
        final subInner = _pointOnCircle(center, radius - 9, subAngle);
        canvas.drawLine(subOuter, subInner, minorTickPaint);
      }
    }

    final needleTail = _pointOnCircle(
      center,
      radius * 0.1,
      needleAngle + math.pi,
    );
    final needleTip = _pointOnCircle(center, radius - 24, needleAngle);
    final needlePaint = Paint()
      ..color = colorScheme.primary
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(needleTail, needleTip, needlePaint);

    final hubOuterPaint = Paint()..color = colorScheme.primary;
    final hubInnerPaint = Paint()..color = colorScheme.onPrimary;
    canvas.drawCircle(center, 9, hubOuterPaint);
    canvas.drawCircle(center, 4.2, hubInnerPaint);
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
        oldDelegate.colorScheme != colorScheme;
  }
}
