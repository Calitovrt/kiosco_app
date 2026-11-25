import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/supabase_service.dart';

/// Chat libre entre el alumno (o su familia) y el kiosco.
///
/// Reemplaza al viejo "Enviar pago": la captura del comprobante es solo un
/// adjunto mas dentro de la conversacion, asi que se puede escribir
/// "esto es un abono de $200" y mandar la foto en el mismo mensaje.
class StudentPaymentChatScreen extends StatefulWidget {
  final Map<String, dynamic> student;

  const StudentPaymentChatScreen({super.key, required this.student});

  @override
  State<StudentPaymentChatScreen> createState() =>
      _StudentPaymentChatScreenState();
}

class _StudentPaymentChatScreenState extends State<StudentPaymentChatScreen> {
  final _supabase = SupabaseService.instance;
  final _messageCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  String _token = '';
  Uint8List? _selectedImage;
  String? _selectedName;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Timer? _poll;

  String get _studentId => widget.student['id'].toString();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      _token = await const FlutterSecureStorage().read(key: 'student_qr_token') ?? '';
    } catch (_) {
      _token = '';
    }
    await _load(showSpinner: true);

    // El alumno entra como anon: no tiene auth.uid(), asi que no puede usar
    // Realtime (las policies no lo distinguen de otro alumno). Se refresca
    // por polling mientras la pantalla esta abierta.
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  Future<void> _load({bool showSpinner = false}) async {
    if (showSpinner && mounted) setState(() => _loading = true);
    try {
      final data = await _supabase.getStudentMessages(
        studentId: _studentId,
        token: _token,
      );
      if (!mounted) return;

      final grew = data.length != _messages.length;
      setState(() {
        _messages = data;
        _loading = false;
        _error = null;
      });
      if (grew) _scrollToBottom();

      final hasUnreadFromKiosco = data.any(
        (m) => m['sender'] == 'kiosco' && m['read_at'] == null,
      );
      if (hasUnreadFromKiosco) {
        await _supabase.markStudentMessagesRead(
          studentId: _studentId,
          token: _token,
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error ??= 'No se pudo cargar el chat';
      });
    }
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
    final text = _messageCtrl.text.trim();
    if (text.isEmpty && _selectedImage == null) return;

    setState(() => _sending = true);
    try {
      String? path;
      if (_selectedImage != null) {
        path = await _supabase.uploadPaymentCapture(
          _studentId,
          _selectedName ?? 'captura.png',
          _selectedImage!,
        );
      }

      await _supabase.sendStudentMessage(
        studentId: _studentId,
        token: _token,
        body: text,
        imagePath: path,
      );

      if (!mounted) return;
      _messageCtrl.clear();
      setState(() {
        _selectedImage = null;
        _selectedName = null;
      });
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo enviar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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
    final mine = m['sender'] == 'alumno';
    final body = (m['body'] as String? ?? '').trim();
    final hasImage = (m['image_path'] as String?)?.isNotEmpty ?? false;
    final fg = mine ? cs.onPrimary : cs.onSurface;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 320),
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.receiptText, size: 14, color: fg),
                  const SizedBox(width: 4),
                  Text(
                    'Comprobante adjunto',
                    style: TextStyle(fontSize: 12, color: fg),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 2),
            Text(
              _formatTime(m['created_at'] as String?),
              style: TextStyle(
                fontSize: 10,
                color: fg.withValues(alpha: 0.7),
              ),
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
      appBar: AppBar(title: const Text('Chat con el kiosco')),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.wifiOff, size: 44, color: cs.outline),
                            const SizedBox(height: 12),
                            Text(_error!),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: () => _load(showSpinner: true),
                              child: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      )
                    : _messages.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(LucideIcons.messageCircle,
                                      size: 48, color: cs.outline),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Escribile al kiosco',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Podés preguntar por un pedido o mandar la captura de un pago.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: cs.outline),
                                  ),
                                ],
                              ),
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
                          height: 90,
                          width: 90,
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
                        tooltip: 'Adjuntar captura',
                        onPressed: _sending ? null : _pickImage,
                      ),
                      Expanded(
                        child: TextField(
                          controller: _messageCtrl,
                          minLines: 1,
                          maxLines: 3,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) {
                            if (!_sending) _send();
                          },
                          decoration: const InputDecoration(
                            hintText: 'Escribí un mensaje',
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
