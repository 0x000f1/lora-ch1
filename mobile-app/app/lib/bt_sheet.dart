import 'dart:async';
import 'package:app/ble_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';


void showBTSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => const _BtScanSheet(),
  );
}

class _BtScanSheet extends StatefulWidget {
  const _BtScanSheet();

  @override
  State<_BtScanSheet> createState() => _BtScanSheetState();
}

class _BtScanSheetState extends State<_BtScanSheet> {
  List<BluetoothDevice> _devices = [];
  StreamSubscription? _scanSub;
  StreamSubscription? _adapterSub;
  int? _connectIndex;
  bool _isBtOn = true;

  @override
  void initState() {
    super.initState();
    _initBt();
  }

  void _initBt() {
    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      if (mounted) {
        setState(() => _isBtOn = state == BluetoothAdapterState.on);
      }
      if (state == BluetoothAdapterState.on) {
        _startDiscovery();
      }
    });
  }

  void _startDiscovery() {
    // cancel in case another scan is already running
    _scanSub?.cancel();

    // filter all connected devices
    final connected = FlutterBluePlus.connectedDevices
        .where((d) => d.platformName.startsWith("lora-ch1"))
        .toList();

    setState(() {
      _devices = connected;
    });

    FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
      androidUsesFineLocation: true,
    );

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        // filter from all devices
        final scanned = results
            .map((r) => r.device)
            .where((d) => d.platformName.startsWith("lora-ch1"))
            .toList();

        // combine scanned and connected lists
        final combined = List<BluetoothDevice>.from(connected);
        for (var dev in scanned) {
          if (!combined.contains(dev)) {
            combined.add(dev);
          }
        }

        setState(() {
          _devices = combined;
        });
      }
    });
  }

  Future<void> _connect(BluetoothDevice device, int index) async {
    setState(() => _connectIndex = index);

    // function from ble_service.dart
    bool success = await connectAndSetupDevice(device);

    if (mounted) {
      if (success) {
        Navigator.pop(context);
      } else {
        setState(() => _connectIndex = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Connection or channel setup failed")),
        );
      }
    }
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _adapterSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              "Available Devices",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
          ),
          if (!_isBtOn)
            const Expanded(
              child: Center(
                child: Text(
                  "Please turn on Bluetooth",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          if (_isBtOn)
            Expanded(
              child: _devices.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Spacer(flex: 3),
                          const Text(
                            "Press the pairing button on the device.",
                            style: TextStyle(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 35),
                          const CircularProgressIndicator(),
                          const Spacer(flex: 4),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: _devices.length,
                      // horizontal line between list tiles
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, i) {
                        final device = _devices[i];
                        final isConnectedToThis = FlutterBluePlus
                            .connectedDevices
                            .contains(device);
                        final isConnecting = _connectIndex == i;

                        return ListTile(
                          // DEVICE TILE
                          // checks if the app is trying to connect to a device
                          leading: isConnecting
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  // loading icon if the device is connecting
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )

                              // green icon for connected devices
                              : isConnectedToThis
                              ? const Icon(
                                  Icons.check_circle_outline,
                                  color: Colors.green,
                                )
                              : const Icon(
                                  Icons.bluetooth,
                                  color: Colors.white,
                                ),
                          title: Text(
                            device.platformName.isEmpty
                                ? "Unknown"
                                : device.platformName,
                            style: TextStyle(
                              color: isConnectedToThis
                                  ? Colors.green
                                  : Colors.white,
                            ),
                          ),
                          // only connect if not already connected/connecting
                          onTap: (isConnecting || isConnectedToThis)
                              ? null
                              : () => _connect(device, i),

                          // DISCONNECT BUTTON
                          // checks if device is already connected
                          trailing: isConnectedToThis
                              ? IconButton(
                                  icon: Icon(Icons.close, color: Colors.red),
                                  onPressed: () async {
                                    await disconnectDevice(device);
                                    setState(() {});
                                  },
                                )
                              // no button if device is not connected already
                              : null,
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }
}
