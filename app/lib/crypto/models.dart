import 'package:uuid/uuid.dart';

/// A single vault entry (credential).
class VaultEntry {
  final String id;
  String name;
  String url;
  String username;
  String password;
  String notes;
  String? totpSecret;
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
    required this.createdAt,
    required this.updatedAt,
  });

  VaultEntry.create({required this.name, this.url = '', this.username = '', this.password = '', this.notes = '', this.totpSecret})
      : id = const Uuid().v4(),
        createdAt = DateTime.now().toUtc(),
        updatedAt = DateTime.now().toUtc();

  /// True if it is a TOTP entry (authenticator).
  bool get isTotp => totpSecret != null;

  VaultEntry copyWith({
    String? name,
    String? url,
    String? username,
    String? password,
    String? notes,
    String? Function()? totpSecret,
  }) {
    return VaultEntry(
      id: id,
      name: name ?? this.name,
      url: url ?? this.url,
      username: username ?? this.username,
      password: password ?? this.password,
      notes: notes ?? this.notes,
      totpSecret: totpSecret != null ? totpSecret() : this.totpSecret,
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
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

/// The whole vault: list of entries. Serialized as JSON and encrypted with the vault_key.
class VaultData {
  final List<VaultEntry> entries;

  VaultData({List<VaultEntry>? entries}) : entries = entries ?? [];

  Map<String, dynamic> toJson() => {'version': 1, 'entries': entries.map((e) => e.toJson()).toList()};

  factory VaultData.fromJson(Map<String, dynamic> json) => VaultData(
        entries: ((json['entries'] as List?) ?? [])
            .map((e) => VaultEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  VaultData copyWith({List<VaultEntry>? entries}) =>
      VaultData(entries: entries ?? this.entries);
}
