import 'dart:convert';

/// Compartiment 1 : Identifiants, Clés IT & Secrets (Section 3.1).
class VaultItem {
  const VaultItem({
    required this.id,
    required this.category,
    required this.title,
    required this.login,
    required this.password,
    required this.secondaryPin,
    required this.url,
    required this.notes,
    required this.updatedAt,
  });

  static const List<String> categories = <String>[
    'Banques/Cartes',
    'Mobile Money',
    'Serveurs/SSH/Dev',
    'Comptes Personnels',
    'Autres',
  ];

  final String id;
  final String category;
  final String title;
  final String login;
  final String password;
  final String secondaryPin;
  final String url;
  final String notes;
  final int updatedAt;

  Map<String, Object?> toDbMap() {
    // Règle #1 : JSON stocké directement, chiffré nativement par SQLCipher AES-256.
    final payload = jsonEncode(<String, String>{
      'login': login,
      'password': password,
      'secondary_pin': secondaryPin,
      'url': url,
      'notes': notes,
    });
    return <String, Object?>{
      'id': id,
      'category': category,
      'title': title,
      'encrypted_payload': payload,
      'updated_at': updatedAt,
    };
  }

  factory VaultItem.fromDbMap(Map<String, Object?> map) {
    final rawPayload = (map['encrypted_payload'] as String?) ?? '{}';
    Map<String, dynamic> decoded = <String, dynamic>{};
    try {
      final parsed = jsonDecode(rawPayload);
      if (parsed is Map<String, dynamic>) {
        decoded = parsed;
      }
    } catch (_) {}

    return VaultItem(
      id: map['id']! as String,
      category: map['category']! as String,
      title: map['title']! as String,
      login: (decoded['login'] as String?) ?? '',
      password: (decoded['password'] as String?) ?? '',
      secondaryPin: (decoded['secondary_pin'] as String?) ?? '',
      url: (decoded['url'] as String?) ?? '',
      notes: (decoded['notes'] as String?) ?? '',
      updatedAt: (map['updated_at'] as int?) ?? 0,
    );
  }
}

/// Compartiment 2 : Porte-Documents Numérique Chiffré (Section 3.2).
class VaultDocument {
  const VaultDocument({
    required this.id,
    required this.title,
    required this.docType,
    required this.imageBase64,
    required this.notes,
    required this.createdAt,
  });

  static const List<String> predefinedTypes = <String>[
    'CNI',
    'Passeport',
    'Permis de conduire',
    'État civil',
    'Diplômes & Attestations',
    'Titre Foncier / Bail',
    'Entreprise (NINEA / RCCM / Statuts)',
    'Contrats & Conventions',
    'Banque / RIB',
    'Santé / Ordonnances',
    'Véhicule (Carte Grise / Assurance)',
    'Autre',
  ];

  final String id;
  final String title;
  final String docType;
  final String imageBase64;
  final String notes;
  final int createdAt;

  Map<String, Object?> toDbMap() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'doc_type': docType,
      'encrypted_image': imageBase64,
      'notes': notes,
      'created_at': createdAt,
    };
  }

  factory VaultDocument.fromDbMap(Map<String, Object?> map) {
    return VaultDocument(
      id: map['id']! as String,
      title: map['title']! as String,
      docType: map['doc_type']! as String,
      imageBase64: (map['encrypted_image'] as String?) ?? '',
      notes: (map['notes'] as String?) ?? '',
      createdAt: (map['created_at'] as int?) ?? 0,
    );
  }
}

/// Compartiment 3 : Carnet des Notes Noires (Section 3.3).
class BlackTextNote {
  const BlackTextNote({
    required this.id,
    required this.title,
    required this.content,
    required this.category,
    required this.tags,
    required this.isPinned,
    required this.createdAt,
    required this.updatedAt,
  });

  static const List<String> domains = <String>[
    'Stratégie',
    'Architecture Tech/Code',
    'Affaires/Contrats',
    'Intime/Personnel',
  ];

  final String id;
  final String title;
  final String content;
  final String category;
  final String tags;
  final bool isPinned;
  final int createdAt;
  final int updatedAt;

  Map<String, Object?> toDbMap() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'content': content,
      'category': category,
      'tags': tags,
      'is_pinned': isPinned ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory BlackTextNote.fromDbMap(Map<String, Object?> map) {
    return BlackTextNote(
      id: map['id']! as String,
      title: map['title']! as String,
      content: (map['content'] as String?) ?? '',
      category: (map['category'] as String?) ?? domains.first,
      tags: (map['tags'] as String?) ?? '',
      isPinned: ((map['is_pinned'] as int?) ?? 0) == 1,
      createdAt: (map['created_at'] as int?) ?? 0,
      updatedAt: (map['updated_at'] as int?) ?? 0,
    );
  }
}

/// Modes d'auto-destruction des Mémos Vocaux Noirs (Section 3.4).
enum AudioAutoDeleteMode {
  permanent(0, 'Permanent'),
  burnAfterListening(1, 'Écoute Unique'),
  ephemeral24h(2, 'Éphémère (24h)');

  const AudioAutoDeleteMode(this.code, this.label);
  final int code;
  final String label;

  static AudioAutoDeleteMode fromCode(int code) {
    for (final mode in values) {
      if (mode.code == code) return mode;
    }
    return AudioAutoDeleteMode.permanent;
  }
}

/// Compartiment 4 : Studio de Mémos Vocaux Noirs (Section 3.4).
class BlackAudioMemo {
  const BlackAudioMemo({
    required this.id,
    required this.title,
    required this.durationSeconds,
    required this.audioBase64,
    required this.autoDeleteMode,
    required this.listenCount,
    required this.createdAt,
  });

  final String id;
  final String title;
  final int durationSeconds;
  final String audioBase64;
  final AudioAutoDeleteMode autoDeleteMode;
  final int listenCount;
  final int createdAt;

  bool get isExpired24h {
    if (autoDeleteMode != AudioAutoDeleteMode.ephemeral24h) return false;
    final ageMs = DateTime.now().millisecondsSinceEpoch - createdAt;
    return ageMs >= const Duration(hours: 24).inMilliseconds;
  }

  Map<String, Object?> toDbMap() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'duration_seconds': durationSeconds,
      'encrypted_audio': audioBase64,
      'auto_delete_mode': autoDeleteMode.code,
      'listen_count': listenCount,
      'created_at': createdAt,
    };
  }

  factory BlackAudioMemo.fromDbMap(Map<String, Object?> map) {
    return BlackAudioMemo(
      id: map['id']! as String,
      title: map['title']! as String,
      durationSeconds: (map['duration_seconds'] as int?) ?? 0,
      audioBase64: (map['encrypted_audio'] as String?) ?? '',
      autoDeleteMode:
          AudioAutoDeleteMode.fromCode((map['auto_delete_mode'] as int?) ?? 0),
      listenCount: (map['listen_count'] as int?) ?? 0,
      createdAt: (map['created_at'] as int?) ?? 0,
    );
  }
}

/// Compteurs d'audit temps réel des 4 compartiments (Section 4.3).
class VaultCounts {
  const VaultCounts({
    required this.items,
    required this.documents,
    required this.notes,
    required this.audioMemos,
  });

  final int items;
  final int documents;
  final int notes;
  final int audioMemos;
}