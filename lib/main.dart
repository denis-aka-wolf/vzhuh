import 'package:flutter/material.dart';

import 'connection_service.dart';

void main() {
  runApp(const VzhuhApp());
}

class VzhuhApp extends StatelessWidget {
  const VzhuhApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Вжух',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3659D9)),
        useMaterial3: true,
      ),
      home: const ConnectionHomePage(),
    );
  }
}

class ConnectionHomePage extends StatefulWidget {
  const ConnectionHomePage({super.key});

  @override
  State<ConnectionHomePage> createState() => _ConnectionHomePageState();
}

class _ConnectionHomePageState extends State<ConnectionHomePage> {
  final LocalConnectionService _service = LocalConnectionService();
  final TextEditingController _remoteAddressController =
      TextEditingController(text: LocalConnectionService.loopbackAddress);
  final TextEditingController _listenPortController = TextEditingController(
    text: '52741',
  );
  final TextEditingController _remotePortController = TextEditingController(
    text: '52741',
  );

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    _service.dispose();
    _listenPortController.dispose();
    _remoteAddressController.dispose();
    _remotePortController.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  int? _readPort(TextEditingController controller) {
    final port = int.tryParse(controller.text.trim());
    if (port == null || port < 1 || port > 65535) {
      _showMessage('Укажите порт от 1 до 65535.');
      return null;
    }
    return port;
  }

  Future<void> _startWaiting() async {
    final port = _readPort(_listenPortController);
    if (port == null) return;
    await _runAction(
      () => _service.startListening(
        LocalConnectionService.loopbackAddress,
        port,
      ),
    );
  }

  Future<void> _connect() async {
    final address = _remoteAddressController.text.trim();
    final port = _readPort(_remotePortController);
    if (port == null) return;
    await _runAction(() => _service.connect(address, port));
  }

  Future<void> _runAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Вжух'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                'Демо на этом ПК',
                style: theme.textTheme.labelLarge,
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Демонстрация подключения',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Проверьте обмен запросом и подтверждением между двумя '
                'экземплярами приложения на этом компьютере.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              _SecurityNotice(
                onLearnMore: () => _showMessage(
                  'Эта версия передаёт только запрос и состояние соединения. '
                  'Экран, мышь и клавиатура не передаются.',
                ),
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final waitingCard = _buildWaitingCard(context);
                  final connectCard = _buildConnectCard(context);

                  if (constraints.maxWidth < 700) {
                    return Column(
                      children: [
                        waitingCard,
                        const SizedBox(height: 16),
                        connectCard,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: waitingCard),
                      const SizedBox(width: 16),
                      Expanded(child: connectCard),
                    ],
                  );
                },
              ),
              if (_service.hasPendingRequest) ...[
                const SizedBox(height: 16),
                _buildIncomingRequest(context),
              ],
              const SizedBox(height: 16),
              _buildConnectionStatus(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWaitingCard(BuildContext context) {
    final theme = Theme.of(context);
    final isListening = _service.isListening;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeading(
              icon: Icons.sensors,
              title: 'Ожидать подключения',
            ),
            const SizedBox(height: 16),
            TextField(
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Адрес ожидания',
                hintText: LocalConnectionService.loopbackAddress,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _listenPortController,
              enabled: !isListening,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Порт',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isListening
                    ? () => _runAction(_service.stopListening)
                    : (_service.isBusy ? null : _startWaiting),
                icon: Icon(isListening ? Icons.stop : Icons.sensors),
                label: Text(isListening ? 'Прекратить ожидание' : 'Начать'),
              ),
            ),
            if (isListening) ...[
              const SizedBox(height: 12),
              Text(
                'Адрес для подключения: '
                '${_service.listeningAddress}:${_service.listeningPort}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConnectCard(BuildContext context) {
    final isConnecting = _service.isConnecting;
    final enabled = !_service.isBusy;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeading(
              icon: Icons.computer,
              title: 'Подключить второй экземпляр',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _remoteAddressController,
              readOnly: true,
              enabled: enabled,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Адрес этого компьютера',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _remotePortController,
              enabled: enabled,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Порт',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: enabled ? _connect : null,
                icon: isConnecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link),
                label: Text(
                  isConnecting ? 'Ожидание подтверждения' : 'Подключиться',
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'В демонстрационном режиме разрешён только 127.0.0.1. '
              'Подключение с других устройств невозможно.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomingRequest(BuildContext context) {
    final address = _service.pendingAddress ?? 'Неизвестный адрес';
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeading(
              icon: Icons.person_add_alt_1,
              title: 'Запрос на подключение',
            ),
            const SizedBox(height: 8),
            Text('Компьютер $address запрашивает соединение.'),
            const SizedBox(height: 8),
            const Text(
              'Принимайте запрос только от человека, которому доверяете. '
              'Подтверждение устанавливает соединение, но не включает '
              'удалённое управление.',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _runAction(_service.acceptPending),
                  icon: const Icon(Icons.check),
                  label: const Text('Разрешить соединение'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _runAction(_service.rejectPending),
                  icon: const Icon(Icons.close),
                  label: const Text('Отклонить'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStatus(BuildContext context) {
    final theme = Theme.of(context);
    String title;
    String description;
    IconData icon;

    if (_service.isConnected) {
      title = 'Соединение установлено';
      description =
          'Связь с ${_service.connectedAddress ?? 'компьютером'} активна. '
          'Передача экрана и управление недоступны.';
      icon = Icons.check_circle_outline;
    } else if (_service.hasPendingRequest) {
      title = 'Ожидается решение';
      description = 'Подтвердите или отклоните входящий запрос.';
      icon = Icons.hourglass_top;
    } else if (_service.isConnecting) {
      title = 'Подключение…';
      description = 'Ожидаем подтверждения на другом компьютере.';
      icon = Icons.sync;
    } else if (_service.isListening) {
      title = 'Ожидание подключения';
      description =
          'Другой компьютер может отправить запрос по указанному адресу.';
      icon = Icons.sensors;
    } else {
      title = 'Не подключено';
      description =
          'Выберите режим: ожидание входящего запроса или подключение.';
      icon = Icons.lan_outlined;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.primary, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(description),
                ],
              ),
            ),
            if (_service.isConnected)
              TextButton.icon(
                onPressed: () => _runAction(_service.disconnect),
                icon: const Icon(Icons.link_off),
                label: const Text('Отключиться'),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _SecurityNotice extends StatelessWidget {
  const _SecurityNotice({required this.onLearnMore});

  final VoidCallback onLearnMore;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.errorContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: colors.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Демо только на этом ПК (127.0.0.1). Соединение не шифруется '
                'и не проверяет личность. Экран и ввод не передаются.',
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
            TextButton(onPressed: onLearnMore, child: const Text('Подробнее')),
          ],
        ),
      ),
    );
  }
}
