import 'dart:convert';

import 'package:flutter/material.dart';

import 'auth.dart';

class LoginScreen extends StatefulWidget {
  final PiApiClient client;
  final ValueChanged<AuthSession> onLoggedIn;
  final Color accentColor;

  const LoginScreen({
    super.key,
    required this.client,
    required this.onLoggedIn,
    required this.accentColor,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _obscurePassword = true;
  bool _rememberMe = true;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loading || !_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final session = await widget.client.login(
        _usernameController.text.trim(),
        _passwordController.text,
        rememberMe: _rememberMe,
      );
      widget.onLoggedIn(session);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.8, -0.8),
                  radius: 1.45,
                  colors: [
                    widget.accentColor.withValues(alpha: 0.28),
                    const Color(0xFF0A0F1C),
                    const Color(0xFF070B14),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: -100,
            top: -120,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.tertiary.withValues(alpha: 0.08),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 760;
                      final intro = _LoginIntro(
                        accentColor: widget.accentColor,
                      );
                      final form = _LoginCard(
                        formKey: _formKey,
                        usernameController: _usernameController,
                        passwordController: _passwordController,
                        loading: _loading,
                        obscurePassword: _obscurePassword,
                        rememberMe: _rememberMe,
                        error: _error,
                        onTogglePassword: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                        onLogin: _login,
                        onRememberMeChanged: (value) {
                          setState(() {
                            _rememberMe = value;
                          });
                        },
                      );

                      if (wide) {
                        return Row(
                          children: [
                            Expanded(child: intro),
                            const SizedBox(width: 46),
                            SizedBox(width: 410, child: form),
                          ],
                        );
                      }

                      return Column(
                        children: [intro, const SizedBox(height: 28), form],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginIntro extends StatelessWidget {
  final Color accentColor;

  const _LoginIntro({required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [accentColor, Theme.of(context).colorScheme.tertiary],
            ),
            borderRadius: BorderRadius.circular(21),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.28),
                blurRadius: 30,
              ),
            ],
          ),
          child: const Icon(
            Icons.developer_board_rounded,
            color: Colors.white,
            size: 34,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Stoneys\nRaspberry Pi',
          style: TextStyle(
            fontSize: 42,
            height: 0.98,
            letterSpacing: -1.4,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Dein geschützter Zugang zu Systemstatus, Dateien und Administration.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 16,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 22),
        const Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _FeatureChip(icon: Icons.shield_outlined, text: 'Sicherer Login'),
            _FeatureChip(icon: Icons.people_outline, text: 'Mehrbenutzer'),
            _FeatureChip(icon: Icons.tune_rounded, text: 'Eigene Rechte'),
          ],
        ),
      ],
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FeatureChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17),
          const SizedBox(width: 7),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool loading;
  final bool obscurePassword;
  final bool rememberMe;
  final String? error;
  final VoidCallback onTogglePassword;
  final VoidCallback onLogin;
  final ValueChanged<bool> onRememberMeChanged;

  const _LoginCard({
    required this.formKey,
    required this.usernameController,
    required this.passwordController,
    required this.loading,
    required this.obscurePassword,
    required this.rememberMe,
    required this.error,
    required this.onTogglePassword,
    required this.onLogin,
    required this.onRememberMeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Willkommen zurück',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                'Melde dich an, um Pi Control zu öffnen.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: usernameController,
                autofocus: true,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(
                  labelText: 'Benutzername',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Benutzername eingeben'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: passwordController,
                obscureText: obscurePassword,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => onLogin(),
                decoration: InputDecoration(
                  labelText: 'Passwort',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: onTogglePassword,
                    icon: Icon(
                      obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Passwort eingeben' : null,
              ),
              const SizedBox(height: 6),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: rememberMe,
                onChanged: loading
                    ? null
                    : (value) => onRememberMeChanged(value == true),
                title: const Text('Angemeldet bleiben'),
                subtitle: const Text(
                  'Auf diesem Gerät bis zu 30 Tage eingeloggt bleiben',
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline, size: 20),
                      const SizedBox(width: 9),
                      Expanded(child: Text(error!)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: loading ? null : onLogin,
                icon: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login_rounded),
                label: Text(loading ? 'Anmeldung läuft …' : 'Anmelden'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PasswordChangeScreen extends StatefulWidget {
  final PiApiClient client;
  final AuthSession session;
  final ValueChanged<AuthSession> onChanged;
  final VoidCallback onLogout;

  const PasswordChangeScreen({
    super.key,
    required this.client,
    required this.session,
    required this.onChanged,
    required this.onLogout,
  });

  @override
  State<PasswordChangeScreen> createState() => _PasswordChangeScreenState();
}

class PasswordChangeDialog extends StatefulWidget {
  final PiApiClient client;
  final AuthSession session;

  const PasswordChangeDialog({
    super.key,
    required this.client,
    required this.session,
  });

  @override
  State<PasswordChangeDialog> createState() => _PasswordChangeDialogState();
}

class _PasswordChangeDialogState extends State<PasswordChangeDialog> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await widget.client.post(
        'auth/password',
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'current_password': _currentController.text,
          'new_password': _newController.text,
        }),
      );
      if (response.statusCode != 200) {
        throw widget.client.responseException(response);
      }

      final user = widget.client.decodeObject(response)['user'];
      if (user is! Map) throw const ApiException('Ungültige Antwort.');
      if (!mounted) return;
      Navigator.of(context)
          .pop(AuthSession.fromJson(widget.session.token, user));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Passwort ändern'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _currentController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Aktuelles Passwort',
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'Aktuelles Passwort eingeben'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _newController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Neues Passwort',
                  helperText: 'Mindestens 10 Zeichen',
                ),
                validator: (value) => value == null || value.length < 10
                    ? 'Mindestens 10 Zeichen verwenden'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmController,
                obscureText: true,
                onFieldSubmitted: (_) => _save(),
                decoration: const InputDecoration(
                  labelText: 'Neues Passwort wiederholen',
                ),
                validator: (value) => value != _newController.text
                    ? 'Die Passwörter stimmen nicht überein'
                    : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _loading ? null : _save,
          child: Text(_loading ? 'Wird gespeichert …' : 'Speichern'),
        ),
      ],
    );
  }
}

