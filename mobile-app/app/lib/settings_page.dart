import 'package:flutter/material.dart';
import 'ble_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // keep track of loading to wait for ble response and request
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Vibration feedback", style: TextStyle(fontSize: 18)),
                Transform.scale(
                  scale: 0.65,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: vibrationSetting,
                    builder: (context, isEnabled, child) {
                      return Switch(
                        value: isEnabled,
                        onChanged: _isLoading
                            ? null
                            : (bool value) async {
                                final messenger = ScaffoldMessenger.of(context);
                                // lock switch before sending request
                                setState(() {
                                  _isLoading = true;
                                });
                                
                                // send request
                                bool success = await setVibration(value);
                                
                                if (success) {
                                  // if request is sent succesfully, update global variable
                                  vibrationSetting.value = value;
                                } else {
                                  // show error is request failed
                                  messenger.showSnackBar(
                                    const SnackBar(content: Text("Failed to update vibration setting.")),
                                  );
                                  
                                }
                                // unlock switch at the end of the request
                                if (mounted) {
                                  setState(() {
                                    _isLoading = false;
                                  });
                                }
                              },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
