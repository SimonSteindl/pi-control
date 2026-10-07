import 'dart:convert';

import 'package:flutter/material.dart';

import 'auth.dart';

const permissionOptions = <PermissionOption>[
  PermissionOption(
    id: 'dashboard_view',
    title: 'Dashboard',
    description: 'Systemstatus, Temperatur und Speicher ansehen',
    icon: Icons.space_dashboard_outlined,
  ),
  PermissionOption(
    id: 'files_view',
    title: 'Dateien ansehen',
    description: 'Ordner öffnen und Dateien herunterladen',
    icon: Icons.folder_open_outlined,
  ),
  PermissionOption(
    id: 'files_upload',
    title: 'Dateien hochladen',
    description: 'Neue Dateien auf den NAS-Speicher laden',
    icon: Icons.upload_file_outlined,
  ),
  PermissionOption(
    id: 'files_manage',
    title: 'Dateien verwalten',
    description: 'Ordner erstellen, umbenennen und löschen',
    icon: Icons.drive_file_move_outline,
  ),
  PermissionOption(
    id: 'system_control',
    title: 'System steuern',
    description: 'Pi und Systemdienste neu starten',
    icon: Icons.settings_remote_outlined,
  ),
  PermissionOption(
    id: 'benchmark_run',
    title: 'Benchmark starten',
    description: 'CPU-Leistungstest ausführen',
    icon: Icons.speed_outlined,
  ),
  PermissionOption(
    id: 'users_manage',
    title: 'Benutzer verwalten',
    description: 'Konten und Zugriffsrechte bearbeiten',
    icon: Icons.manage_accounts_outlined,
  ),
  PermissionOption(
    id: 'terminal_access',
    title: 'Web-Terminal',
    description: 'Befehle am Pi ausführen · nur für Administratoren',
    icon: Icons.terminal_outlined,
    adminOnly: true,
  ),
];

class UserAdminView extends StatefulWidget {
  final PiApiClient client;
  final AuthSession session;
  final ValueChanged<AuthSession> onSessionUpdated;
  final Color accentColor;

  const UserAdminView({
    super.key,
    required this.client,
    required this.session,
    required this.onSessionUpdated,
    required this.accentColor,
  });

  @override
  State<UserAdminView> createState() => _UserAdminViewState();
}

class _UserAdminViewState extends State<UserAdminView> {
  List<ManagedUser> _users = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await widget.client.get('admin/users');
      if (response.statusCode != 200) {
        throw widget.client.responseException(response);
      }

      final decoded = widget.client.decodeObject(response);
      final rawUsers = decoded['users'];
      if (rawUsers is! List) throw const ApiException('Ungültige Antwort.');

      final users = rawUsers
          .whereType<Map>()
          .map(ManagedUser.fromJson)
          .toList();

      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _createUser() async {
    final draft = await showDialog<UserDraft>(
      context: context,
      builder: (context) => const UserEditorDialog(),
    );
    if (draft == null) return;

    await _saveRequest(
      () => widget.client.post(
        'admin/users',
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(draft.toJson()),
      ),
      success: 'Benutzer „${draft.username}“ wurde angelegt.',
    );
  }

  Future<void> _editUser(ManagedUser user) async {
    final draft = await showDialog<UserDraft>(
      context: context,
      builder: (context) => UserEditorDialog(user: user),
    );
    if (draft == null) return;

    await _saveRequest(
      () => widget.client.patch(
        'admin/users/${user.id}',
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(draft.toJson()),
      ),
      success: 'Benutzer „${draft.username}“ wurde gespeichert.',
      editedUserId: user.id,
    );
  }

