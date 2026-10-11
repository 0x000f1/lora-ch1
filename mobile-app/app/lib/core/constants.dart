// shared static constants used by UI and BLE

const String broadcastMac = "FFFFFFFF";

// max payload size of one fragment for broadcast messages
const int maxFragmentBytes = 240;

// encryption constants
const int _encryptionNonceBytes = 12;
const int _encryptionMacBytes = 16;
const int encryptionMetaBytes = _encryptionMacBytes + _encryptionNonceBytes;

// max number of fragments a message can reach
const int maxFragmentsPerMessage = 4;
    
const int maxUserNameLength = 16;

// value on which the battery is considered charging
const int batteryChargingValue = 110;

const int minValidUnixStamp = 1000000000;

const int peerOfflineTtlSeconds = 120;

