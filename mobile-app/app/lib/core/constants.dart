// shared static constants used by UI and BLE

const String broadcastMac = "FFFFFFFF";

const String broadcastId = "FFFFFFFFFFFF";

// max payload size of one fragment for broadcast messages
const int maxFragmentBytes = 64;

// max number of fragments a message can reach
const int maxFragmentsPerMessage = 8;

const int maxBytesBroadcast = maxFragmentsPerMessage * maxFragmentBytes;
// base64 adds a factor of 4/3, nonce and authtag is 28 bytes
const int maxBytesPrivate = (maxBytesBroadcast * 3) ~/ 4 - encryptionMetaBytes - 2;

// encryption constants
const int _encryptionNonceBytes = 12;
const int _encryptionMacBytes = 16;
const int encryptionMetaBytes = _encryptionMacBytes + _encryptionNonceBytes;


    
const int maxUserNameLength = 16;

// value on which the battery is considered charging
const int batteryChargingValue = 110;

const int minValidUnixStamp = 1000000000;

const int peerOfflineTtlSeconds = 120;