  Future<void> _saveRequest(
    Future<dynamic> Function() request, {
    required String success,
    int? editedUserId,
  }) async {
    try {
      final response = await request();
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw widget.client.responseException(response);
      }

      final decoded = widget.client.decodeObject(response);
      final user = decoded['user'];
      if (editedUserId == widget.session.userId && user is Map) {
        widget.onSessionUpdated(
          AuthSession.fromJson(widget.session.token, user),
        );
      }

      _showMessage(success);
      await _load();
    } catch (error) {
      _showMessage(error.toString());
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeUsers = _users.where((user) => user.isActive).length;
    final admins = _users.where((user) => user.isAdmin).length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          widget.accentColor.withValues(alpha: 0.94),
                          scheme.tertiary.withValues(alpha: 0.78),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Wrap(
                      spacing: 18,
                      runSpacing: 18,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.admin_panel_settings_rounded,
                              color: Colors.white,
                              size: 38,
                            ),
                            SizedBox(width: 14),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Admin-Panel',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 25,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  'Konten und Zugriffsrechte verwalten',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                          ],
                        ),
                        FilledButton.icon(
                          onPressed: _createUser,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF10182A),
                          ),
                          icon: const Icon(Icons.person_add_alt_1_rounded),
                          label: const Text('Benutzer hinzufügen'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryCard(
                          label: 'Konten',
                          value: '${_users.length}',
                          icon: Icons.people_alt_outlined,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SummaryCard(
                          label: 'Aktiv',
                          value: '$activeUsers',
                          icon: Icons.verified_user_outlined,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SummaryCard(
                          label: 'Admins',
                          value: '$admins',
                          icon: Icons.shield_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(42),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null)
                    Card(
                      color: scheme.errorContainer,
                      child: ListTile(
                        leading: const Icon(Icons.error_outline),
                        title: Text(_error!),
                        trailing: TextButton(
                          onPressed: _load,
                          child: const Text('Nochmal'),
                        ),
                      ),
                    )
                  else
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (var index = 0; index < _users.length; index++)
                            Column(
                              children: [
                                _UserTile(
                                  user: _users[index],
                                  isCurrent:
                                      _users[index].id == widget.session.userId,
                                  onEdit: () => _editUser(_users[index]),
                                ),
                                if (index != _users.length - 1)
                                  const Divider(height: 1, indent: 76),
                              ],
                            ),
                        ],
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
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 9),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final ManagedUser user;
  final bool isCurrent;
  final VoidCallback onEdit;

  const _UserTile({
    required this.user,
    required this.isCurrent,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: user.isActive
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        child: Text(
          user.displayName.isEmpty ? '?' : user.displayName[0].toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      title: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            user.displayName,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (isCurrent) const _UserBadge(text: 'Du'),
          if (user.isAdmin) const _UserBadge(text: 'Admin', admin: true),
          if (!user.isActive) const _UserBadge(text: 'Gesperrt', blocked: true),
        ],
      ),
      subtitle: Text(
        '@${user.username}  •  ${user.isAdmin ? 'Alle Rechte' : '${user.permissions.length} Rechte'}'
        '  •  ${user.isAdmin ? 'Gesamter NAS' : (user.storagePath.isEmpty ? 'NAS /' : user.storagePath)}'
        '  •  ${user.storageQuotaBytes == null ? 'Unbegrenzt' : _formatQuota(user.storageQuotaBytes!)}'
        '${user.mustChangePassword ? '  •  Passwortwechsel offen' : ''}',
      ),
      trailing: IconButton.filledTonal(
        onPressed: onEdit,
        tooltip: 'Bearbeiten',
        icon: const Icon(Icons.edit_outlined),
      ),
    );
  }

  String _formatQuota(int bytes) {
    final gb = bytes / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(gb < 10 ? 1 : 0)} GB';
  }
}

class _UserBadge extends StatelessWidget {
  final String text;
  final bool admin;
  final bool blocked;

