import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:app/core/logger.dart';
import 'package:app/services/ble_service.dart';

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
  int? _connectIndex;

  @override
  void initState() {
    super.initState();
    _startDiscovery();
  }

  // close the route this widget lives on
  void _closeThisRoute() {
    // find the route that contains this widget
    final route = ModalRoute.of(context);
    // remove this route from navigator stack
    if (route != null) Navigator.of(context).removeRoute(route);
  }

  void _startDiscovery() async {
    startBluetoothDeviceScan((combinedDevices) {
      if (mounted) {
        setState(() {
          _devices = combinedDevices;
        });
      }
    });
  }

  Future<void> _connect(BluetoothDevice device, int index) async {
    setState(() => _connectIndex = index);

    bool success = await connectAndSetupDevice(device);

    if (!mounted) return;

    if (success) {
      _closeThisRoute();
    } else {
      setState(() => _connectIndex = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Connection or channel setup failed")));
    }
  }

  @override
  void dispose() {
    stopBluetoothScan();
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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white70),
            ),
          ),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: isBluetoothOn,
              builder: (context, isBtOn, child) {
                if (!isBtOn) {
                  return Center(
                    child: Text("Please turn on Bluetooth", style: TextStyle(color: Colors.white)),
                  );
                }

                if (_devices.isEmpty) {
                  return Center(
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
                  );
                }
                return ListView.separated(
                  itemCount: _devices.length,
                  // horizontal line between list tiles
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, i) {
                    final device = _devices[i];
                    final isConnectedToThis = device.isConnected;
                    final isConnecting = _connectIndex == i;

                    return ListTile(
                      // DEVICE TILE
                      // checks if the app is trying to connect to a device
                      leading: isConnecting
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              // loading icon if the device is connecting
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          // green icon for connected devices
                          : isConnectedToThis
                          ? const Icon(Icons.check_circle_outline, color: Colors.green)
                          : const Icon(Icons.bluetooth, color: Colors.white),
                      title: Text(
                        device.platformName.isEmpty ? "Unknown" : device.platformName,
                        style: TextStyle(color: isConnectedToThis ? Colors.green : Colors.white),
                      ),
                      // only connect if not already connected/connecting
                      onTap: (isConnecting || isConnectedToThis) ? null : () => _connect(device, i),

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
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
