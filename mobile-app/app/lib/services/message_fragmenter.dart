// Fragmentation of outgoing messages and assembly of incoming messages

import 'dart:convert';

import 'package:app/core/constants.dart';
import 'package:characters/characters.dart';
import 'package:app/core/logger.dart';

// buffer for incoming fragments, key: mac
final Map<String, List<String?>> _fragBuffers = {};

// split every outgoing message into 200 byte sized fragments
List<String> splitMessage(String text) {
  final List<String> fragments = [];
  final StringBuffer currentFragment = StringBuffer();
  int currentFragmentBytes = 0;

  // in each iteration, check if current character can fit into a fragment without splitting a multi-byte character
  for (final char in text.characters) {
    final charBytes = utf8.encode(char).length;

    // reset current fragment if adding a character results in one over the byte limit
    if (currentFragmentBytes + charBytes > maxFragmentBytes) {
      fragments.add(currentFragment.toString());
      currentFragment.clear();
      currentFragmentBytes = 0;
    }
    // append character and update bytecount
    currentFragment.write(char);
    currentFragmentBytes += charBytes;
  }

  // add remaining text into a seperate fragment
  if (currentFragment.isNotEmpty) {
    fragments.add(currentFragment.toString());
  }

  return fragments;
}

// rearrange every incoming message, only returns when every fragment arrives
String? handleIncomingFragments(String rawData) {
  final parts = rawData.split(';');
  if (parts.length < 9) return rawData;

  final senderMac = parts[0];
  final senderUsername = parts[1];
  final colorHex = parts[2];
  final targetMac = parts[3];
  final currentFragment = int.tryParse(parts[4]);
  final totalFragments = int.tryParse(parts[5]);
  final timeStamp = parts[6];
  final rssi = parts[7];
  final payload = parts.sublist(8).join(';');

  if (currentFragment == null ||
      totalFragments == null ||
      currentFragment < 1 ||
      currentFragment > totalFragments) {
    return null;
  }

  // send single fragment message instantly
  if (totalFragments <= 1) {
    return "$senderMac;$senderUsername;$colorHex;$targetMac;$timeStamp;$rssi;$payload";
  }
  
  // use sendermac + timestamp as a key
  final String bufferKey = "${senderMac}_$timeStamp";

  // get the slot of this fragment
  var slots = _fragBuffers[bufferKey];

  // fill the buffer with the amount of fragments excepted, or
  // replace if it was created for a different amount of fragment
  if (slots == null || slots.length != totalFragments) {
    slots = _fragBuffers[bufferKey] = List<String?>.filled(totalFragments, null);
  }

  slots[currentFragment - 1] = payload;
  AppLogger.log("FRAG", "fragment $currentFragment/$totalFragments from $senderMac stored, fragbuffer = {$_fragBuffers}");

  // wait until every fragment has arrived
  if (slots.contains(null)) {
    return null;
  }

  // clear buffer after all fragments arrive
  _fragBuffers.remove(bufferKey);
  final completeMessage = slots.join();

  return "$senderMac;$senderUsername;$colorHex;$targetMac;$timeStamp;$rssi;$completeMessage";
}

// clear all partially recieved message
void clearFragmentBuffers() => _fragBuffers.clear();
