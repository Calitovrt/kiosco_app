import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dashboard_screen.dart';
import 'sales_screen.dart';
import 'students_screen.dart';
import 'products_screen.dart';
import 'reports_screen.dart';
import 'pending_screen.dart';
import 'chat_inbox_screen.dart';
import 'admin_screen.dart';
import 'login_screen.dart';
import 'config_screen.dart';
import 'student_login_screen.dart';
import 'student_qr_scanner_screen.dart';
import 'admin_orders_screen.dart';
import '../services/exporter.dart';

import '../services/store_config.dart';
import '../services/theme_provider.dart';
import '../services/responsive.dart';
import 'dart:async';
import '../services/supabase_service.dart';


class HomeScreen extends StatefulWidget {

  final String username;
  final String role;

  const HomeScreen({
    super.key,
    required this.username,
    required this.role,
  });

  @override
  State<HomeScreen> createState() =>
      _HomeScreenState();
}

class _HomeScreenState
    extends State<HomeScreen> {

  int selectedIndex = 0;
  int activeOrders = 0;
  int pendingCaptures = 0;
  Set<String> _knownCaptureIds = {};
  bool _capturesReady = false;
  StreamSubscription? _ordersSub;
  StreamSubscription? _capturesSub;
  double _fabX = 0;
  double _fabY = 0;
  bool _fabInit = false;

  bool get isSuperAdmin => widget.role == 'super_admin';

  @override
  void initState() {
    super.initState();
    _ordersSub = SupabaseService.instance.streamActiveOrdersCount().listen((active) {
      if (mounted) {
        if (active > activeOrders) {
          HapticFeedback.heavyImpact();
        }
        setState(() => activeOrders = active);
      }
    });

    // Badge del chat + aviso cuando el alumno escribe.
    // El primer load no notifica: solo marca lo que ya existia.
    _capturesSub = SupabaseService.instance.streamMessages().listen((data) {
      if (!mounted) return;

      final unreadStudents = <String>{};
      for (final m in data) {
        if (m['sender'] == 'alumno' && m['read_at'] == null) {
          unreadStudents.add(m['student_id'].toString());
        }
      }

      final ids = data
          .map((m) => m['id']?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toSet();

      if (_capturesReady) {
        final fresh = data.where((m) {
          final id = m['id']?.toString();
          return m['sender'] == 'alumno' &&
              id != null &&
              !_knownCaptureIds.contains(id);
        }).toList();

        if (fresh.isNotEmpty) {
          final names = fresh
              .map((m) => (m['student'] ?? '').toString())
              .where((n) => n.isNotEmpty && n != 'Alumno')
              .toSet()
              .toList();

          final text = names.isEmpty
              ? 'Llegó un mensaje nuevo'
              : names.length == 1
                  ? '${names.first} te escribió'
                  : '${names.length} alumnos te escribieron';

          HapticFeedback.heavyImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(text),
              backgroundColor: Colors.green.shade700,
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }

      _knownCaptureIds = ids;
      _capturesReady = true;
      setState(() => pendingCaptures = unreadStudents.length);
    });

    ThemeProvider.instance.addListener(_refresh);
  }

  @override
  void dispose() {
    _ordersSub?.cancel();
    _capturesSub?.cancel();
    ThemeProvider.instance.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {

    setState(() {});
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollCtrl) => SingleChildScrollView(
            controller: scrollCtrl,
            padding: EdgeInsets.fromLTRB(
              R.sp(context, 24),
              R.sp(context, 16),
              R.sp(context, 24),
              R.sp(context, 32),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              SizedBox(height: R.sp(context, 20)),

              Row(
                children: [
                  CircleAvatar(
                    child: Icon(LucideIcons.user, size: R.sp(context, 28)),
                  ),
                  SizedBox(width: R.sp(context, 16)),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.username,
                        style: TextStyle(
                          fontSize: R.fs(context, 20),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        isSuperAdmin ? 'Super Admin' : 'Administrador',
                        style: TextStyle(
                          fontSize: R.fs(context, 16),
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              SizedBox(height: R.sp(context, 24)),
              const Divider(),
              SizedBox(height: R.sp(context, 8)),

              ListTile(
                leading: const Icon(LucideIcons.lock),
                title: const Text('Cambiar contraseña'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showChangePassword();
                },
              ),

              ListTile(
                leading: const Icon(Icons.admin_panel_settings),
                title: const Text('Gestionar administradores'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AdminScreen()),
                  );
                },
              ),

              if (isSuperAdmin)
                ListTile(
                  leading: const Icon(Icons.store),
                  title: const Text('Configuración de tienda'),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ConfigScreen()),
                    );
                  },
                ),

              ListTile(
                leading: const Icon(Icons.backup),
                title: const Text('Exportar todo'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  exportBackupToExcel(context);
                },
              ),

              ListTile(
                leading: const Icon(LucideIcons.school, color: Color(0xFF2563EB)),
                title: const Text('Portal del Alumno'),
                subtitle: const Text('Los estudiantes pueden comprar'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StudentLoginScreen()),
                  );
                },
              ),

              ListTile(
                leading: const Icon(LucideIcons.scan, color: Color(0xFF7C3AED)),
                title: const Text('Escanear QR'),
                subtitle: const Text('Ver pedidos de un alumno'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StudentQrScannerScreen()),
                  );
                },
              ),

              ListTile(
                leading: const Icon(LucideIcons.logOut, color: Colors.red),
                title: const Text('Cerrar sesión', style: TextStyle(color: Colors.red)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  // Cerrar sesion de verdad: sin signOut() el JWT de Supabase
                  // sigue vivo y persistido, y el "logout" es solo visual.
                  try {
                    await SupabaseService.instance.logoutAdmin();
                  } catch (_) {
                    // signOut() ya limpio la sesion del dispositivo antes de
                    // fallar el revoke remoto. Navegar igual: si no, el usuario
                    // queda en una pantalla autenticada sin sesion.
                  }
                  if (!mounted) return;
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (_) => false,
                  );
                },
              ),
            ],
          ),
        ),
      );
    },
    );
  }

  void _showChangePassword() {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambiar contraseña'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Contraseña actual',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Nueva contraseña',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirmar nueva contraseña',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (newCtrl.text != confirmCtrl.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Las contraseñas no coinciden'), backgroundColor: Colors.red),
                );
                return;
              }
              if (newCtrl.text.length < 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Mínimo 4 caracteres'), backgroundColor: Colors.red),
                );
                return;
              }
              try {
                final ok = await SupabaseService.instance.changePassword(
                  widget.username,
                  oldCtrl.text,
                  newCtrl.text,
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? 'Contraseña cambiada' : 'Contraseña actual incorrecta'),
                    backgroundColor: ok ? Colors.green : Colors.red,
                  ),
                );
              } catch (e) {
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    final screens = [

      const DashboardScreen(),

      SalesScreen(),

      const StudentsScreen(),

      const ProductsScreen(),

      const ReportsScreen(),

      const PendingScreen(),
      const ChatInboxScreen(),

    ];

    return Scaffold(

      body: LayoutBuilder(
        builder: (context, constraints) {
          if (!_fabInit) {
            _fabX = constraints.maxWidth - 72;
            _fabY = constraints.maxHeight - 190;
            _fabInit = true;
          }
          return Stack(
            children: [
              screens[selectedIndex],
              Positioned(
                left: _fabX,
                top: _fabY,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _fabX = (_fabX + details.delta.dx).clamp(0, constraints.maxWidth - 56);
                      _fabY = (_fabY + details.delta.dy).clamp(0, constraints.maxHeight - 56);
                    });
                  },
                  child: Badge(
                    isLabelVisible: activeOrders > 0,
                    label: Text('$activeOrders', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                    backgroundColor: Colors.red,
                    textStyle: const TextStyle(color: Colors.white),
                    child: FloatingActionButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AdminOrdersScreen()),
                      ),
                      tooltip: 'Pedidos del día',
                      child: const Icon(LucideIcons.clipboardList),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),

      bottomNavigationBar:
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment:
            MainAxisAlignment.end,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  right: 8,
                  bottom: 4,
                ),
                child: IconButton(
                  icon: const Icon(LucideIcons.settings),
                  onPressed: _showSettings,
                  tooltip: 'Configuración',
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  right: 12,
                  bottom: 4,
                ),
                child: IconButton(
                  icon: Icon(ThemeProvider.instance.isDark ? LucideIcons.moon : LucideIcons.sun),
                  onPressed: () {
                    ThemeProvider
                        .instance
                        .toggle();
                  },
                  tooltip: 'Modo oscuro',
                ),
              ),
            ],
          ),
          NavigationBar(

        selectedIndex: selectedIndex,

        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,

        onDestinationSelected:
            (index) async {

          setState(() {

            selectedIndex = index;
          });

          // El badge del chat se recalcula contra la base al cambiar de
          // pestaña: no depende solo de que llegue el evento de Realtime.
          try {
            final unread = await SupabaseService.instance.countUnreadConversations();
            if (mounted) setState(() => pendingCaptures = unread);
          } catch (_) {
            // Si falla, se mantiene el valor anterior.
          }
        },

        destinations: [

          NavigationDestination(icon: Icon(LucideIcons.home), label: 'Inicio'),
          NavigationDestination(icon: Icon(LucideIcons.shoppingBag), label: 'Ventas'),
          NavigationDestination(icon: Icon(LucideIcons.users), label: StoreConfig.instance.entityPlural),
          NavigationDestination(icon: Icon(LucideIcons.package), label: 'Productos'),
          NavigationDestination(icon: Icon(LucideIcons.chartBar), label: 'Reportes'),
          NavigationDestination(icon: Icon(LucideIcons.clock), label: 'Pendientes'),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: pendingCaptures > 0,
              label: Text(
                '$pendingCaptures',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              backgroundColor: Colors.red,
              textStyle: const TextStyle(color: Colors.white),
              child: Icon(LucideIcons.messageCircle),
            ),
            label: 'Mensajes',
          ),
        ],
      ),
        ],
      ),
    );
  }
}