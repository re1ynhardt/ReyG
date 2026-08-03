import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../providers/auth_provider.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController(text: '');
  final _password = TextEditingController(text: '');
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok = await auth.login(_email.text.trim(), _password.text);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.error ?? context.tr('login_error'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40),
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: CustomPaint(
                      painter: EqualizerLogoPainter(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.tr('app_name'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 40),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(labelText: context.tr('email')),
                    validator: (v) =>
                        (v == null || !v.contains('@')) ? context.tr('email') : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: context.tr('password'),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) => (v == null || v.length < 6) ? context.tr('password') : null,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: auth.busy ? null : _submit,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: auth.busy
                        ? const SizedBox(
                            height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(context.tr('login')),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RegisterScreen()),
                    ),
                    child: Text(context.tr('no_account')),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'version 1.5.3 \nby re1ynhardt',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  
}
class EqualizerLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 1. Принудительно удерживаем форму строгого квадрата по центру
    final double side = size.width < size.height ? size.width : size.height;
    final double offsetX = (size.width - side) / 2;
    final double offsetY = (size.height - side) / 2;

    // Создаем кисть с линейным синим градиентом слева направо внутри квадрата
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          const Color(0xFF0052D4), // Глубокий синий
          const Color(0xFF2196F3), // Яркий синий
          const Color(0xFF00F2FE), // Лазурно-неоновый
        ],
      ).createShader(Rect.fromLTWH(offsetX, offsetY, side, side))
      ..style = PaintingStyle.fill;

    // 2. Новая пропорция: зазор в 2.5 раза шире самой палочки (gap = colWidth * 2.5)
    // Формула: 4 * colWidth + 3 * (2.5 * colWidth) = 11.5 * colWidth
    final double colWidth = side / 11.5; 
    final double gap = colWidth * 2.5; // Палочки стали более выразительными, но не громоздкими

    // --- КОЛОНКА 1 (Слева) ---
    final double x1 = offsetX;
    canvas.drawRect(Rect.fromLTWH(x1, offsetY + 0, colWidth, side * 0.18), paint);
    canvas.drawRect(Rect.fromLTWH(x1, offsetY + side * 0.25, colWidth, side * 0.75), paint);

    // --- КОЛОНКА 2 ---
    final double x2 = x1 + colWidth + gap;
    canvas.drawRect(Rect.fromLTWH(x2, offsetY + 0, colWidth, side * 0.44), paint);
    canvas.drawRect(Rect.fromLTWH(x2, offsetY + side * 0.52, colWidth, side * 0.48), paint);

    // --- КОЛОНКА 3 ---
    final double x3 = x2 + colWidth + gap;
    canvas.drawRect(Rect.fromLTWH(x3, offsetY + 0, colWidth, side), paint);

    // --- КОЛОНКА 4 (Справа) ---
    final double x4 = x3 + colWidth + gap;
    canvas.drawRect(Rect.fromLTWH(x4, offsetY + 0, colWidth, side * 0.31), paint);
    canvas.drawRect(Rect.fromLTWH(x4, offsetY + side * 0.39, colWidth, side * 0.31), paint);
    canvas.drawRect(Rect.fromLTWH(x4, offsetY + side * 0.78, colWidth, side * 0.22), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
