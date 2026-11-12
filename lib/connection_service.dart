import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class LocalConnectionService extends ChangeNotifier {
  static const loopbackAddress = '127.0.0.1';
  static const _connectMessage = 'VZH1:CONNECT\n';
  static const _acceptMessage = 'VZH1:ACCEPT\n';
  static const _rejectMessage = 'VZH1:REJECT\n';
  static const _maxHandshakeLength = 32;

  ServerSocket? _server;
  StreamSubscription<Socket>? _serverSubscription;
  Socket? _pendingSocket;
  StreamSubscription<List<int>>? _pendingSubscription;
  Timer? _pendingTimer;
  Socket? _activeSocket;
  StreamSubscription<List<int>>? _activeSubscription;
  Socket? _outgoingSocket;
  StreamSubscription<List<int>>? _outgoingSubscription;
  bool _isConnecting = false;
  bool _serverOwnsActiveSocket = false;
  bool _disposed = false;

  bool get isListening => _server != null;
  bool get isConnecting => _isConnecting;
  bool get hasPendingRequest => _pendingSocket != null;
  bool get isConnected => _activeSocket != null;
  bool get isBusy =>
      isListening || isConnecting || hasPendingRequest || isConnected;
  String? get listeningAddress => _server?.address.address;
  int? get listeningPort => _server?.port;
  String? get pendingAddress => _pendingSocket?.remoteAddress.address;
  String? get connectedAddress => _activeSocket?.remoteAddress.address;

  static bool isLoopbackAddress(String value) {
    return value == loopbackAddress;
  }

  Future<void> startListening(String address, int port) async {
    _validateEndpoint(address, port);
    if (isBusy) {
      throw StateError('Сначала завершите текущее ожидание или соединение.');
    }

    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    _server = server;
    _serverSubscription = server.listen(
      _handleIncoming,
      onError: (Object error) {
        if (identical(_server, server)) {
          _server = null;
          _serverSubscription = null;
          _notifyListeners();
        }
      },
      onDone: () {
        if (identical(_server, server)) {
          _server = null;
          _serverSubscription = null;
          _notifyListeners();
        }
      },
    );
    _notifyListeners();
  }

  Future<void> stopListening() async {
    final server = _server;
    _server = null;
    final serverSubscription = _serverSubscription;
    _serverSubscription = null;
    await serverSubscription?.cancel();
    await server?.close();

    _pendingTimer?.cancel();
    _pendingTimer = null;
    final pendingSocket = _pendingSocket;
    _pendingSocket = null;
    final pendingSubscription = _pendingSubscription;
    _pendingSubscription = null;
    await pendingSubscription?.cancel();
    pendingSocket?.destroy();

    if (_serverOwnsActiveSocket) {
      await disconnect();
    }
    _notifyListeners();
  }

  Future<void> connect(String address, int port) async {
    _validateEndpoint(address, port);
    if (isBusy) {
      throw StateError('Сначала завершите текущее ожидание или соединение.');
    }

    _isConnecting = true;
    _notifyListeners();
    Socket? socket;
    StreamSubscription<List<int>>? subscription;

    try {
      socket = await Socket.connect(
        InternetAddress.tryParse(address)!,
        port,
        timeout: const Duration(seconds: 5),
      );
      _outgoingSocket = socket;
      final reply = Completer<List<int>>();
      final responseBytes = <int>[];
      final connectedSocket = socket;
      subscription = connectedSocket.listen(
        (data) {
          if (reply.isCompleted) return;
          for (final byte in data) {
            responseBytes.add(byte);
            if (responseBytes.length > _maxHandshakeLength) {
              reply.complete(const []);
              return;
            }
            if (byte == 10) {
              reply.complete(List<int>.from(responseBytes));
              return;
            }
          }
        },
        onError: (Object error) {
          if (!reply.isCompleted) reply.complete(const []);
          _handleSocketEnded(connectedSocket);
        },
        onDone: () {
          if (!reply.isCompleted) reply.complete(const []);
          _handleSocketEnded(connectedSocket);
        },
      );
      _outgoingSubscription = subscription;

      connectedSocket.add(utf8.encode(_connectMessage));
      await connectedSocket.flush();
      final responseBytesResult = await reply.future.timeout(
        const Duration(seconds: 60),
      );
      if (responseBytesResult.isEmpty) {
        throw StateError('Компьютер закрыл соединение до подтверждения.');
      }
      final response = utf8.decode(responseBytesResult, allowMalformed: false);

      if (response != _acceptMessage) {
        if (response == _rejectMessage) {
          throw StateError('Запрос на подключение отклонён.');
        }
        throw const FormatException('Получен неизвестный ответ узла.');
      }

      _activeSocket = connectedSocket;
      _activeSubscription = subscription;
      _outgoingSocket = null;
      _outgoingSubscription = null;
      _isConnecting = false;
      _serverOwnsActiveSocket = false;
      _notifyListeners();
    } catch (error) {
      _outgoingSocket = null;
      _outgoingSubscription = null;
      _isConnecting = false;
      await subscription?.cancel();
      socket?.destroy();
      _notifyListeners();
      rethrow;
    }
  }

  Future<void> acceptPending() async {
    final socket = _pendingSocket;
    if (socket == null) {
      throw StateError('Нет входящего запроса для подтверждения.');
    }

    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pendingSocket = null;
    _activeSocket = socket;
    _activeSubscription = _pendingSubscription;
    _pendingSubscription = null;
    _serverOwnsActiveSocket = true;

    try {
      socket.add(utf8.encode(_acceptMessage));
      await socket.flush();
      _notifyListeners();
    } catch (error) {
      socket.destroy();
      _handleSocketEnded(socket);
      rethrow;
    }
  }

  Future<void> rejectPending() async {
    final socket = _pendingSocket;
    if (socket == null) {
      throw StateError('Нет входящего запроса для отклонения.');
    }

    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pendingSocket = null;
    final subscription = _pendingSubscription;
    _pendingSubscription = null;

    try {
      socket.add(utf8.encode(_rejectMessage));
      await socket.flush();
    } finally {
      await subscription?.cancel();
      socket.destroy();
      _notifyListeners();
    }
  }

  Future<void> disconnect() async {
    final socket = _activeSocket;
    if (socket == null) return;

    _activeSocket = null;
    _activeSubscription = null;
    _serverOwnsActiveSocket = false;
    socket.destroy();
    _notifyListeners();
  }

  void _handleIncoming(Socket socket) {
    if (!isLoopbackAddress(socket.remoteAddress.address) ||
        _pendingSocket != null ||
        _activeSocket != null) {
      socket.destroy();
      return;
    }

    final requestBytes = utf8.encode(_connectMessage);
    final receivedBytes = <int>[];
    var handshakeComplete = false;
    final handshakeTimer = Timer(const Duration(seconds: 5), socket.destroy);

    late final StreamSubscription<List<int>> subscription;
    subscription = socket.listen(
      (data) {
        if (handshakeComplete ||
            identical(_pendingSocket, socket) ||
            identical(_activeSocket, socket)) {
          return;
        }

        receivedBytes.addAll(data);
        if (receivedBytes.length > requestBytes.length) {
          handshakeTimer.cancel();
          socket.destroy();
          return;
        }
        if (receivedBytes.length < requestBytes.length) return;

        handshakeComplete = true;
        handshakeTimer.cancel();
        for (var index = 0; index < requestBytes.length; index++) {
          if (receivedBytes[index] != requestBytes[index]) {
            socket.destroy();
            return;
          }
        }

        if (_pendingSocket != null || _activeSocket != null) {
          socket.destroy();
          return;
        }

        _pendingSocket = socket;
        _pendingSubscription = subscription;
        _pendingTimer = Timer(
          const Duration(seconds: 60),
          () => unawaited(rejectPending()),
        );
        _notifyListeners();
      },
      onError: (Object error) {
        handshakeTimer.cancel();
        socket.destroy();
      },
      onDone: () {
        handshakeTimer.cancel();
        _handleSocketEnded(socket);
      },
    );
  }

  void _handleSocketEnded(Socket socket) {
    var changed = false;
    if (identical(_pendingSocket, socket)) {
      _pendingSocket = null;
      _pendingSubscription = null;
      _pendingTimer?.cancel();
      _pendingTimer = null;
      changed = true;
    }
    if (identical(_activeSocket, socket)) {
      _activeSocket = null;
      _activeSubscription = null;
      _serverOwnsActiveSocket = false;
      changed = true;
    }
    if (identical(_outgoingSocket, socket)) {
      _outgoingSocket = null;
      _outgoingSubscription = null;
      _isConnecting = false;
      changed = true;
    }
    if (changed) _notifyListeners();
  }

  void _validateEndpoint(String address, int port) {
    if (!isLoopbackAddress(address)) {
      throw const FormatException(
        'В демонстрационном режиме разрешён только адрес 127.0.0.1.',
      );
    }
    if (port < 1 || port > 65535) {
      throw const FormatException('Порт должен быть от 1 до 65535.');
    }
  }

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pendingTimer?.cancel();
    unawaited(_serverSubscription?.cancel());
    unawaited(_pendingSubscription?.cancel());
    unawaited(_activeSubscription?.cancel());
    unawaited(_outgoingSubscription?.cancel());
    unawaited(_server?.close());
    _pendingSocket?.destroy();
    _activeSocket?.destroy();
    _outgoingSocket?.destroy();
    super.dispose();
  }
}
