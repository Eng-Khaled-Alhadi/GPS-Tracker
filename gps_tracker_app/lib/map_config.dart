import 'package:flutter_map/flutter_map.dart';

// CARTO basemaps require an API key (free tier available).
// Get one at https://carto.com/basemaps/apikey, then run with:
//   flutter run --dart-define=CARTO_API_KEY=your_key
const String cartoApiKey = String.fromEnvironment('CARTO_API_KEY');

TileLayer cartoDarkTileLayer() {
  return TileLayer(
    urlTemplate:
        'https://basemaps.cartocdn.com/rastertiles/dark_all/{z}/{x}/{y}{r}.png?key={key}',
    additionalOptions: const {'key': cartoApiKey},
    userAgentPackageName: 'com.gpstracker.gps_tracker_app',
  );
}
