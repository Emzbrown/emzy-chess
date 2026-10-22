import 'dart:async';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

import 'protocol.dart';

/// Connection state of the P2P layer.
enum P2pStatus { idle, hosting, discovering, connecting, connected, error }

/// A peer discovered over mDNS (or advertised by us when hosting).
class PeerDevice {
  const PeerDevice({required this.name, required this.address, required this.port});

  final String name;
  final InternetAddress address;
  final int port;

  @override
  String toString() => '$name ($address:$port)';
}

/// Local Wi-Fi P2P transport.
///
/// Host side: binds a [ServerSocket], advertises via Bonsoir
/// (`_chess-game._tcp`) and accepts a single opponent.
/// Client side: browses mDNS for hosted games, resolves them to ip:port and
/// connects directly with a [Socket].
///
/// All game traffic is newline-delimited JSON (see [protocol.dart]).
class P2pService extends ChangeNotifier {
  P2pStatus _status = P2pStatus.idle;
  String? _error;
  ServerSocket? _server;
  Socket? _socket;
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<Socket>? _acceptSub;
  StreamSubscription<Uint8List>? _socketSub;
  StreamSubscription<BonsoirDiscoveryEvent>? _discoverySub;
  final TcpLineDecoder _decoder = TcpLineDecoder();
  final StreamController<NetworkMessage> _messages =
      StreamController<NetworkMessage>.broadcast();
  final List<PeerDevice> _peers = [];

  P2pStatus get status => _status;
  String? get error => _error;
  List<PeerDevice> get peers => List.unmodifiable(_peers);

  /// Game messages received from the opponent.
  Stream<NetworkMessage> get messages => _messages.stream;

  void _setStatus(P2pStatus status) {
    if (_status == status) return;
    _status = status;
    notifyListeners();
  }

  // ---------------------------------------------------------------- hosting

  /// Starts hosting a game. Returns the TCP port clients connect to.
  Future<int> host({required String playerName}) async {
    await close();
    _error = null;
    try {
      final server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      _server = server;
      _setStatus(P2pStatus.hosting);

      _acceptSub = server.listen((socket) {
        if (_socket != null) {
          // Single-opponent game: refuse extra connections politely.
          socket.destroy();
          return;
        }
        _attachSocket(socket);
      });

      final service = BonsoirService(
        name: playerName.isEmpty ? 'Chess host' : playerName,
        type: kServiceType,
        port: server.port,
        attributes: {'version': '1'},
      );
      final broadcast = BonsoirBroadcast(service: service);
      await broadcast.initialize();
      await broadcast.start();
      _broadcast = broadcast;
      return server.port;
    } catch (error) {
      _error = 'Could not host a game: $error';
      _setStatus(P2pStatus.error);
      rethrow;
    }
  }

  // --------------------------------------------------------------- browsing

  /// Starts browsing for hosted games on the local network.
  Future<void> browse() async {
    await close();
    _error = null;
    try {
      final discovery = BonsoirDiscovery(type: kServiceType);
      await discovery.initialize();
      _discovery = discovery;
      _peers.clear();
      _setStatus(P2pStatus.discovering);

      _discoverySub = discovery.eventStream?.listen((event) {
        switch (event) {
          case BonsoirDiscoveryServiceFoundEvent():
            unawaited(event.service.resolve(discovery.serviceResolver));
          case BonsoirDiscoveryServiceResolvedEvent():
            _onPeerResolved(event.service);
          case BonsoirDiscoveryServiceLostEvent():
            _peers.removeWhere((p) => p.name == event.service.name);
            notifyListeners();
          default:
            break;
        }
      });

      await discovery.start();
    } catch (error) {
      _error = 'Could not browse for games: $error';
      _setStatus(P2pStatus.error);
      rethrow;
    }
  }

  void _onPeerResolved(BonsoirService service) {
    final port = service.port;
    // Bonsoir 7 hands out host addresses as strings; parse them ourselves.
    final addresses = service.hostAddresses;
    if (addresses.isEmpty) return;

    // Prefer IPv4; mDNS often returns link-local IPv6 too.
    InternetAddress? address;
    for (final candidate in addresses) {
      final parsed = InternetAddress.tryParse(candidate);
      if (parsed != null && parsed.type == InternetAddressType.IPv4) {
        address = parsed;
        break;
      }
    }
    address ??= InternetAddress.tryParse(addresses.first);
    if (address == null) return;

    _peers.removeWhere((p) => p.name == service.name);
    _peers.add(PeerDevice(name: service.name, port: port, address: address));
    notifyListeners();
  }

  // ------------------------------------------------------------- connecting

  /// Connects to a discovered peer.
  Future<void> connectTo(PeerDevice peer) async {
    await close();
    _error = null;
    _setStatus(P2pStatus.connecting);
    try {
      final socket = await Socket.connect(
        peer.address,
        peer.port,
        timeout: const Duration(seconds: 5),
      );
      _attachSocket(socket);
    } catch (error) {
      _error = 'Could not connect to ${peer.name}: $error';
      _setStatus(P2pStatus.error);
      rethrow;
    }
  }

  void _attachSocket(Socket socket) {
    _socket = socket;
    _setStatus(P2pStatus.connected);
    _socketSub = socket.listen(
      (data) {
        for (final message in _decoder.add(data)) {
          _messages.add(message);
        }
      },
      onError: (Object error) {
        _error = 'Connection error: $error';
        _setStatus(P2pStatus.error);
      },
      onDone: () {
        if (_status == P2pStatus.connected) {
          _error = 'Opponent disconnected';
          _setStatus(P2pStatus.error);
        }
      },
      cancelOnError: true,
    );
  }

  // ---------------------------------------------------------------- traffic

  /// Sends one message to the opponent. No-op when not connected.
  void send(NetworkMessage message) {
    final socket = _socket;
    if (socket == null || _status != P2pStatus.connected) return;
    try {
      socket.write(encodeLine(message));
    } catch (error) {
      _error = 'Could not send: $error';
      _setStatus(P2pStatus.error);
    }
  }

  /// Convenience for the protocol's core payload.
  void sendMove({required String san, required String fen}) {
    send(NetworkMessage.move(san: san, fen: fen));
  }

  // ----------------------------------------------------------------- tidy up

  /// Stops hosting/browsing and drops any connection. Safe to call first.
  Future<void> close() async {
    await _discoverySub?.cancel();
    _discoverySub = null;
    if (_discovery != null) {
      try {
        await _discovery!.stop();
      } catch (_) {
        // Plugin may already be shut down on some platforms.
      }
      _discovery = null;
    }
    await _acceptSub?.cancel();
    _acceptSub = null;
    await _server?.close();
    _server = null;
    if (_broadcast != null) {
      try {
        await _broadcast!.stop();
      } catch (_) {
        // Ignore: broadcast teardown is best-effort.
      }
      _broadcast = null;
    }
    await _socketSub?.cancel();
    _socketSub = null;
    _socket?.destroy();
    _socket = null;
    _peers.clear();
    if (_status != P2pStatus.error) _setStatus(P2pStatus.idle);
  }

  @override
  void dispose() {
    unawaited(close());
    unawaited(_messages.close());
    super.dispose();
  }
}
