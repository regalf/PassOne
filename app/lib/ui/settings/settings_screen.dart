import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/l10n.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../state/settings.dart';
import '../vault/totp_test_screen.dart';
import 'export.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final session = ref.watch(sessionControllerProvider);
    final notifier = ref.read(sessionControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: l10n.sectionGeneral,
            children: [
              ListTile(
                leading: const Icon(Icons.language),
                title: Text(l10n.language),
                trailing: DropdownButton<String>(
                  value: session.settings.languageCode ?? 'system',
                  underline: const SizedBox.shrink(),
                  onChanged: (v) =>
                      notifier.setLanguageCode(v == 'system' ? null : v),
                  items: [
                    DropdownMenuItem(
                        value: 'system', child: Text(l10n.languageSystem)),
                    DropdownMenuItem(value: 'it', child: Text(l10n.italian)),
                    DropdownMenuItem(value: 'en', child: Text(l10n.english)),
                  ],
                ),
              ),
            ],
          ),
          _Section(
            title: l10n.sectionServer,
            children: [
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: Text(l10n.serverAddress),
                subtitle: Text(session.settings.serverUrl.isEmpty
                    ? l10n.notConfigured
                    : session.settings.serverUrl),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _editServerUrl(context, ref),
              ),
            ],
          ),
          _Section(
            title: l10n.sectionSecurity,
            children: [
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(l10n.autoLock),
                subtitle: Text(l10n.autoLockSub(
                    _lockLabel(l10n, session.settings.lockTimeout))),
                trailing: DropdownButton<LockTimeout>(
                  value: session.settings.lockTimeout,
                  underline: const SizedBox.shrink(),
                  onChanged: (v) {
                    if (v == LockTimeout.always) {
                      _confirmAlways(context, notifier);
                    } else {
                      notifier.setLockTimeout(v!);
                    }
                  },
                  items: LockTimeout.values
                      .map((t) => DropdownMenuItem(
                          value: t, child: Text(_lockLabel(l10n, t))))
                      .toList(),
                ),
              ),
              if (defaultTargetPlatform == TargetPlatform.android)
                ListTile(
                  leading: const Icon(Icons.fingerprint),
                  title: Text(l10n.biometricAccess),
                  subtitle: Text(l10n.biometricSub),
                  trailing: Switch(
                    value: session.settings.biometricsEnabled,
                    onChanged: (v) => _toggleBiometrics(context, ref, v),
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.vpn_key_outlined),
                title: Text(l10n.recoveryKeyStatus),
                subtitle: Text(session.cache?.wrappedRecovery != null
                    ? l10n.active
                    : l10n.notActive),
                onTap: () => _manageRecovery(context, ref),
              ),
              ListTile(
                leading: const Icon(Icons.password),
                title: Text(l10n.changeMasterPassword),
                onTap: () => _changePassword(context, ref),
              ),
            ],
          ),
          const ImportExportSection(),
          _Section(
            title: l10n.sectionDeveloper,
            children: [
              ListTile(
                leading: const Icon(Icons.qr_code_2),
                title: Text(l10n.testTotp),
                subtitle: Text(l10n.testTotpSub),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const TotpTestScreen())),
              ),
            ],
          ),
          _Section(
            title: l10n.sectionSession,
            children: [
              ListTile(
                leading: const Icon(Icons.logout),
                title: Text(l10n.logout),
                subtitle: Text(l10n.logoutSub),
                onTap: () => notifier.logout(),
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: Text(l10n.logoutAll),
                subtitle: Text(l10n.logoutAllSub),
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(ctx.l10n.revokeAllTitle),
                      content: Text(ctx.l10n.revokeAllBody),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: Text(ctx.l10n.cancel)),
                        FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: Text(ctx.l10n.revoke)),
                      ],
                    ),
                  );
                  if (ok == true) notifier.logoutAll();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _lockLabel(AppLocalizations l10n, LockTimeout t) =>
      t == LockTimeout.always ? l10n.lockAlways : l10n.lockMinutes(t.minutes);

  Future<void> _toggleBiometrics(
      BuildContext context, WidgetRef ref, bool enable) async {
    final notifier = ref.read(sessionControllerProvider.notifier);
    try {
      if (enable) {
        await notifier.enableBiometrics();
      } else {
        await notifier.disableBiometrics();
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(enable
                ? context.l10n.biometricEnabled
                : context.l10n.biometricDisabled)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.biometricEnableFailed(e))));
      }
    }
  }

  Future<void> _editServerUrl(BuildContext context, WidgetRef ref) async {
    final current =
        ref.read(sessionControllerProvider).settings.serverUrl;
    final controller = TextEditingController(text: current);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.serverAddress),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: ctx.l10n.url,
            hintText: ctx.l10n.serverHint,
          ),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(), child: Text(ctx.l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: Text(ctx.l10n.save)),
        ],
      ),
    );
    if (url != null && url.isNotEmpty) {
      await ref.read(sessionControllerProvider.notifier).setServerUrl(url);
    }
  }

  Future<void> _confirmAlways(
      BuildContext context, SessionController notifier) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.alwaysKeepOpen),
        content: Text(ctx.l10n.alwaysKeepOpenWarning),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(ctx.l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(ctx.l10n.proceedAnyway)),
        ],
      ),
    );
    if (ok == true) notifier.setLockTimeout(LockTimeout.always);
  }

  Future<void> _manageRecovery(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(sessionControllerProvider.notifier);
    final enabled =
        ref.read(sessionControllerProvider).cache?.wrappedRecovery != null;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(
            enabled ? ctx.l10n.recoveryActive : ctx.l10n.recoveryNotActive),
        children: [
          if (enabled)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop('rotate'),
              child: ListTile(
                leading: const Icon(Icons.refresh),
                title: Text(ctx.l10n.rotateRecovery),
                subtitle: Text(ctx.l10n.rotateRecoverySub),
              ),
            ),
          if (enabled)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop('disable'),
              child: ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(ctx.l10n.disableRecovery),
                subtitle: Text(ctx.l10n.disableRecoverySub),
              ),
            ),
          if (!enabled)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop('enable'),
              child: ListTile(
                leading: const Icon(Icons.add),
                title: Text(ctx.l10n.enableRecovery),
                subtitle: Text(ctx.l10n.enableRecoverySub),
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(),
            child: ListTile(
              leading: const Icon(Icons.close),
              title: Text(ctx.l10n.cancel),
            ),
          ),
        ],
      ),
    );
    if (action == null || !context.mounted) return;

    if (action == 'disable') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.l10n.disableRecoveryTitle),
          content: Text(ctx.l10n.disableRecoveryBody),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(ctx.l10n.cancel)),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(ctx.l10n.disableRecovery)),
          ],
        ),
      );
      if (ok == true && context.mounted) {
        await _promptOldPasswordAndRun(
            context, ref, (oldPw) => notifier.changePassword(
                oldPassword: oldPw, newPassword: oldPw, disableRecovery: true));
      }
      return;
    }

    // enable / rotate: asks for the current password
    await _promptOldPasswordAndRun(context, ref,
        (oldPw) async {
      final key = await notifier.changePassword(
        oldPassword: oldPw,
        newPassword: oldPw,
        generateRecovery: true,
      );
      if (key != null && context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(ctx.l10n.saveNewRecoveryTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(ctx.l10n.shownOnce),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(key,
                      style: const TextStyle(fontFamily: 'monospace')),
                ),
              ],
            ),
            actions: [
              FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(ctx.l10n.savedKeyButton)),
            ],
          ),
        );
      }
    });
  }

  Future<void> _promptOldPasswordAndRun(
      BuildContext context,
      WidgetRef ref,
      Future<void> Function(String oldPassword) action) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.confirmMaster),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(ctx.l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: Text(ctx.l10n.confirm)),
        ],
      ),
    );
    if (result == null) return;
    try {
      await action(result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.operationCompleted)));
      }
    } on WrongPasswordException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.wrongPassword)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.l10n.errorPrefix(e))));
      }
    }
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final oldC = TextEditingController();
    final newC = TextEditingController();
    final confirmC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.changeMasterPassword),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: oldC,
                obscureText: true,
                decoration: InputDecoration(
                    labelText: ctx.l10n.currentPassword)),
            TextField(
                controller: newC,
                obscureText: true,
                decoration: InputDecoration(
                    labelText: ctx.l10n.newPassword)),
            TextField(
                controller: confirmC,
                obscureText: true,
                decoration: InputDecoration(
                    labelText: ctx.l10n.confirmPassword)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(ctx.l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(ctx.l10n.change)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    if (newC.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.passwordMinLength)));
      return;
    }
    if (newC.text != confirmC.text) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.passwordsDontMatch)));
      return;
    }
    try {
      await ref.read(sessionControllerProvider.notifier).changePassword(
            oldPassword: oldC.text,
            newPassword: newC.text,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.passwordChanged)));
      }
    } on WrongPasswordException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.currentPasswordInvalid)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.l10n.errorPrefix(e))));
      }
    }
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
          child: Text(title.toUpperCase(),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.primary)),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Column(children: children),
        ),
      ],
    );
  }
}
