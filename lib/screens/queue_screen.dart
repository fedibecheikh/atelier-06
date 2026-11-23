import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:waiting_room_app/models/queue_state.dart';
import 'package:waiting_room_app/providers/connectivity_provider.dart';
import 'package:waiting_room_app/providers/queue_provider.dart';
import 'package:waiting_room_app/widgets/client_card.dart';
import 'package:waiting_room_app/widgets/loading_widget.dart';
import 'package:waiting_room_app/widgets/offline_banner.dart';
import 'package:waiting_room_app/widgets/queue_empty_widget.dart';

class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key});

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  final TextEditingController _nameController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  ConnectivityProvider? _connectivity;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
    _connectivity = context.read<ConnectivityProvider>();
    _connectivity!.addListener(_onConnectivityChanged);
  }

  @override
  void dispose() {
    _connectivity?.removeListener(_onConnectivityChanged);
    _scrollController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _onConnectivityChanged() {
    if (!mounted) return;
    if (_connectivity!.isOnline) {
      unawaited(context.read<QueueProvider>().syncPending());
    }
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      unawaited(context.read<QueueProvider>().loadMore());
    }
  }

  Future<void> _addClient() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    _nameController.clear();
    await context.read<QueueProvider>().addClient(name);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<QueueProvider>();
    final connectivity = context.watch<ConnectivityProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resilient Waiting Room'),
        centerTitle: true,
        actions: [
          if (provider.isSyncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          IconButton(
            key: const Key('sync-button'),
            tooltip: 'Synchronize pending registrations',
            icon: const Icon(Icons.cloud_upload),
            onPressed: () => context.read<QueueProvider>().syncPending(),
          ),
          IconButton(
            key: const Key('refresh-button'),
            tooltip: 'Refresh queue',
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<QueueProvider>().refresh(),
          ),
        ],
      ),
      body: Column(
        children: [
          OfflineBanner(status: connectivity.status),
          if (provider.isDemo) _DemoBanner(),
          if (provider.errorMessage != null &&
              provider.state != QueueState.error)
            MaterialBanner(
              content: Text(provider.errorMessage!),
              actions: [
                TextButton(
                  onPressed: () => context.read<QueueProvider>().refresh(),
                  child: const Text('Retry'),
                ),
                TextButton(
                  onPressed: provider.clearError,
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('client-name-field'),
                    controller: _nameController,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Client name',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addClient(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  key: const Key('add-client-button'),
                  onPressed: _addClient,
                  child: const Text('Add'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'Clients in Queue: ${provider.clients.length}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (provider.isSyncing)
                  const Text(
                    'Syncing...',
                    style: TextStyle(color: Colors.blueGrey),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildQueue(context, provider)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildQueue(BuildContext context, QueueProvider provider) {
    return switch (provider.state) {
      QueueState.initial ||
      QueueState.loading =>
        const LoadingWidget(message: 'Loading queue...'),
      QueueState.error => _QueueErrorWidget(
          message: provider.errorMessage ?? 'Failed to load queue',
          onRetry: () => context.read<QueueProvider>().fetchInitialQueue(),
        ),
      QueueState.empty => const QueueEmptyWidget(),
      QueueState.loaded ||
      QueueState.refreshing ||
      QueueState.loadingMore =>
        RefreshIndicator(
          onRefresh: () => context.read<QueueProvider>().refresh(),
          child: _buildList(context, provider),
        ),
    };
  }

  Widget _buildList(BuildContext context, QueueProvider provider) {
    if (provider.clients.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          QueueEmptyWidget(),
        ],
      );
    }

    final showFooter = provider.hasMore || provider.isLoadingMore;

    return ListView.builder(
      key: const Key('queue-list'),
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: provider.clients.length + (showFooter ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == provider.clients.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: provider.isLoadingMore
                  ? const CircularProgressIndicator()
                  : OutlinedButton(
                      key: const Key('load-more-button'),
                      onPressed: () =>
                          context.read<QueueProvider>().loadMore(),
                      child: const Text('Load more'),
                    ),
            ),
          );
        }

        final client = provider.clients[index];
        return ClientCard(
          client: client,
          onDelete: () =>
              context.read<QueueProvider>().removeClient(client.id),
        );
      },
    );
  }
}

class _DemoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.amber.shade100,
      padding: const EdgeInsets.all(10),
      child: const Text(
        'Demo mode: registrations are stored locally and synchronized in memory.',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _QueueErrorWidget extends StatelessWidget {
  const _QueueErrorWidget({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              key: const Key('retry-button'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
