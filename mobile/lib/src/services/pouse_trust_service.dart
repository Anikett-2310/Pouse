import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pouse_trusted_pc.dart';

/// Persistent service managing application-level Trust On First Use (TOFU) for Pouse PCs.
///
/// Ensures explicit user consent is required on first connection, enables automatic
/// re-authorization for previously trusted devices, and supports explicit revocation (Forget).
class PouseTrustService {
  static const String _prefKeyTrustedPcs = 'pouse_trusted_pcs_v1';

  final ValueNotifier<List<PouseTrustedPc>> trustedPcsNotifier =
      ValueNotifier<List<PouseTrustedPc>>([]);

  PouseTrustService() {
    load();
  }

  /// Loads trusted PCs from persistent local storage.
  Future<List<PouseTrustedPc>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_prefKeyTrustedPcs) ?? [];
      final list = <PouseTrustedPc>[];
      for (final item in rawList) {
        try {
          final map = jsonDecode(item) as Map<String, dynamic>;
          list.add(PouseTrustedPc.fromJson(map));
        } catch (e) {
          debugPrint('[TRUST] Failed to parse trusted PC record: $e');
        }
      }
      trustedPcsNotifier.value = list;
      return list;
    } catch (e) {
      debugPrint('[TRUST] Error loading trusted PCs: $e');
      return [];
    }
  }

  /// Checks whether a PC is trusted by stable ID or Classic BD_ADDR.
  bool isTrustedSync(String addressOrId) {
    final query = addressOrId.trim().toUpperCase();
    return trustedPcsNotifier.value.any(
      (pc) => pc.id.toUpperCase() == query || pc.classicAddress.toUpperCase() == query,
    );
  }

  /// Checks whether a PC is trusted (async ensuring storage is loaded).
  Future<bool> isTrusted(String addressOrId) async {
    if (trustedPcsNotifier.value.isEmpty) {
      await load();
    }
    return isTrustedSync(addressOrId);
  }

  /// Authorizes and persists a new trusted PC (Trust On First Use).
  Future<void> trustPc({
    required String id,
    required String name,
    required String classicAddress,
  }) async {
    final now = DateTime.now();
    final newEntry = PouseTrustedPc(
      id: id,
      name: name,
      classicAddress: classicAddress,
      firstTrustedAt: now,
      lastSeenAt: now,
    );

    final current = List<PouseTrustedPc>.from(trustedPcsNotifier.value);
    final index = current.indexWhere((p) => p == newEntry);
    if (index >= 0) {
      current[index] = newEntry.copyWith(firstTrustedAt: current[index].firstTrustedAt);
    } else {
      current.add(newEntry);
    }

    trustedPcsNotifier.value = current;
    await _save(current);
    debugPrint('[TRUST] PC trusted: ${newEntry.name} (${newEntry.classicAddress})');
  }

  /// Updates last seen timestamp for an existing trusted PC.
  Future<void> updateLastSeen(String addressOrId) async {
    final query = addressOrId.trim().toUpperCase();
    final current = List<PouseTrustedPc>.from(trustedPcsNotifier.value);
    final index = current.indexWhere(
      (pc) => pc.id.toUpperCase() == query || pc.classicAddress.toUpperCase() == query,
    );
    if (index >= 0) {
      current[index] = current[index].copyWith(lastSeenAt: DateTime.now());
      trustedPcsNotifier.value = current;
      await _save(current);
    }
  }

  /// Revokes trust for a PC (Forget device).
  Future<void> forgetPc(String addressOrId) async {
    final query = addressOrId.trim().toUpperCase();
    final current = List<PouseTrustedPc>.from(trustedPcsNotifier.value);
    final updated = current
        .where((pc) => pc.id.toUpperCase() != query && pc.classicAddress.toUpperCase() != query)
        .toList();

    if (updated.length != current.length) {
      trustedPcsNotifier.value = updated;
      await _save(updated);
      debugPrint('[TRUST] PC trust revoked for: $addressOrId');
    }
  }

  /// Clears all trusted PCs.
  Future<void> clearAll() async {
    trustedPcsNotifier.value = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyTrustedPcs);
    debugPrint('[TRUST] Cleared all trusted PCs');
  }

  Future<void> _save(List<PouseTrustedPc> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stringList = list.map((pc) => jsonEncode(pc.toJson())).toList();
      await prefs.setStringList(_prefKeyTrustedPcs, stringList);
    } catch (e) {
      debugPrint('[TRUST] Error saving trusted PCs: $e');
    }
  }

  void dispose() {
    trustedPcsNotifier.dispose();
  }
}
