/// În afara browserului nu e nevoie (telefonul / Windows nativ folosesc
/// local_auth).
Future<bool> webPresenceAvailable() async => false;

Future<bool> webPresenceVerify() async => false;