  const _UserBadge({
    required this.text,
    this.admin = false,
    this.blocked = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = blocked
        ? Colors.redAccent
        : admin
        ? Colors.amber
        : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class UserEditorDialog extends StatefulWidget {
  final ManagedUser? user;

  const UserEditorDialog({super.key, this.user});

  @override
  State<UserEditorDialog> createState() => _UserEditorDialogState();
}

class _UserEditorDialogState extends State<UserEditorDialog> {
  late final TextEditingController _usernameController;
  late final TextEditingController _displayNameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _storagePathController;
  late final TextEditingController _storageQuotaController;
  final _formKey = GlobalKey<FormState>();
  late bool _isAdmin;
  late bool _isActive;
  late Set<String> _permissions;
  bool _obscurePassword = true;

  bool get _editing => widget.user != null;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _usernameController = TextEditingController(text: user?.username ?? '');
    _displayNameController = TextEditingController(
      text: user?.displayName ?? '',
    );
    _passwordController = TextEditingController();
    _storagePathController = TextEditingController(
      text: user == null
          ? ''
          : user.storagePath.isEmpty
          ? '/'
          : user.storagePath,
    );
    final quotaGb = user?.storageQuotaBytes == null
        ? 0.0
        : user!.storageQuotaBytes! / (1024 * 1024 * 1024);
    _storageQuotaController = TextEditingController(
      text: user == null
          ? '5'
          : quotaGb == quotaGb.roundToDouble()
          ? quotaGb.toStringAsFixed(0)
          : quotaGb.toStringAsFixed(2),
    );
    _isAdmin = user?.isAdmin ?? false;
    _isActive = user?.isActive ?? true;
    _permissions = Set<String>.from(
      user?.permissions ?? const {'dashboard_view'},
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    _storagePathController.dispose();
    _storageQuotaController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final username = _usernameController.text.trim();
    final rawStoragePath = _storagePathController.text.trim();
    final quotaGb = double.tryParse(
      _storageQuotaController.text.trim().replaceAll(',', '.'),
    );
    Navigator.of(context).pop(
      UserDraft(
        username: username,
        displayName: _displayNameController.text.trim(),
        password: _passwordController.text,
        isAdmin: _isAdmin,
        isActive: _isActive,
        permissions: _isAdmin
            ? permissionOptions.map((option) => option.id).toSet()
            : _permissions,
        storagePath: _isAdmin
            ? ''
            : rawStoragePath.isEmpty
            ? 'users/$username'
            : rawStoragePath == '/'
            ? ''
            : rawStoragePath,
        storageQuotaBytes: _isAdmin || quotaGb == null || quotaGb == 0
            ? null
            : (quotaGb * 1024 * 1024 * 1024).round(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editing ? 'Benutzer bearbeiten' : 'Benutzer hinzufügen'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Benutzername',
                    prefixText: '@',
                  ),
                  validator: (value) => value == null || value.trim().length < 3
                      ? 'Mindestens 3 Zeichen verwenden'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(labelText: 'Anzeigename'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Anzeigename eingeben'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: _editing
                        ? 'Neues Passwort (optional)'
                        : 'Einmal-Passwort',
                    helperText: _editing
                        ? 'Leer lassen, wenn es gleich bleiben soll'
                        : 'Der Benutzer muss es beim ersten Login ändern',
                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (!_editing && (value == null || value.length < 10)) {
                      return 'Mindestens 10 Zeichen verwenden';
                    }
                    if (_editing &&
                        value != null &&
                        value.isNotEmpty &&
                        value.length < 10) {
                      return 'Mindestens 10 Zeichen verwenden';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isAdmin,
                  onChanged: (value) => setState(() => _isAdmin = value),
                  title: const Text('Administrator'),
                  subtitle: const Text('Erhält automatisch alle Rechte'),
                  secondary: const Icon(Icons.admin_panel_settings_outlined),
                ),
                if (_editing)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _isActive,
                    onChanged: (value) => setState(() => _isActive = value),
                    title: const Text('Konto aktiv'),
                    subtitle: const Text(
                      'Gesperrte Benutzer können sich nicht anmelden',
                    ),
                    secondary: const Icon(Icons.verified_user_outlined),
                  ),
                const Divider(height: 26),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Dateispeicher',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _storagePathController,
                  enabled: !_isAdmin,
                  decoration: InputDecoration(
                    labelText: 'Erlaubter NAS-Ordner',
                    hintText:
                        'users/${_usernameController.text.trim().isEmpty ? 'benutzername' : _usernameController.text.trim()}',
                    prefixIcon: const Icon(Icons.folder_shared_outlined),
                    helperText: _isAdmin
                        ? 'Administratoren sehen immer den gesamten NAS.'
                        : '„/“ erlaubt den gesamten NAS. Der Ordner wird automatisch erstellt.',
                  ),
                  validator: (value) {
                    if (_isAdmin) return null;
                    final normalized = (value ?? '').replaceAll('\\', '/');
                    if (normalized.split('/').contains('..')) {
                      return '„..“ ist im Ordnerpfad nicht erlaubt';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _storageQuotaController,
                  enabled: !_isAdmin,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Speicherlimit in GB',
                    prefixIcon: const Icon(Icons.data_usage_rounded),
                    helperText: _isAdmin
                        ? 'Administratoren haben kein Speicherlimit.'
                        : '0 bedeutet unbegrenzt. Beispiel: 2,5 GB',
                  ),
                  validator: (value) {
                    if (_isAdmin) return null;
                    final number = double.tryParse(
                      (value ?? '').trim().replaceAll(',', '.'),
                    );
                    if (number == null || number < 0 || number > 102400) {
                      return 'Bitte 0 bis 102400 GB eingeben';
                    }
                    return null;
                  },
                ),
                const Divider(height: 26),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Zugriffsrechte',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 6),
                for (final option in permissionOptions)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: option.adminOnly
                        ? _isAdmin
                        : _isAdmin ||
                              option.id == 'dashboard_view' ||
                              _permissions.contains(option.id),
                    onChanged:
                        _isAdmin ||
                            option.adminOnly ||
                            option.id == 'dashboard_view'
                        ? null
                        : (value) {
                            setState(() {
                              if (value == true) {
                                _permissions.add(option.id);
                              } else {
                                _permissions.remove(option.id);
                              }
                            });
                          },
                    secondary: Icon(option.icon),
                    title: Text(option.title),
                    subtitle: Text(option.description),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Speichern'),
        ),
      ],
    );
  }
}

class ManagedUser {
  final int id;
  final String username;
  final String displayName;
  final bool isAdmin;
  final bool isActive;
  final bool mustChangePassword;
  final Set<String> permissions;
  final String storagePath;
  final int? storageQuotaBytes;

  const ManagedUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.isAdmin,
    required this.isActive,
    required this.mustChangePassword,
    required this.permissions,
    required this.storagePath,
    required this.storageQuotaBytes,
  });

