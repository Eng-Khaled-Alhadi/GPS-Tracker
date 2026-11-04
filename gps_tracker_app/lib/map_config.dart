import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';

// CARTO basemaps require an API key (free tier available).
// Get one at https://carto.com/basemaps/apikey, then run with:
//   flutter run --dart-define=CARTO_API_KEY=your_key
//
// A key's restrictions must ALL pass, and browsers can't send the mobile-app
// headers, so use separate keys: one restricted to Websites (web build) and
// one restricted to Mobile apps (Android/iOS builds).
const String cartoApiKey = String.fromEnvironment('CARTO_API_KEY');

const _androidPackage = 'com.gpstracker.gps_tracker_app';
const _iosBundleId = 'com.gpstracker.gpsTrackerApp';

// SHA-1 of the key that signs the APK. Defaults to the current signing key;
// override when building with a different one (e.g. a release keystore).
const _androidCertSha1 = String.fromEnvironment(
  'CARTO_ANDROID_CERT',
  defaultValue: '10:B9:7D:A8:0A:61:50:20:D5:F5:F7:5B:8E:15:01:A7:A0:A2:F4:4E',
);

// Headers CARTO checks for a key with a "Mobile apps" restriction.
Map<String, String> _cartoAppHeaders() {
  if (kIsWeb) return {};
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return {
        'X-Android-Package': _androidPackage,
        'X-Android-Cert': _androidCertSha1,
      };
    case TargetPlatform.iOS:
      return {'X-Ios-Bundle-Identifier': _iosBundleId};
    default:
      return {};
  }
}

TileLayer cartoDarkTileLayer() {
  return TileLayer(
    urlTemplate:
        'https://basemaps.cartocdn.com/rastertiles/dark_all/{z}/{x}/{y}{r}.png?key={key}',
    additionalOptions: const {'key': cartoApiKey},
    userAgentPackageName: _androidPackage,
    tileProvider: NetworkTileProvider(headers: _cartoAppHeaders()),
  );
}
