import 'dart:convert';

import 'package:emzy_chess/network/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NetworkMessage', () {
    test('MOVE round-trips through the wire format', () {
      const fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      final line = encodeLine(NetworkMessage.move(san: 'e4', fen: fen));

      expect(line.endsWith('\n'), isTrue);
      final decoded = NetworkMessage.tryDecode(line.trim());
      expect(decoded, isNotNull);
      expect(decoded!.type, NetworkMessageType.move);
      expect(decoded.san, 'e4');
      expect(decoded.fen, fen);
    });

    test('MOVE payload matches the protocol contract', () {
      final json = jsonDecode(
        NetworkMessage.move(san: 'e4', fen: '8/8/8/8/8/8/8/8 w - - 0 1')
            .toString(),
      ) as Map<String, dynamic>;
      expect(json, {
        'type': 'MOVE',
        'san': 'e4',
        'fen': '8/8/8/8/8/8/8/8 w - - 0 1',
      });
    });

    test('malformed and unknown input decodes to null', () {
      expect(NetworkMessage.tryDecode('not json at all'), isNull);
      expect(NetworkMessage.tryDecode(''), isNull);
      expect(NetworkMessage.tryDecode('{"type": "NOPE"}'), isNull);
      expect(NetworkMessage.tryDecode('[1,2,3]'), isNull);
      // Missing san/fen on a MOVE is tolerated structurally (resync path).
      expect(NetworkMessage.tryDecode('{"type": "RESIGN"}')!.type,
          NetworkMessageType.resign);
    });
  });

  group('TcpLineDecoder', () {
    test('reassembles messages split across chunk boundaries', () {
      final decoder = TcpLineDecoder();
      const fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      final bytes = utf8.encode('{"type": "MOVE", "san": "e4", "fen": "$fen"}\n');

      // Cut the message in the middle of the JSON.
      final first = decoder.add(bytes.sublist(0, 20));
      expect(first, isEmpty);
      final second = decoder.add(bytes.sublist(20));
      expect(second, hasLength(1));
      expect(second.single.san, 'e4');
    });

    test('handles several messages in one chunk and skips garbage lines', () {
      final decoder = TcpLineDecoder();
      final bytes = utf8.encode(
        'garbage\n{"type": "PING"}\n{"type": "MOVE", "san": "d4", "fen": "x"}\n',
      );
      final messages = decoder.add(bytes);
      expect(messages.map((m) => m.type).toList(),
          [NetworkMessageType.ping, NetworkMessageType.move]);
      expect(messages.last.san, 'd4');
    });

    test('drops a peer that spews bytes without ever sending a newline', () {
      final decoder = TcpLineDecoder();
      expect(decoder.add(utf8.encode('x' * 40000)), isEmpty);
      // The decoder recovers and still parses the next well-formed message.
      final messages = decoder.add(utf8.encode('{"type": "SYNC", "fen": "f"}\n'));
      expect(messages.single.type, NetworkMessageType.sync);
    });
  });
}
