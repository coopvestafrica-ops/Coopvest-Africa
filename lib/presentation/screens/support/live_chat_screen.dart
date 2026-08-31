import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme_config.dart';
import '../../../config/theme_extension.dart';
import '../../../core/network/api_client.dart';

/// Live Chat Screen
///
/// Real-time-ish support chat backed by the support-ticket system: the first
/// time a member opens live chat we create a "Live Chat" ticket, then reuse it
/// for the conversation. Messages poll every few seconds; admins answer from
/// the admin portal's Support page and their replies appear here.
class LiveChatScreen extends ConsumerStatefulWidget {
  const LiveChatScreen({super.key});

  @override
  ConsumerState<LiveChatScreen> createState() => _LiveChatScreenState();
}

class _LiveChatScreenState extends ConsumerState<LiveChatScreen> {
  static const _chatTitle = 'Live Chat';
  static const _activeStatuses = {'open', 'in_progress', 'awaiting_user'};

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? _ticketId;
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeChat() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final dio = ApiClient().getDio();

      // Reuse the most recent still-active live chat ticket, if any.
      final listResponse = await dio.get('/tickets');
      final tickets = (listResponse.data['tickets'] as List?) ?? [];
      String? ticketId;
      for (final t in tickets) {
        if (t['title'] == _chatTitle && _activeStatuses.contains(t['status'])) {
          ticketId = t['id'] as String?;
          break;
        }
      }

      // Otherwise start a new live chat ticket.
      if (ticketId == null) {
        final createResponse = await dio.post('/tickets', data: {
          'title': _chatTitle,
          'description': 'Live chat session started',
          'category': 'other',
          'priority': 'medium',
        });
        ticketId = createResponse.data['ticket']?['id'] as String?;
      }

      if (ticketId == null) {
        throw Exception('Could not start a live chat session');
      }

      _ticketId = ticketId;
      await _fetchMessages();

      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _fetchMessages());

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Could not start live chat. Please try again.';
        });
      }
    }
  }

  Future<void> _fetchMessages() async {
    final ticketId = _ticketId;
    if (ticketId == null) return;
    try {
      final response = await ApiClient().getDio().get('/tickets/$ticketId');
      final messages = (response.data['messages'] as List?)
              ?.map((m) => Map<String, dynamic>.from(m as Map))
              .toList() ??
          [];
      if (mounted) {
        setState(() => _messages = messages);
        _scrollToBottom();
      }
    } catch (_) {
      // Polling failures are transient — keep the current thread on screen.
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    final ticketId = _ticketId;
    if (text.isEmpty || ticketId == null || _isSending) return;

    setState(() => _isSending = true);
    try {
      await ApiClient().getDio().post('/tickets/$ticketId/messages', data: {'content': text});
      _messageController.clear();
      await _fetchMessages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message failed to send. Please try again.'),
            backgroundColor: CoopvestColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldBackground,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Live Chat', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
            Text('Support team replies here', style: TextStyle(fontSize: 11, color: context.textSecondary)),
          ],
        ),
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: CoopvestColors.primary))
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_error!, style: TextStyle(color: context.textSecondary)),
                            const SizedBox(height: 12),
                            ElevatedButton(onPressed: _initializeChat, child: const Text('Retry')),
                          ],
                        ),
                      )
                    : _messages.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                'Hi! Send us a message and the support team will respond here.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: context.textSecondary),
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) => _buildBubble(_messages[index]),
                          ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: context.cardBackground,
                border: Border(top: BorderSide(color: context.dividerColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      textCapitalization: TextCapitalization.sentences,
                      minLines: 1,
                      maxLines: 4,
                      style: TextStyle(color: context.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: TextStyle(color: context.textSecondary),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: context.scaffoldBackground,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: CoopvestColors.primary,
                    child: IconButton(
                      icon: _isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send, color: Colors.white, size: 20),
                      onPressed: _isSending ? null : _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(Map<String, dynamic> message) {
    final isMine = message['senderType'] == 'user';
    final content = (message['content'] ?? message['body'] ?? '').toString();
    final createdAt = DateTime.tryParse((message['createdAt'] ?? '').toString());

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isMine ? CoopvestColors.primary : context.cardBackground,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMine)
              const Padding(
                padding: EdgeInsets.only(bottom: 2),
                child: Text('Support', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: CoopvestColors.primary)),
              ),
            Text(
              content,
              style: TextStyle(color: isMine ? Colors.white : context.textPrimary),
            ),
            if (createdAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 10,
                    color: isMine ? Colors.white70 : context.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
