import 'dart:async';

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
      title: 'Simple Speedometer',
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
  Position? _lastPosition;
  DateTime? _lastTimestamp;

  String _statusMessage = 'Initializing...';
  bool _isTracking = false;
  double _speedMps = 0;

  @override
  void initState() {
    super.initState();
    _initTracking();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initTracking() async {
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
      },
    );

    setState(() {
      _statusMessage = 'Tracking speed...';
      _isTracking = true;
    });
  }

  void _onPosition(Position position) {
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
      _statusMessage = 'Tracking speed...';
      _isTracking = true;
    });
  }

  double get _speedKmh => _speedMps * 3.6;

  @override
  Widget build(BuildContext context) {
    final speedKmh = _speedKmh;
    final progress = (speedKmh / _maxSpeedKmh).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Simple Speedometer'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 220,
                height: 220,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 14,
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          speedKmh.toStringAsFixed(1),
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                        const Text('km/h'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
              Text(
                'Lat: ${_lastPosition?.latitude.toStringAsFixed(6) ?? '-'}  '
                'Lng: ${_lastPosition?.longitude.toStringAsFixed(6) ?? '-'}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _initTracking,
                icon: const Icon(Icons.my_location),
                label: Text(_isTracking ? 'Re-check Permission' : 'Enable Location'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
