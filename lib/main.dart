import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'geofencing_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Woosmap Geofencing REST Sample',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final GeofencingService _service = GeofencingService();
  String _status = 'Idle';

  /// Latest Woosmap permission status:
  /// `GRANTED_BACKGROUND`, `GRANTED_FOREGROUND`, `DENIED`, `UNKNOWN` (or null
  /// until the first check completes).
  String? _permission;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check when returning to the app — e.g. after the user changed the
    // setting in the system Settings app, or iOS upgraded to "Always".
    if (state == AppLifecycleState.resumed) {
      _refreshPermission();
    }
  }

  /// Re-read the current permission status into [_permission].
  Future<void> _refreshPermission() async {
    final status = await _service.permissionStatus();
    if (!mounted) return;
    setState(() => _permission = status);
  }

  /// Whether we still need to ask the user (show the permission button).
  /// True while unknown or denied; false once foreground/background granted.
  bool get _permissionNeedsRequest =>
      _permission == null ||
      _permission == 'UNKNOWN' ||
      _permission == 'DENIED';

  /// Human-readable label for the granted states shown when no request is due.
  String get _permissionLabel {
    switch (_permission) {
      case 'GRANTED_BACKGROUND':
        return 'Always (background) ✓';
      case 'GRANTED_FOREGROUND':
        return 'While in use (foreground)';
      default:
        return _permission ?? 'Unknown';
    }
  }

  /// Handler for the "Grant location permission" button.
  ///
  /// The first request differs per platform:
  ///   - iOS: request "Always" directly — `requestAlwaysAuthorization` drives
  ///     the When-In-Use → Always sequence itself.
  ///   - Android: request foreground ("When In Use") first; the OS won't grant
  ///     background until foreground is granted, so we upgrade separately below.
  ///
  /// IMPORTANT: the plugin does NOT resolve `requestPermissions()` on the first
  /// (undetermined) call — on iOS it shows the OS prompt and never returns a
  /// result, so awaiting it hangs. We therefore fire the request without
  /// awaiting and poll `getPermissionsStatus()` for the outcome instead.
  Future<void> _requestPermission() async {
    setState(() => _status = 'Requesting permission…');

    // 1. iOS -> background:true ("Always"); Android -> background:false
    //    (foreground first).
    String? status = 'UNKNOWN';
    if (Platform.isIOS) {
      status = await _service.requestPermission(background: true);
    } else {
      status = await _service.requestPermission(background: false);
    }
    // 2. Android only: upgrade to background ("Always") once foreground is
    //    granted. (On iOS step 1 already requested "Always".)
    if (Platform.isAndroid &&
        (status == 'GRANTED_FOREGROUND' || status == 'GRANTED_BACKGROUND')) {
      status = await _service.requestPermission(background: true);
    }

    if (!mounted) return;
    setState(() {
      _permission = status;
      _status = 'Idle';
    });

    // On Android/ios the plugin does not route to Settings on a hard denial; guide
    // the user there ourselves.
    if (status == 'DENIED') {
      await _promptOpenSettings(
        'Location access is denied for this app.\n'
        'Enable "Always" location in Settings, then try again.',
      );
      await _refreshPermission();
    }
  }

  /// Show a dialog that routes the user to the system app settings, where
  /// they can grant a permission the in-app prompt can no longer request.
  Future<void> _promptOpenSettings(String message) async {
    if (!mounted) return;
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Location permission needed'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
    if (open == true) {
      await openAppSettings();
    }
  }

  Future<void> _start() async {
    // Only check that permission is already granted — requesting it is handled
    // by the "Grant location permission" button.
    await _refreshPermission();
    if (!mounted) return;
    if (_permissionNeedsRequest) {
      setState(() =>
          _status = 'Grant location permission before starting tracking.');
      return;
    }
    setState(() => _status = 'Starting passiveTracking...');
    await _service.initAndStart();
    if (!mounted) return;
    setState(() => _status = 'passiveTracking started');
  }

  Future<void> _stop() async {
    await _service.stop();
    setState(() => _status = 'Tracking stopped');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Woosmap Geofencing REST Sample')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Status: $_status', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 24),
            // Show the permission button while access is unknown/denied;
            // otherwise just show the current permission state as a label.
            if (_permissionNeedsRequest)
              ElevatedButton.icon(
                onPressed: _requestPermission,
                icon: const Icon(Icons.location_on),
                label: const Text('Grant location permission'),
              )
            else
              Text(
                'Location permission: $_permissionLabel',
                style: const TextStyle(fontSize: 16),
              ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _start,
              child: const Text('Start passive tracking'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _stop,
              child: const Text('Stop tracking'),
            ),
          ],
        ),
      ),
    );
  }
}
