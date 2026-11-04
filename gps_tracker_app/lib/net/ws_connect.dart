// Opens a WebSocket that the production Nginx will accept.
// Browsers send an Origin header on their own; native (Android/iOS/desktop)
// clients don't, so the io implementation adds it.
export 'ws_connect_web.dart' if (dart.library.io) 'ws_connect_io.dart';
