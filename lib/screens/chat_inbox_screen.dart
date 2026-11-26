import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/supabase_service.dart';

/// Bandeja de chat del kiosco: un hilo por alumno, ordenado por el ultimo
/// mensaje. Reemplaza a la vieja pantalla de comprobantes.
class ChatInboxScreen extends StatefulWidget {
  const ChatInboxScreen({super.key});

  @override
  State<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _Conversation {
  _Conversation({required this.studentId, required this.name});

  final String studentId;
  String name;
  String lastBody = '';
  bool lastHasImage = false;
  DateTime? lastAt;
  int unread = 0;
}

class _ChatInboxScreenState extends State<ChatInboxScreen> {
  StreamSubscription? _sub;
  List<_Conversation> _conversations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _sub = SupabaseService.instance.streamMessages().listen(
      (data) {
        if (!mounted) return;
        setState(() {
          _conversations = _group(data);
          _loading = false;
        });
      },
      onError: (_) {
        if (mounted) setState(() => _loading = false);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  List<_Conversation> _group(List<Map<String, dynamic>> data) {
    final byId = <String, _Conversation>{};

    for (final m in data) {
      final id = m['student_id']?.toString();
      if (id == null || id.isEmpty) continue;

      final conv = byId.putIfAbsent(
        id,
        () => _Conversation(
          studentId: id,
          name: (m['student'] ?? 'Alumno').toString(),
        ),
      );
      conv.name = (m['student'] ?? conv.name).toString();

      final at = DateTime.tryParse(m['created_at']?.toString() ?? '');
      if (at != null && (conv.lastAt == null || at.isAfter(conv.lastAt!))) {
        conv.lastAt = at;
        conv.lastBody = (m['body'] as String? ?? '').trim();
        conv.lastHasImage = (m['image_path'] as String?)?.isNotEmpty ?? false;
      }

      if (m['sender'] == 'alumno' && m['read_at'] == null) conv.unread++;
    }

    final list = byId.values.toList()
      ..sort((a, b) => (b.lastAt ?? DateTime(2000))
          .compareTo(a.lastAt ?? DateTime(2000)));
    return list;
  }

  String _preview(_Conversation c) {
    if (c.lastBody.isNotEmpty) return c.lastBody;
    if (c.lastHasImage) return 'Comprobante adjunto';
    return 'Sin mensajes';
  }

  String _formatAt(DateTime? at) {
    if (at == null) return '';
    final local = at.toLocal();
    final now = DateTime.now();
    final hhmm =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (local.year == now.year && local.day == now.day && local.month == now.month) {
      return hhmm;
    }
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Mensajes')),
      body: _conversations.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.messageCircle, size: 48, color: cs.outline),
                    const SizedBox(height: 12),
                    const Text(
                      'Todavía no hay mensajes',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Cuando un alumno escriba o mande un comprobante, aparece acá.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.outline),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              itemCount: _conversations.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final c = _conversations[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: cs.primaryContainer,
                    child: Icon(LucideIcons.user, color: cs.onPrimaryContainer),
                  ),
                  title: Text(
                    c.name,
                    style: TextStyle(
                      fontWeight: c.unread > 0 ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    _preview(c),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: c.unread > 0 ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatAt(c.lastAt),
                        style: TextStyle(fontSize: 11, color: cs.outline),
                      ),
                      if (c.unread > 0) ...[
                        const SizedBox(height: 6),
                        Badge(
                          label: Text('${c.unread}'),
                          backgroundColor: Colors.red,
                          textColor: Colors.white,
                        ),
                      ],
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatThreadScreen(
                          studentId: c.studentId,
                          studentName: c.name,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

/// Hilo de mensajes con un alumno.
class ChatThreadScreen extends StatefulWidget {
  final String studentId;
  final String studentName;

  const ChatThreadScreen({
    super.key,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  StreamSubscription? _sub;
  List<Map<String, dynamic>> _messages = [];
  Uint8List? _selectedImage;
  String? _selectedName;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _sub = SupabaseService.instance.streamMessages().listen((all) {
      if (!mounted) return;
      final mine = all
          .where((m) => m['student_id']?.toString() == widget.studentId)
          .toList();

      final grew = mine.length != _messages.length;
      setState(() => _messages = mine);
      if (grew) _scrollToBottom();

      final hasUnread = mine.any(
        (m) => m['sender'] == 'alumno' && m['read_at'] == null,
      );
      if (hasUnread) {
        SupabaseService.instance.markConversationReadForAdmin(widget.studentId);
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    });
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _selectedImage = result.files.first.bytes;
      _selectedName = result.files.first.name;
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty && _selectedImage == null) return;

    setState(() => _sending = true);
    try {
      String? path;
      if (_selectedImage != null) {
        path = await SupabaseService.instance.uploadPaymentCapture(
          widget.studentId,
          _selectedName ?? 'adjunto.png',
          _selectedImage!,
        );
      }
      await SupabaseService.instance.sendAdminMessage(
        studentId: widget.studentId,
        body: text,
        imagePath: path,
      );
      if (!mounted) return;

      // Relectura explicita: no dependemos de que llegue el evento de Realtime
      // para ver lo que acabamos de mandar.
      final fresh =
          await SupabaseService.instance.getMessagesForStudent(widget.studentId);
      if (!mounted) return;
      setState(() => _messages = fresh);

      _ctrl.clear();
      setState(() {
        _selectedImage = null;
        _selectedName = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo enviar: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openImage(String path) async {
    final url = await SupabaseService.instance.getPaymentCaptureSignedUrl(path);
    if (!mounted) return;
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el adjunto')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: InteractiveViewer(
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No se pudo cargar la imagen'),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    final hhmm =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final sameDay = dt.year == now.year && dt.day == now.day && dt.month == now.month;
    if (sameDay) return hhmm;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} $hhmm';
  }

  Widget _bubble(Map<String, dynamic> m, ColorScheme cs) {
    final mine = m['sender'] == 'kiosco';
    final body = (m['body'] as String? ?? '').trim();
    final imagePath = m['image_path'] as String?;
    final hasImage = imagePath != null && imagePath.isNotEmpty;
    final fg = mine ? cs.onPrimary : cs.onSurface;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: mine ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (body.isNotEmpty) Text(body, style: TextStyle(color: fg)),
            if (hasImage) ...[
              if (body.isNotEmpty) const SizedBox(height: 6),
              InkWell(
                onTap: () => _openImage(imagePath),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.receiptText, size: 14, color: fg),
                    const SizedBox(width: 4),
                    Text(
                      'Ver comprobante',
                      style: TextStyle(
                        fontSize: 12,
                        color: fg,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 2),
            Text(
              _formatTime(m['created_at'] as String?),
              style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(widget.studentName)),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      'Sin mensajes todavía',
                      style: TextStyle(color: cs.outline),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) => _bubble(_messages[i], cs),
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(top: BorderSide(color: cs.outlineVariant)),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_selectedImage != null) ...[
                    Stack(
                      alignment: Alignment.topRight,
                      children: [
                        Container(
                          height: 80,
                          width: 80,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            image: DecorationImage(
                              image: MemoryImage(_selectedImage!),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() {
                            _selectedImage = null;
                            _selectedName = null;
                          }),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(4),
                            child: const Icon(Icons.close,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(LucideIcons.imagePlus),
                        tooltip: 'Adjuntar imagen',
                        onPressed: _sending ? null : _pickImage,
                      ),
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          minLines: 1,
                          maxLines: 3,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) {
                            if (!_sending) _send();
                          },
                          decoration: const InputDecoration(
                            hintText: 'Responder…',
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: _sending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(LucideIcons.send),
                        tooltip: 'Enviar',
                        onPressed: _sending ? null : _send,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
