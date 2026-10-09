import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'ble_service.dart';
import 'logger.dart';

String colorToHex(Color color) {
  return color
      .toARGB32()
      .toRadixString(16)
      .padLeft(8, '0')
      .substring(2)
      .toUpperCase();
}

Color colorFromHex(String hex) {
  return Color(int.parse('FF$hex', radix: 16));
}

// default 10 colors
final List<Color> _defaultColors = [
  Colors.amber,
  Colors.orange,
  Colors.red,
  Colors.pink,
  Colors.purple,
  Colors.deepPurple,
  Colors.lightBlue,
  Colors.green,
  Colors.brown,
  Colors.black,
];

class SettingsPage extends StatefulWidget {
  final String deviceName;

  const SettingsPage({super.key, required this.deviceName});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // keep track of loading to wait for ble response and request
  bool _isLoading = false;
  bool _isSavingUsername = false;

  bool _isFindingDevice = false;
  bool _isRestartingDevice = false;
  bool _isResettingDevice = false;
  int? _selectedColorIndex;

  bool isUpdatingPreferences = false;
  String? _currentLogName;
  List<LogEntry> _logEntries = [];

  // keeps track of whether the device is restarting or resetting
  bool get _isBusy => _isResettingDevice || _isRestartingDevice;

  Widget _buildUserProfile() {
    final colors = Theme.of(context).colorScheme;
    return ValueListenableBuilder<String>(
      valueListenable: colorSetting,
      builder: (context, colorHex, child) {
        return Container(
          padding: EdgeInsets.all(7),
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 8,
              ),
            ],
            color: colors.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: colors.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: Badge(
                backgroundColor: Colors.transparent,
                alignment: Alignment.bottomRight,
                offset: Offset(-1, -15),
                label: Container(
                  height: 18,
                  width: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.surfaceContainerHigh,
                  ),
                  child: Icon(Icons.edit_sharp, size: 11, color: Colors.white),
                ),

                child: Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    color: colorHex.isEmpty
                        ? Colors.brown
                        : colorFromHex(colorHex),
                    shape: BoxShape.circle,
                  ),
                  child: GestureDetector(
                    onTap: _showColorChooser,
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                ),
              ),
              title: GestureDetector(
                onTap: _showUserNameInput,
                child: ValueListenableBuilder<String>(
                  valueListenable: usernameSetting,
                  builder: (context, username, child) {
                    return Row(
                      children: [
                        Text(username),
                        SizedBox(width: 5),
                        Icon(Icons.edit_rounded, color: Colors.white, size: 11),
                      ],
                    );
                  },
                ),
              ),
              subtitle: Text(widget.deviceName),
            ),
          ),
        );
      },
    );
  }

  void _showUserNameInput() {
    _usernameController.text = usernameSetting.value;
    final validUserNameRegex = RegExp(r'^[\p{L}0-9_\-\. ]+$', unicode: true);
    String? errorMessage;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              insetPadding: EdgeInsets.symmetric(horizontal: 16),
              title: Text("Edit Username", style: TextStyle(fontSize: 18)),
              content: SizedBox(
                width: 500,
                child: TextField(
                  controller: _usernameController,
                  autofocus: true,
                  maxLength: 16,
                  onChanged: (value) {
                    // reset errormessage on each input
                    if (errorMessage != null) {
                      setDialogState(() {
                        errorMessage = null;
                      });
                    }
                  },
                  decoration: InputDecoration(
                    labelText: "Username",
                    border: OutlineInputBorder(),
                    counterText: "",
                    errorText: errorMessage,
                  ),
                ),
              ),
              actionsPadding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              actions: [
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text(
                        "Cancel",
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        final input = _usernameController.text.trim();

                        if (input.isEmpty) {
                          setDialogState(() {
                            errorMessage = "Username cannot be empty";
                          });
                          return;
                        }

                        if (!validUserNameRegex.hasMatch(input)) {
                          setDialogState(() {
                            errorMessage =
                                "Username contains invalid characters.";
                          });
                        }

                        final success = await _submitUsername();

                        if (success && dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                      },
                      child: const Text("Submit"),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showColorChooser() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Choose color",
      barrierColor: Colors.black54,
      pageBuilder: (dialogContext, _, _) {
        return SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 135),
              child: Material(
                borderRadius: BorderRadius.circular(28),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(width: 330, child: _buildColorPicker()),
              ),
            ),
          ),
        );
      },
    );
  }

  // build a color picker with 10 default colors
  Widget _buildColorPicker() {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValueListenableBuilder<String>(
            valueListenable: colorSetting,
            builder: (context, colorHex, child) {
              return GridView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  // 5 colors in 2 rows
                  crossAxisCount: 5,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: 10,
                itemBuilder: (context, index) {
                  final isSelected =
                      colorHex == colorToHex(_defaultColors[index]);

                  return Center(
                    child: SizedBox(
                      height: 50,
                      width: 50,
                      child: GestureDetector(
                        onTap: _isLoading
                            ? null
                            : () async {
                                final hex = colorToHex(_defaultColors[index]);

                                setState(() {
                                  _isLoading = true;
                                });

                                final messenger = ScaffoldMessenger.of(context);
                                bool success = await setColor(hex);

                                if (!success && mounted) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text("Failed to update color."),
                                    ),
                                  );
                                }

                                if (mounted) {
                                  setState(() {
                                    _isLoading = false;
                                  });
                                }
                              },
                        child: Container(
                          decoration: BoxDecoration(
                            color: _defaultColors[index],
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.black,
                              width: isSelected ? 3 : 2,
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              isSelected
                                  ? Icons.check_rounded
                                  : Icons.person_rounded,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildToggleSwitch(
    IconData icon,
    Color iconBackgroundColor,
    String titleText,
    ValueListenable<bool> listenable,
    ValueChanged<bool> onChanged,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: EdgeInsets.only(right: 0, left: 16, top: 6, bottom: 6),
        leading: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: iconBackgroundColor,
          ),
          height: 40,
          width: 40,
          child: Icon(icon, color: Colors.white),
        ),
        title: Text(titleText, style: TextStyle(fontSize: 18)),
        trailing: Transform.scale(
          scale: 0.65,
          child: ValueListenableBuilder<bool>(
            valueListenable: listenable,
            builder: (context, isEnabled, child) {
              return Switch(
                value: isEnabled,
                onChanged: isUpdatingPreferences ? null : onChanged,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLocationSwitch() {
    return _buildToggleSwitch(
      Icons.location_on_rounded,
      Colors.teal.shade300,
      "Share location",
      locationSetting,
      _updateLocationSetting,
    );
  }

  Widget _buildVibrationSwitch() {
    return _buildToggleSwitch(
      Icons.vibration_rounded,
      Colors.blue.shade300,
      "Haptic feedback",
      vibrationSetting,
      _updateVibrationSetting,
    );
  }

  // send toggle haptic
  Future<void> _updateVibrationSetting(bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    final previousValue = vibrationSetting.value;

    vibrationSetting.value = value;

    final success = await setVibration(value);

    if (!success) {
      vibrationSetting.value = previousValue;
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text("Failed to update location sharing")),
        );
      }
    }
  }

  Future<void> _updateLocationSetting(bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    final previousValue = locationSetting.value;

    locationSetting.value = value;

    final success = await setLocationSharing(value);

    if (!success) {
      locationSetting.value = previousValue;
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text("Failed to update location sharing")),
        );
      }
    }
  }

  Widget _buildDeviceActionButton({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    bool isDisabled = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    final textColor = isDisabled ? Colors.grey.shade400 : colors.onSurface;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white),
        ),
        title: Text(title, style: TextStyle(fontSize: 18, color: textColor)),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 13, color: textColor),
        ),
      ),
    );
  }

  // send find device request to device
  Future<void> _findDevice() async {
    if (_isFindingDevice) return;

    setState(() {
      _isFindingDevice = true;
    });

    // disable button for 6 seconds after pressing the button
    final cooldown = Future.delayed(const Duration(seconds: 6));
    final success = await sendCommandWithResponse("FIND", "FIND_OK");
    await cooldown;

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Find device command failed.")),
      );
    }

    if (mounted) {
      setState(() {
        _isFindingDevice = false;
      });
    }
  }

  // send restart device request to device
  Future<void> _restartDevice() async {
    if (_isRestartingDevice) return;

    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _isRestartingDevice = true;
    });

    final success = await restartDevice();

    if (!success) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Failed to restart device.")),
      );

      if (mounted) {
        setState(() {
          _isRestartingDevice = false;
        });
      }
    }
  }

  // send factory reset request
  Future<void> _resetDevice() async {
    if (_isResettingDevice) return;

    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _isResettingDevice = true;
    });

    final success = await factoryResetDevice();

    if (!success) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Failed to reset device.")),
      );

      if (mounted) {
        setState(() {
          _isResettingDevice = false;
        });
      }
    }
  }

  // build haptic toggle button, find device, restart and reset device
  Widget _buildDeviceActions() {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("PREFERENCES", style: TextStyle(fontSize: 16)),
        SizedBox(height: 6),
        Container(
          padding: EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: colors.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _buildVibrationSwitch(),
              SizedBox(height: 6),
              _buildLocationSwitch(),
            ],
          ),
        ),
        SizedBox(height: 20),
        Text("DEVICE", style: TextStyle(fontSize: 16)),
        SizedBox(height: 6),
        Container(
          padding: EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: colors.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _buildDeviceActionButton(
                icon: Icons.device_unknown_rounded,
                iconColor: Colors.orange.shade300,
                title: "Find device",
                subtitle: "Play a short vibration effect on the device",
                onTap: (_isFindingDevice || _isBusy) ? null : _findDevice,
                isDisabled: _isFindingDevice || _isBusy,
              ),
              SizedBox(height: 7),
              _buildDeviceActionButton(
                icon: Icons.restart_alt_rounded,
                iconColor: Colors.green.shade300,
                title: "Restart device",
                subtitle: "Restart device while keeping all settings",
                onTap: _isBusy ? null : _restartDevice,
                isDisabled: _isBusy,
              ),
            ],
          ),
        ),
        SizedBox(height: 20),
        Text("DANGER ZONE", style: TextStyle(fontSize: 16)),
        SizedBox(height: 6),
        Container(
          padding: EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: colors.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: _buildDeviceActionButton(
            icon: Icons.restore_page_rounded,
            iconColor: Colors.red.shade300,
            title: "Reset device",
            subtitle: "Reset device to default settings",
            onTap: _isBusy ? null : _resetDevice,
            isDisabled: _isBusy,
          ),
        ),
      ],
    );
  }

  Future<void> _startNewLog() async {
    var enteredName = '';
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start new log'),
        content: TextField(
          autofocus: true,
          onChanged: (value) => enteredName = value,
          decoration: const InputDecoration(
            labelText: 'Environment / file name',
            hintText: 'Forest, open field, city...',
          ),
          onSubmitted: (_) => Navigator.pop(dialogContext, enteredName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, enteredName),
            child: const Text('Start'),
          ),
        ],
      ),
    );

    if (name == null || name.trim().isEmpty) return;
    try {
      final fileName = await LogManager.startNew(name);
      if (!mounted) return;
      setState(() {
        _currentLogName = fileName;
        _logEntries = [];
      });
    } catch (error) {
      AppLogger.log('LOG', 'Failed to start log: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create log file: $error')),
        );
      }
    }
  }

  Future<void> _openCurrentLog() async {
    List<LogEntry> entries;
    try {
      entries = await LogManager.readCurrent();
    } catch (error) {
      AppLogger.log('LOG', 'Failed to read log: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open log file: $error')),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _logEntries = entries);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (context, controller) => _buildLogList(controller),
      ),
    );
  }

  Widget _buildLogList(ScrollController controller) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Text(
            _currentLogName ?? 'Current log',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _logEntries.isEmpty
                ? const Center(
                    child: Text('No incoming messages in this log yet.'),
                  )
                : ListView.builder(
                    controller: controller,
                    itemCount: _logEntries.length,
                    itemBuilder: (context, index) {
                      final entry = _logEntries[index];
                      final values = entry.toJson();
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: LogManager.labels.map((label) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 125,
                                      child: Text(
                                        label,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text('${values[label] ?? ''}'),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoggingActions() {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('MESSAGE LOGS', style: TextStyle(fontSize: 16)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: colors.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _buildDeviceActionButton(
                icon: Icons.fiber_new_rounded,
                iconColor: Colors.indigo.shade300,
                title: 'Start new log',
                subtitle: _currentLogName ?? 'Choose an environment name',
                onTap: _startNewLog,
              ),
              const SizedBox(height: 7),
              _buildDeviceActionButton(
                icon: Icons.folder_open_rounded,
                iconColor: Colors.teal.shade300,
                title: 'Open current log',
                subtitle: 'View received messages as cards',
                onTap: _currentLogName == null ? null : _openCurrentLog,
                isDisabled: _currentLogName == null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  late final TextEditingController _usernameController;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: usernameSetting.value);
    _initSelectedColor();
    LogManager.currentName()
        .then((name) {
          if (mounted) setState(() => _currentLogName = name);
        })
        .catchError((error) {
          AppLogger.log('LOG', 'Failed to load current log: $error');
        });
    isDeviceConnected.addListener(_handleConnectionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleConnectionChanged();
    });
  }

  @override
  void dispose() {
    isDeviceConnected.removeListener(_handleConnectionChanged);
    _usernameController.dispose();
    super.dispose();
  }

  // go back if the device disconnected
  void _handleConnectionChanged() {
    if (!isDeviceConnected.value && mounted) {
      Navigator.of(context).pop();
    }
  }

  // highlight the current color in the UI
  void _initSelectedColor() {
    final currentColorHex = colorSetting.value;
    if (currentColorHex.isEmpty) return;

    for (int i = 0; i < _defaultColors.length; i++) {
      final hex = colorToHex(_defaultColors[i]);
      if (hex == currentColorHex) {
        _selectedColorIndex = i;
        break;
      }
    }
  }

  // submit username to device
  Future<bool> _submitUsername() async {
    final newName = _usernameController.text.trim();
    if (newName.isEmpty) return false;
    if (newName == usernameSetting.value) return true;

    // unfocus keyboard
    FocusScope.of(context).unfocus();

    setState(() {
      _isSavingUsername = true;
    });

    final messenger = ScaffoldMessenger.of(context);
    bool success = await setUsername(newName);

    if (success) {
      await Future.delayed(Duration(seconds: 1));
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text("Failed to update username")),
      );
    }

    if (mounted) {
      setState(() {
        _isSavingUsername = false;
      });
    }

    return success;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: IgnorePointer(
        ignoring: _isBusy,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _isBusy ? 0.45 : 1,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            children: [
              _buildUserProfile(),
              SizedBox(height: 20),
              Padding(
                padding: EdgeInsetsGeometry.symmetric(horizontal: 5),
                child: _buildDeviceActions(),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: _buildLoggingActions(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
