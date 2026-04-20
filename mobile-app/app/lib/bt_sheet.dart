import 'dart:async';
import 'package:app/ble_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert';

List<BluetoothCharacteristic> _foundChars = [];
List<BluetoothCharacteristic> get chars => _foundChars;

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

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 15), androidUsesFineLocation: true);

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
    _foundChars.clear();
    setState(() => _connectIndex = index);
    try {
      await device.connect();
      debugPrint("[BLE] Connected ${device.platformName}");

      List<BluetoothService> services = await device.discoverServices();

      for (var service in services) {
        for (var characteristics in service.characteristics) {
          // writable and readable characteristic means it was found
          if (characteristics.properties.write && characteristics.properties.notify) {
            _foundChars.add(characteristics);
          }
        }
      }
      if (_foundChars.length == 2) {
        setupBleCommunication(_foundChars[1], _foundChars[0]);
        debugPrint("[BLE] Data characteristic found: ${_foundChars[0].uuid}");
        debugPrint("[BLE] Control characteristic found: ${_foundChars[1].uuid}");
        debugPrint("[BLE] BLE channels succesfully set up.");
      } else {
        debugPrint("[BLE] ERROR: Expected 2 channels, got  ${_foundChars.length}.");
      }
      if (mounted) Navigator.pop(context);
    }
    // if connect not succesful, reset index to null
    catch (e) {
      if (mounted) {
        setState(() => _connectIndex = null);
        debugPrint("[BLE] Connection failed.");
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Connection failed: $e")));
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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white70),
            ),
          ),
          if (!_isBtOn)
            const Expanded(
              child: Center(
                child: Text("Please turn on Bluetooth", style: TextStyle(color: Colors.white)),
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
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, i) {
                        final device = _devices[i];
                        final isConnectedToThis = FlutterBluePlus.connectedDevices.contains(device);
                        final isConnecting = _connectIndex == i;

                        return ListTile(
                          leading: isConnecting
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : isConnectedToThis
                              ? const Icon(Icons.check_circle_outline, color: Colors.green)
                              : const Icon(Icons.bluetooth, color: Colors.white),
                          title: Text(
                            device.platformName.isEmpty ? "Unknown" : device.platformName,
                            style: TextStyle(
                              color: isConnectedToThis ? Colors.green : Colors.white,
                            ),
                          ),
                          // only connect if not already connected/connecting
                          onTap: (isConnecting || isConnectedToThis)
                              ? null
                              : () => _connect(device, i),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }
}
