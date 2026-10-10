// shared constants used by UI and BLE

const String broadcastMac = "FFFFFFFF";

// max payload size of one fragment for broadcast messages
const int broadcastMaxFragmentBytes = 240;

// encryption constants
const int _encryptionNonceBytes = 12;
const int _encryptionMacBytes = 16;
const int encryptionMetaBytes = _encryptionMacBytes + _encryptionNonceBytes;

// max payload size of one fragment for private messages
// base 64 adds a factor of 1.33 + nonce and auth tag (mac) must fit
// 240 -> 152
const int privateMaxFragmentBytes =
    broadcastMaxFragmentBytes ~/ 4 * 3 - _encryptionNonceBytes - _encryptionMacBytes;
    
// max number of fragments a message can reach
const int maxFragmentsPerMessage = 4;
    
const int maxUserNameLength = 16;

// value on which the battery is considered charging
const int batteryChargingValue = 110;

const int minValidUnixStamp = 1000000000;

const int peerOfflineTtlSeconds = 120;

