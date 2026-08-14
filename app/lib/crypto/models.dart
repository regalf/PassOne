import 'package:uuid/uuid.dart';

/// A user-defined folder used to organize vault entries.
class VaultFolder {
  final String id;
  String name;
  DateTime createdAt;
  DateTime updatedAt;

  VaultFolder({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  VaultFolder.create({required this.name})
      : id = const Uuid().v4(),
        createdAt = DateTime.now().toUtc(),
        updatedAt = DateTime.now().toUtc();

  VaultFolder copyWith({String? name}) {
    return VaultFolder(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory VaultFolder.fromJson(Map<String, dynamic> json) => VaultFolder(
        id: json['id'] as String,
        name: (json['name'] as String?) ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

/// A single vault entry (credential).
class VaultEntry {
  final String id;
  String name;
  String url;
  String username;
  String password;
  String notes;
  String? totpSecret;
  String? privateKey;
  String? publicKey;
  String? passphrase;
  String? folderId;
  String? passkeyCredentialId;
  String? passkeyPrivateKey;
  String? passkeyPublicKey;
  String? passkeyRpId;
  String? passkeyUserHandle;
  int passkeyCounter;
  DateTime createdAt;
  DateTime updatedAt;

  VaultEntry({
    required this.id,
    required this.name,
    required this.url,
    required this.username,
    required this.password,
    required this.notes,
    this.totpSecret,
    this.privateKey,
    this.publicKey,
    this.passphrase,
    this.folderId,
    this.passkeyCredentialId,
    this.passkeyPrivateKey,
    this.passkeyPublicKey,
    this.passkeyRpId,
    this.passkeyUserHandle,
    this.passkeyCounter = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  VaultEntry.create({
    required this.name,
    this.url = '',
    this.username = '',
    this.password = '',
    this.notes = '',
    this.totpSecret,
    this.privateKey,
    this.publicKey,
    this.passphrase,
    this.folderId,
    this.passkeyCredentialId,
    this.passkeyPrivateKey,
    this.passkeyPublicKey,
    this.passkeyRpId,
    this.passkeyUserHandle,
    this.passkeyCounter = 0,
  })  : id = const Uuid().v4(),
        createdAt = DateTime.now().toUtc(),
        updatedAt = DateTime.now().toUtc();

  /// True if it is a TOTP entry (authenticator).
  bool get isTotp => totpSecret != null;

  /// True if it is an SSH key entry.
  bool get isSsh => (privateKey?.isNotEmpty ?? false) || (publicKey?.isNotEmpty ?? false);

  /// True if it is a WebAuthn passkey entry.
  bool get isPasskey =>
      passkeyCredentialId != null && passkeyPrivateKey != null;

  VaultEntry copyWith({
    String? name,
    String? url,
    String? username,
    String? password,
    String? notes,
    String? Function()? totpSecret,
    String? Function()? privateKey,
    String? Function()? publicKey,
    String? Function()? passphrase,
    String? Function()? folderId,
    String? Function()? passkeyCredentialId,
    String? Function()? passkeyPrivateKey,
    String? Function()? passkeyPublicKey,
    String? Function()? passkeyRpId,
    String? Function()? passkeyUserHandle,
    int? passkeyCounter,
  }) {
    return VaultEntry(
      id: id,
      name: name ?? this.name,
      url: url ?? this.url,
      username: username ?? this.username,
      password: password ?? this.password,
      notes: notes ?? this.notes,
      totpSecret: totpSecret != null ? totpSecret() : this.totpSecret,
      privateKey: privateKey != null ? privateKey() : this.privateKey,
      publicKey: publicKey != null ? publicKey() : this.publicKey,
      passphrase: passphrase != null ? passphrase() : this.passphrase,
      folderId: folderId != null ? folderId() : this.folderId,
      passkeyCredentialId: passkeyCredentialId != null
          ? passkeyCredentialId()
          : this.passkeyCredentialId,
      passkeyPrivateKey:
          passkeyPrivateKey != null ? passkeyPrivateKey() : this.passkeyPrivateKey,
      passkeyPublicKey:
          passkeyPublicKey != null ? passkeyPublicKey() : this.passkeyPublicKey,
      passkeyRpId: passkeyRpId != null ? passkeyRpId() : this.passkeyRpId,
      passkeyUserHandle:
          passkeyUserHandle != null ? passkeyUserHandle() : this.passkeyUserHandle,
      passkeyCounter: passkeyCounter ?? this.passkeyCounter,
      createdAt: createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'username': username,
        'password': password,
        'notes': notes,
        'totpSecret': totpSecret,
        'privateKey': privateKey,
        'publicKey': publicKey,
        'passphrase': passphrase,
        'folderId': folderId,
        'passkeyCredentialId': passkeyCredentialId,
        'passkeyPrivateKey': passkeyPrivateKey,
        'passkeyPublicKey': passkeyPublicKey,
        'passkeyRpId': passkeyRpId,
        'passkeyUserHandle': passkeyUserHandle,
        'passkeyCounter': passkeyCounter,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory VaultEntry.fromJson(Map<String, dynamic> json) => VaultEntry(
        id: json['id'] as String,
        name: (json['name'] as String?) ?? '',
        url: (json['url'] as String?) ?? '',
        username: (json['username'] as String?) ?? '',
        password: (json['password'] as String?) ?? '',
        notes: (json['notes'] as String?) ?? '',
        totpSecret: json['totpSecret'] as String?,
        privateKey: json['privateKey'] as String?,
        publicKey: json['publicKey'] as String?,
        passphrase: json['passphrase'] as String?,
        folderId: json['folderId'] as String?,
        passkeyCredentialId: json['passkeyCredentialId'] as String?,
        passkeyPrivateKey: json['passkeyPrivateKey'] as String?,
        passkeyPublicKey: json['passkeyPublicKey'] as String?,
        passkeyRpId: json['passkeyRpId'] as String?,
        passkeyUserHandle: json['passkeyUserHandle'] as String?,
        passkeyCounter: (json['passkeyCounter'] as int?) ?? 0,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

/// The whole vault: list of entries. Serialized as JSON and encrypted with the vault_key.
class VaultData {
  final List<VaultEntry> entries;
  final List<VaultFolder> folders;

  VaultData({List<VaultEntry>? entries, List<VaultFolder>? folders})
      : entries = entries ?? [],
        folders = folders ?? [];

  Map<String, dynamic> toJson() => {
        'version': 2,
        'entries': entries.map((e) => e.toJson()).toList(),
        'folders': folders.map((f) => f.toJson()).toList(),
      };

  factory VaultData.fromJson(Map<String, dynamic> json) => VaultData(
        entries: ((json['entries'] as List?) ?? [])
            .map((e) => VaultEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        folders: ((json['folders'] as List?) ?? [])
            .map((f) => VaultFolder.fromJson(f as Map<String, dynamic>))
            .toList(),
      );

  VaultData copyWith({List<VaultEntry>? entries, List<VaultFolder>? folders}) =>
      VaultData(
        entries: entries ?? this.entries,
        folders: folders ?? this.folders,
      );
}