  factory ManagedUser.fromJson(Map<dynamic, dynamic> json) {
    final rawPermissions = json['permissions'];
    return ManagedUser(
      id: (json['id'] as num?)?.toInt() ?? 0,
      username: json['username']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? 'Benutzer',
      isAdmin: json['is_admin'] == true,
      isActive: json['is_active'] != false,
      mustChangePassword: json['must_change_password'] == true,
      permissions: rawPermissions is List
          ? rawPermissions.map((value) => value.toString()).toSet()
          : <String>{},
      storagePath: json['storage_path']?.toString() ?? '',
      storageQuotaBytes: json['storage_quota_bytes'] is num
          ? (json['storage_quota_bytes'] as num).toInt()
          : null,
    );
  }
}

class UserDraft {
  final String username;
  final String displayName;
  final String password;
  final bool isAdmin;
  final bool isActive;
  final Set<String> permissions;
  final String storagePath;
  final int? storageQuotaBytes;

  const UserDraft({
    required this.username,
    required this.displayName,
    required this.password,
    required this.isAdmin,
    required this.isActive,
    required this.permissions,
    required this.storagePath,
    required this.storageQuotaBytes,
  });

  Map<String, dynamic> toJson() => {
    'username': username,
    'display_name': displayName,
    if (password.isNotEmpty) 'password': password,
    'is_admin': isAdmin,
    'is_active': isActive,
    'permissions': permissions.toList()..sort(),
    'storage_path': storagePath,
    'storage_quota_bytes': storageQuotaBytes,
  };
}

class PermissionOption {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final bool adminOnly;

  const PermissionOption({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    this.adminOnly = false,
  });
}
