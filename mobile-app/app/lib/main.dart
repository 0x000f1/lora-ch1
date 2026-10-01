import 'package:app/ble_service.dart';
import 'package:app/private_page.dart';
import 'package:app/settings_page.dart';
import 'package:flutter/material.dart';
// https://pub.dev/packages/flutter_floating_bottom_bar
import 'package:flutter_floating_bottom_bar/flutter_floating_bottom_bar.dart';
import 'theme.dart';
import 'bt_sheet.dart';
import 'broadcast_page.dart';

void main() {
  //debugPaintSizeEnabled = true; // see layout bounds in debug mode
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(theme: appTheme, home: const HomePage());
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  // late: will be initialized before first use (in initState())
  late TabController tabController;
  int currentPage = 0;

  @override
  void initState() {
    initConnectionListener();
    tabController = TabController(length: 2, vsync: this);
    tabController.animation!.addListener(() {
      if (tabController.index != currentPage) {
        changePage(tabController.index);
      }
    });
    super.initState();
  }

  void changePage(int newPage) {
    setState(() {
      currentPage = newPage;
    });
  }

  @override
  void dispose() {
    tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("Device Connected: $isDeviceConnected");
    return Scaffold(
      appBar: AppBar(
        title: const Text("BT Mesh Chat"),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: isDeviceConnected,
            builder: (context, isConnected, child) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isConnected)
                    ValueListenableBuilder<int>(
                      valueListenable: batteryLevel,
                      builder: (context, bat, child) {
                        return Row(
                          children: [
                            Text("$bat%"),
                            const SizedBox(width: 4),
                            Icon(
                              bat > 20
                                  ? Icons.battery_full_rounded
                                  : Icons.battery_alert_rounded,
                            ),
                          ],
                        );
                      },
                    ),


                  if (isConnected)
                    IconButton(
                      icon: Icon(Icons.settings),
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SettingsPage(),
                          ),
                        );
                      },
                      
                    ),


                  IconButton(
                    icon: Icon(
                      isConnected
                          ? Icons.bluetooth_connected_rounded
                          : Icons.bluetooth_rounded,
                      color: Colors.black,
                    ),
                    onPressed: () => showBTSheet(context),
                  ),
                  const SizedBox(width: 4),
                ],
              );
            },
          ),
        ],
      ),
      body: BottomBar(
        borderRadius: BorderRadius.circular(25),
        width: MediaQuery.of(context).size.width * 0.55,
        barColor: Colors.grey.shade200,

        body: (context, controller) => TabBarView(
          controller: tabController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            //const Center(child: Text("Private Chats")),
            PrivatePage(scrollController: controller),
            BroadcastPage(scrollController: controller),
          ],
        ),
        child: TabBar(
          indicatorAnimation: TabIndicatorAnimation.elastic,
          indicatorPadding: EdgeInsetsGeometry.only(top: 7, bottom: 7),
          indicator: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(20),
          ),
          unselectedLabelColor: Colors.blue.shade800,
          labelColor: Colors.blue.shade800,
          controller: tabController,
          tabs: [
            SizedBox(
              height: 55,
              width: 55,
              child: Center(
                child: ImageIcon(
                  AssetImage('assets/icons/private.png'),
                  size: 35,
                ),
              ),
            ),
            SizedBox(
              height: 55,
              width: 55,
              child: Center(
                child: ImageIcon(
                  AssetImage('assets/icons/broadcast.png'),
                  size: 35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
