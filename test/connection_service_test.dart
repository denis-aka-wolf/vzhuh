import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vzhuh/connection_service.dart';

void main() {
  group('LocalConnectionService address policy', () {
    test('allows loopback and private IPv4 addresses only', () {
      expect(LocalConnectionService.isAllowedAddress('127.0.0.1'), isTrue);
      expect(LocalConnectionService.isAllowedAddress('10.2.3.4'), isTrue);
      expect(LocalConnectionService.isAllowedAddress('172.16.0.1'), isTrue);
      expect(LocalConnectionService.isAllowedAddress('172.31.255.254'), isTrue);
      expect(LocalConnectionService.isAllowedAddress('192.168.1.20'), isTrue);

      expect(LocalConnectionService.isAllowedAddress('172.32.0.1'), isFalse);
      expect(LocalConnectionService.isAllowedAddress('8.8.8.8'), isFalse);
      expect(LocalConnectionService.isAllowedAddress('2001:db8::1'), isFalse);
      expect(
        LocalConnectionService.isAllowedAddress('not-an-address'),
        isFalse,
      );
    });
  });

  test('connects after explicit approval and disconnects cleanly', () async {
    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservation.port;
    await reservation.close();

    final receiver = LocalConnectionService();
    final connector = LocalConnectionService();
    final incomingRequest = Completer<void>();
    var wasConnected = false;
    final disconnected = Completer<void>();

    receiver.addListener(() {
      if (receiver.hasPendingRequest && !incomingRequest.isCompleted) {
        incomingRequest.complete();
      }
      if (receiver.isConnected) wasConnected = true;
      if (wasConnected && !receiver.isConnected && !disconnected.isCompleted) {
        disconnected.complete();
      }
    });

    try {
      await receiver.startListening('127.0.0.1', port);
      final connection = connector.connect('127.0.0.1', port);
      await incomingRequest.future.timeout(const Duration(seconds: 5));

      expect(receiver.pendingAddress, '127.0.0.1');
      await receiver.acceptPending();
      await connection.timeout(const Duration(seconds: 5));
      expect(receiver.isConnected, isTrue);
      expect(connector.isConnected, isTrue);

      await connector.disconnect();
      await disconnected.future.timeout(const Duration(seconds: 5));
      expect(receiver.isConnected, isFalse);
      expect(connector.isConnected, isFalse);
    } finally {
      await connector.disconnect();
      await receiver.stopListening();
      connector.dispose();
      receiver.dispose();
    }
  });
}
