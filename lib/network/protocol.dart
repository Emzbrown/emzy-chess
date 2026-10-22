/// Wire names for the JSON messages exchanged over the P2P TCP link.
///
/// The framing is newline-delimited JSON, one move object per line:
///   {"type": "MOVE", "san": "e4", "fen": "..."}
library;

import 'dart:convert';

const String kServiceType = '_chess-game._tcp';

enum NetworkMessageType {
  hello,
  move,
  newGame,
  resign,
  sync,
  ping,
  pong,
}

const Map<String, NetworkMessageType> _wireToType = {
  'HELLO': NetworkMessageType.hello,
  'MOVE': NetworkMessageType.move,
  'NEW_GAME': NetworkMessageType.newGame,
  'RESIGN': NetworkMessageType.resign,
  'SYNC': NetworkMessageType.sync,
  'PING': NetworkMessageType.ping,
  'PONG': NetworkMessageType.pong,
};

const Map<NetworkMessageType, String> _typeToWire = {
  NetworkMessageType.hello: 'HELLO',
  NetworkMessageType.move: 'MOVE',
  NetworkMessageType.newGame: 'NEW_GAME',
  NetworkMessageType.resign: 'RESIGN',
  NetworkMessageType.sync: 'SYNC',
  NetworkMessageType.ping: 'PING',
  NetworkMessageType.pong: 'PONG',
};

/// One decoded message from the opponent.
class NetworkMessage {
  const NetworkMessage._({
    required this.type,
    this.san,
    this.fen,
    this.name,
    this.color,
  });

  final NetworkMessageType type;

  /// SAN of the move (MOVE messages).
  final String? san;

  /// Board position right after the move (MOVE messages).
  final String? fen;

  /// Player name / assigned color (HELLO messages).
  final String? name;
  final String? color;

  /// The canonical move payload required by the protocol:
  /// `{"type": "MOVE", "san": "e4", "fen": "..."}`.
  factory NetworkMessage.move({required String san, required String fen}) =
      _MoveMessage;

  factory NetworkMessage.hello({required String name, required String color}) {
    return NetworkMessage._(
      type: NetworkMessageType.hello,
      name: name,
      color: color,
    );
  }

  factory NetworkMessage.newGame() =>
      const NetworkMessage._(type: NetworkMessageType.newGame);

  factory NetworkMessage.resign() =>
      const NetworkMessage._(type: NetworkMessageType.resign);

  factory NetworkMessage.sync(String fen) =>
      NetworkMessage._(type: NetworkMessageType.sync, fen: fen);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': _typeToWire[type]!,
        if (san != null) 'san': san,
        if (fen != null) 'fen': fen,
        if (name != null) 'name': name,
        if (color != null) 'color': color,
      };

  /// Decodes a single JSON line. Returns null for anything malformed so a
  /// hostile/corrupt peer can never crash the game screen.
  static NetworkMessage? tryDecode(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) return null;
      final type = _wireToType[decoded['type']];
      if (type == null) return null;
      return NetworkMessage._(
        type: type,
        san: decoded['san'] as String?,
        fen: decoded['fen'] as String?,
        name: decoded['name'] as String?,
        color: decoded['color'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => jsonEncode(toJson());
}

/// Dedicated subtype so `NetworkMessage.move` can be a factory constructor.
class _MoveMessage extends NetworkMessage {
  _MoveMessage({required super.san, required super.fen})
      : super._(type: NetworkMessageType.move);
}

/// Encodes a message as one newline-terminated JSON line.
String encodeLine(NetworkMessage message) => '${jsonEncode(message.toJson())}\n';

/// Reassembles newline-delimited messages from TCP chunk boundaries, which
/// rarely align with message boundaries.
class TcpLineDecoder {
  String _buffer = '';
  static const _maxLineLength = 8192;

  /// Feed raw bytes; returns every complete message found so far.
  List<NetworkMessage> add(List<int> bytes) {
    _buffer += utf8.decode(bytes, allowMalformed: true);
    if (_buffer.length > _maxLineLength * 4 && !_buffer.contains('\n')) {
      // Defensive: a peer spewing garbage without newlines gets dropped.
      _buffer = '';
      return const [];
    }

    final messages = <NetworkMessage>[];
    var newlineIndex = _buffer.indexOf('\n');
    while (newlineIndex >= 0) {
      final line = _buffer.substring(0, newlineIndex);
      _buffer = _buffer.substring(newlineIndex + 1);
      final message = NetworkMessage.tryDecode(line);
      if (message != null) messages.add(message);
      newlineIndex = _buffer.indexOf('\n');
    }
    return messages;
  }
}
