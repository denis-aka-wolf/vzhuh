import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vzhuh/connection_service.dart';

void main() {
  group('LocalConnectionService loopback policy', () {
    test('allows only the IPv4 loopback address', () {
      expect(
        LocalConnectionService.isLoopbackAddress('127.0.0.1'),
        isTrue,
      );
      expect(LocalConnectionService.isLoopbackAddress('127.0.0.2'), isFalse);
      expect(LocalConnectionService.isLoopbackAddress('10.2.3.4'), isFalse);
      expect(LocalConnectionService.isLoopbackAddress('192.168.1.20'), isFalse);
      expect(LocalConnectionService.isLoopbackAddress('8.8.8.8'), isFalse);
      expect(LocalConnectionService.isLoopbackAddress('2001:db8::1'), isFalse);
      expect(
        LocalConnectionService.isLoopbackAddress('not-an-address'),
        isFalse,
      );
    });

    test('advertises only the loopback address', () async {
      expect(
        await LocalConnectionService.availableAddresses(),
        [LocalConnectionService.loopbackAddress],
      );
    });

    test('rejects non-loopback listen and connect addresses', () async {
      final service = LocalConnectionService();
      addTearDown(service.dispose);

      await expectLater(
        service.startListening('192.168.1.20', 52741),
        throwsFormatException,
      );
      await expectLater(
        service.connect('192.168.1.20', 52741),
        throwsFormatException,
      );
      expect(service.isListening, isFalse);
      expect(service.isConnecting, isFalse);
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
      expect(receiver.listeningAddress, '127.0.0.1');
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
