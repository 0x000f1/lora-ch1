import 'package:flutter/material.dart';
import 'ble_service.dart';

// default 9 colors
final List<Color> _defaultColors = [
  Colors.amber,
  Colors.orange,
  Colors.red,
  Colors.pink,
  Colors.purple,
  Colors.deepPurple,
  Colors.indigo,
  Colors.lightBlue,
  Colors.green,
];

// build a color picker with 9 default colors and a custom color picker
Widget _buildColorPicker() {
  return Padding(
    padding: EdgeInsets.symmetric(horizontal: 15, vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Select color:", style: TextStyle(fontSize: 20)),
        SizedBox(height: 15,),
        GridView.builder(
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
            bool isLast = index == 9;

            return Center(
              child: SizedBox(
                height: 50,
                width: 50,
                child: Container(
                  decoration: BoxDecoration(
                    color: isLast ? Colors.grey.shade200 : _defaultColors[index],
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 2),
                  ),
                  child: Center(
                    child: Icon(
                      isLast ? Icons.palette_rounded : Icons.person_rounded,
                      color: isLast ? Colors.black54 : Colors.white,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    ),
  );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // keep track of loading to wait for ble response and request
  bool _isLoading = false;
  bool _isSavingUsername = false;

  late final TextEditingController _usernameController;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: usernameSetting.value);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _submitUsername() async {
    final newName = _usernameController.text.trim();
    if (newName.isEmpty || newName == usernameSetting.value) return;

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
      messenger.showSnackBar(SnackBar(content: Text("Failed to update username")));
    }

    if (mounted) {
      setState(() {
        _isSavingUsername = false;
      });
    }
  }

  // show a loading icon for 1 second after pressing the submit button
  Widget _buildSubmitButton() {
    if (_isSavingUsername) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))),
      );
    }

    return IconButton(
      icon: const Icon(Icons.check_circle, color: Colors.blue),
      onPressed: _submitUsername,
    );
  }

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
                // VIBRATION SWITCH
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

          // SET USERNAME
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _usernameController,
                    maxLength: 16,
                    cursorColor: Colors.black,
                    cursorWidth: 1,
                    cursorHeight: 16,
                    decoration: const InputDecoration(
                      labelText: "Username",
                      labelStyle: TextStyle(color: Colors.black),
                      counterText: "",
                      border: OutlineInputBorder(),
                      enabledBorder: OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.black)),
                      disabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.black)),

                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                _buildSubmitButton(),
              ],
            ),
          ),
          _buildColorPicker(),
        ],
      ),
    );
  }
}
