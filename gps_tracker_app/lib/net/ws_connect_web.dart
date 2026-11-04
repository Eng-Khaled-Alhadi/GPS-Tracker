import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel openWebSocket(Uri uri) => WebSocketChannel.connect(uri);
