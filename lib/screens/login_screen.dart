import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../widgets/ambient_background.dart';
import '../widgets/brand_mark.dart';
import '../services/animeon_api.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.onLogin,
    required this.onLoginWithCode,
    required this.onRegister,
  });

  final Future<void> Function(String email, String password) onLogin;
  final Future<void> Function(String code) onLoginWithCode;
  final Future<void> Function(
    String name,
    String email,
    String mobile,
    String password,
  )
  onRegister;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _registering = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _mobile.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      if (_registering) {
        await widget.onRegister(
          _name.text,
          _email.text,
          _mobile.text,
          _password.text,
        );
      } else {
        await widget.onLogin(_email.text, _password.text);
      }
    } on AnimeOnApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ورود انجام نشد؛ دوباره تلاش کن.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pasteAndLogin() async {
    if (_loading) return;
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final code = clipboard?.text?.trim() ?? '';
    if (code.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('کد ورودی در کلیپ‌بورد پیدا نشد.')),
        );
      }
      return;
    }
    setState(() => _loading = true);
    try {
      await widget.onLoginWithCode(code);
    } on AnimeOnApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ورود با کد انجام نشد.')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 24, end: 0),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) => Transform.translate(
                    offset: Offset(0, value),
                    child: child,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Align(
                          alignment: Alignment.centerRight,
                          child: BrandMark(size: 62),
                        ),
                        const SizedBox(height: 44),
                        Text(
                          _registering ? 'ساخت حساب' : 'خوش برگشتی',
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _registering
                              ? 'حساب MBNime خودت را بساز و مستقیم وارد برنامه شو.'
                              : 'برای ورود به آرشیو کامل فیلم‌ها و انیمه‌ها، وارد حساب خودت شو.',
                          style: const TextStyle(
                            color: AnimeColors.muted,
                            height: 1.8,
                          ),
                        ),
                        const SizedBox(height: 32),
                        if (_registering) ...[
                          TextFormField(
                            controller: _name,
                            decoration: const InputDecoration(
                              labelText: 'نام کاربری',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                            validator: (value) =>
                                (value?.trim().length ?? 0) < 2
                                ? 'نام کاربری را وارد کن'
                                : null,
                          ),
                          const SizedBox(height: 14),
                        ],
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textDirection: TextDirection.ltr,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'ایمیل',
                            hintText: 'name@example.com',
                            prefixIcon: Icon(Icons.alternate_email_rounded),
                          ),
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            if (!RegExp(
                              r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                            ).hasMatch(text)) {
                              return 'ایمیل معتبر وارد کن';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        if (_registering) ...[
                          TextFormField(
                            controller: _mobile,
                            keyboardType: TextInputType.phone,
                            textDirection: TextDirection.ltr,
                            decoration: const InputDecoration(
                              labelText: 'شماره همراه (اختیاری)',
                              prefixIcon: Icon(Icons.phone_android_rounded),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          textDirection: TextDirection.ltr,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: 'رمز عبور',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: Icon(
                                  _obscure
                                      ? Icons.visibility_rounded
                                      : Icons.visibility_off_rounded,
                                  key: ValueKey(_obscure),
                                ),
                              ),
                            ),
                          ),
                          validator: (value) => (value?.length ?? 0) < 4
                              ? 'رمز عبور باید حداقل ۴ نویسه باشد'
                              : null,
                        ),
                        if (_registering) ...[
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _confirmPassword,
                            obscureText: true,
                            textDirection: TextDirection.ltr,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: const InputDecoration(
                              labelText: 'تکرار رمز عبور',
                              prefixIcon: Icon(Icons.lock_reset_rounded),
                            ),
                            validator: (value) => value != _password.text
                                ? 'تکرار رمز عبور یکسان نیست'
                                : null,
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _loading ? null : _submit,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: _loading
                                ? const SizedBox(
                                    key: ValueKey('loading'),
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                    ),
                                  )
                                : Row(
                                    key: ValueKey('label'),
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        _registering
                                            ? 'ثبت‌نام و ورود'
                                            : 'ورود به MBNime',
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        _registering
                                            ? Icons.person_add_alt_1_rounded
                                            : Icons.arrow_back_rounded,
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => setState(() {
                                  _registering = !_registering;
                                  _formKey.currentState?.reset();
                                }),
                          child: Text(
                            _registering
                                ? 'حساب دارم؛ ورود'
                                : 'حساب ندارم؛ ثبت‌نام',
                          ),
                        ),
                        if (!_registering) ...[
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Text(
                                  'ورود با کد',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                              ),
                              const Expanded(child: Divider()),
                            ],
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            readOnly: true,
                            textDirection: TextDirection.ltr,
                            decoration: const InputDecoration(
                              labelText: 'کد ورود MBN1',
                              hintText: 'برای ورود، دکمه Paste را بزن',
                              prefixIcon: Icon(Icons.key_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _loading ? null : _pasteAndLogin,
                            icon: const Icon(Icons.content_paste_go_rounded),
                            label: const Text('Paste و ورود خودکار'),
                          ),
                        ],
                        const SizedBox(height: 18),
                        const Row(
                          children: [
                            Icon(
                              Icons.verified_user_outlined,
                              size: 18,
                              color: AnimeColors.cyan,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'بعد از ورود، همه بخش‌های برنامه بدون قفل اشتراک فعال هستند.',
                                style: TextStyle(
                                  color: AnimeColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
