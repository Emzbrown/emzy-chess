# Emzy Chess

Offline Stockfish chess, local Wi-Fi P2P play, and game analysis — built with Flutter.

## Modes

| Mode | What it does |
| --- | --- |
| **Play vs Stockfish** | Fully offline engine game. The human plays White; a strength slider maps to 200 ms – 5 s of engine think time per move. |
| **Play on Local Wi-Fi** | Host advertises `_chess-game._tcp` over mDNS (Bonsoir); a joiner browses, resolves the host to `ip:port`, and connects with a raw TCP socket. The host plays White. |
| **Analyze a Game** | Start from any FEN. Stockfish evaluates every position: a vertical evaluation bar plus a move-by-move evaluation line graph (fl_chart). Tap the graph or a move to scrub the board. |

## Architecture

```
lib/
├── engine/                 # Stockfish behind UCI, isolated from the UI thread
│   ├── engine_isolate.dart #   owns the FFI engine inside a background Isolate
│   ├── uci_engine.dart     #   uci/isready/go bookkeeping, bestmove futures
│   ├── uci_parser.dart     #   pure-Dart parsers for `info`/`bestmove` lines
│   └── engine_manager.dart #   process-wide singleton (one engine instance)
├── network/                # local Wi-Fi P2P
│   ├── protocol.dart       #   newline-delimited JSON: {"type":"MOVE","san":"e4","fen":"..."}
│   └── p2p_service.dart    #   Bonsoir mDNS + dart:io ServerSocket/Socket
├── game/                   # rules and state on top of the `chess` package
│   ├── chess_ops.dart      #   SAN/UCI conversions, legal-move queries
│   ├── game_controller.dart#   the unified BoardInput surface
│   ├── analysis_controller.dart # one evaluation per ply, White POV
│   └── models.dart         #   MoveRecord, PlyEvaluation, enums
└── ui/
    ├── widgets/            # ChessBoard (unified), EvalBar, EvalGraph, MoveList
    └── screens/            # home, engine game, P2P lobby/network game, analysis
```

Key rules:

1. **One board, three inputs.** `ChessBoard` renders whatever `GameController`
   holds and funnels input back through the `BoardInput` interface — human
   touches (`applyTouch`), Stockfish `bestmove`s (`applyEngineMove`), and TCP
   payloads (`applyNetworkMove`) are all the same pipeline.
2. **Engine off the UI thread.** The `stockfish` FFI instance lives in a
   background `Isolate`; UCI commands go in over a `SendPort` and stdout lines
   come back as stream events. Screens only see `Stream<String>` and futures.
3. **Wire format is dumb on purpose.** Newline-delimited JSON over TCP, one
   move object per line; the receiver validates SAN against its local rules and
   falls back to a FEN resync if the two sides drift.

## Platform notes

- **Android** (`android/app/src/main/AndroidManifest.xml`): `INTERNET`,
  `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`
  for TCP + NsdManager-based mDNS.
- **iOS** (`ios/Runner/Info.plist`): `NSLocalNetworkUsageDescription` and
  `NSBonjourServices = _chess-game._tcp` (iOS 14+ local-network permission).
- The `stockfish` package ships native engines for **Android and iOS**. On
  desktop platforms engine screens show a friendly "engine unavailable"
  error with retry; P2P and board features still work.

## Running

```bash
flutter pub get
flutter run          # Android or iOS device on the same Wi-Fi for P2P
```

## Tests

```bash
flutter analyze      # zero issues
flutter test         # 51 tests
```

Coverage: UCI parsing, JSON protocol framing (including chunk-split TCP
reassembly), SAN/UCI chess helpers, the unified game controller (touch, engine,
network, resync, endings), the analysis pipeline with a scripted fake engine
(White-POV conversion, mate scores), and widget tests for the app shell and the
board driven by all three input sources.