class _PasswordChangeScreenState extends State<PasswordChangeScreen> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_loading || !_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await widget.client.post(
        'auth/password',
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'current_password': _currentController.text,
          'new_password': _newController.text,
        }),
      );
      if (response.statusCode != 200) {
        throw widget.client.responseException(response);
      }

      final decoded = widget.client.decodeObject(response);
      final user = decoded['user'];
      if (user is! Map) throw const ApiException('Ungültige Antwort.');
      widget.onChanged(AuthSession.fromJson(widget.session.token, user));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Passwort ändern'),
        actions: [
          TextButton.icon(
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Abmelden'),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.password_rounded, size: 48),
                      const SizedBox(height: 16),
                      const Text(
                        'Neues Passwort festlegen',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Das Einmal-Passwort muss vor der ersten Verwendung geändert werden.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _currentController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Aktuelles Einmal-Passwort',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? 'Aktuelles Passwort eingeben'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _newController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Neues Passwort',
                          helperText: 'Mindestens 10 Zeichen',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => value == null || value.length < 10
                            ? 'Mindestens 10 Zeichen verwenden'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _confirmController,
                        obscureText: true,
                        onFieldSubmitted: (_) => _save(),
                        decoration: const InputDecoration(
                          labelText: 'Neues Passwort wiederholen',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => value != _newController.text
                            ? 'Die Passwörter stimmen nicht überein'
                            : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ],
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        onPressed: _loading ? null : _save,
                        icon: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_rounded),
                        label: Text(
                          _loading
                              ? 'Wird gespeichert …'
                              : 'Passwort speichern',
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ],
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
