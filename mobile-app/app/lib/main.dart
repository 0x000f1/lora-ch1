import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
// https://pub.dev/packages/flutter_floating_bottom_bar
import 'package:flutter_floating_bottom_bar/flutter_floating_bottom_bar.dart';
import 'theme.dart';
import 'bt_sheet.dart';

void main() {
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
  @override
  void initState() {
    super.initState();
    tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("BT Mesh Chat"),
        actions: [
          IconButton(
            icon: Icon(Icons.bluetooth_rounded),
            onPressed: () => showBTSheet(context),
          ),
        ],
      ),
      body: BottomBar(
        borderRadius: BorderRadius.circular(25),
        width: MediaQuery.of(context).size.width * 0.55,
        barColor: Colors.lightBlue.shade300,
        body: (context, controller) => Container(),
        child: TabBar(
          indicatorAnimation: TabIndicatorAnimation.elastic,
          indicatorPadding: EdgeInsetsGeometry.only(top: 7, bottom: 7),
          indicator: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(20),
          ),
          unselectedLabelColor: Colors.black,
          labelColor: Colors.black,
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
