import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// Must match the origin allowed by `location /ws` in nginx.conf.
const _allowedOrigin = 'https://tracking.qutma.com';

WebSocketChannel openWebSocket(Uri uri) =>
    IOWebSocketChannel.connect(uri, headers: {'Origin': _allowedOrigin});
