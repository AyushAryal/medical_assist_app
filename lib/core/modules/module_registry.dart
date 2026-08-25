import 'package:flutter/material.dart';

/// A unit of functionality that can be licensed independently.
///
/// Round 1 ships everything in [ModuleTier.core]; the paid tiers exist now so
/// that gating is designed in from the start rather than retrofitted through
/// every screen later.
enum ModuleId {
  patients,
  clinics,
  encounters,
  vitals,
  notes,
  attachments,
  voiceNotes,
  earlyWarningScore,
  problemList,
  medications,
  appointments,
  analytics,
  cloudSync,
  multiUser,
  export,
}

enum ModuleTier { core, professional, clinicPlus }

extension ModuleTierX on ModuleTier {
  String get label => switch (this) {
        ModuleTier.core => 'Core',
        ModuleTier.professional => 'Professional',
        ModuleTier.clinicPlus => 'Clinic+',
      };
}

class ModuleDescriptor {
  const ModuleDescriptor({
    required this.id,
    required this.name,
    required this.description,
    required this.tier,
    required this.icon,
    this.dependsOn = const <ModuleId>[],
  });

  final ModuleId id;
  final String name;
  final String description;
  final ModuleTier tier;
  final IconData icon;

  /// Enabling a module implies enabling what it reads from. Checked by
  /// [ModuleRegistry.resolve] so a licence can never grant an unusable module.
  final List<ModuleId> dependsOn;
}

abstract final class ModuleRegistry {
  static const Map<ModuleId, ModuleDescriptor> all =
      <ModuleId, ModuleDescriptor>{
    ModuleId.patients: ModuleDescriptor(
      id: ModuleId.patients,
      name: 'Patient register',
      description: 'Demographics, MRN allocation and patient search.',
      tier: ModuleTier.core,
      icon: Icons.people_outline,
    ),
    ModuleId.clinics: ModuleDescriptor(
      id: ModuleId.clinics,
      name: 'Clinics',
      description: 'Multiple sites of care with per-site encounter context.',
      tier: ModuleTier.core,
      icon: Icons.local_hospital_outlined,
    ),
    ModuleId.encounters: ModuleDescriptor(
      id: ModuleId.encounters,
      name: 'Encounters',
      description: 'Visit records with disposition and follow-up.',
      tier: ModuleTier.core,
      icon: Icons.event_note_outlined,
      dependsOn: <ModuleId>[ModuleId.patients, ModuleId.clinics],
    ),
    ModuleId.vitals: ModuleDescriptor(
      id: ModuleId.vitals,
      name: 'Vital signs',
      description: 'Observations with age-banded reference flagging.',
      tier: ModuleTier.core,
      icon: Icons.monitor_heart_outlined,
      dependsOn: <ModuleId>[ModuleId.patients],
    ),
    ModuleId.notes: ModuleDescriptor(
      id: ModuleId.notes,
      name: 'Clinical notes',
      description: 'SOAP notes with signing, locking and amendments.',
      tier: ModuleTier.core,
      icon: Icons.description_outlined,
      dependsOn: <ModuleId>[ModuleId.encounters],
    ),
    ModuleId.problemList: ModuleDescriptor(
      id: ModuleId.problemList,
      name: 'Problem list',
      description: 'Active and resolved diagnoses with optional coding.',
      tier: ModuleTier.core,
      icon: Icons.checklist_outlined,
      dependsOn: <ModuleId>[ModuleId.patients],
    ),
    ModuleId.medications: ModuleDescriptor(
      id: ModuleId.medications,
      name: 'Medications',
      description: 'Current and past medication list.',
      tier: ModuleTier.core,
      icon: Icons.medication_outlined,
      dependsOn: <ModuleId>[ModuleId.patients],
    ),
    ModuleId.appointments: ModuleDescriptor(
      id: ModuleId.appointments,
      name: 'Appointments',
      description: 'Booking, the day list and front-desk check-in.',
      tier: ModuleTier.core,
      icon: Icons.event_outlined,
      dependsOn: <ModuleId>[ModuleId.patients, ModuleId.clinics],
    ),
    ModuleId.attachments: ModuleDescriptor(
      id: ModuleId.attachments,
      name: 'Photos & documents',
      description: 'Clinical photography and file attachments.',
      tier: ModuleTier.professional,
      icon: Icons.attach_file_outlined,
      dependsOn: <ModuleId>[ModuleId.patients],
    ),
    ModuleId.voiceNotes: ModuleDescriptor(
      id: ModuleId.voiceNotes,
      name: 'Voice notes',
      description: 'Dictate into any note field and keep the audio.',
      tier: ModuleTier.professional,
      icon: Icons.mic_none_outlined,
      dependsOn: <ModuleId>[ModuleId.attachments],
    ),
    ModuleId.earlyWarningScore: ModuleDescriptor(
      id: ModuleId.earlyWarningScore,
      name: 'Early warning score',
      description: 'NEWS2 track-and-trigger scoring on observation sets.',
      tier: ModuleTier.professional,
      icon: Icons.warning_amber_outlined,
      dependsOn: <ModuleId>[ModuleId.vitals],
    ),
    ModuleId.analytics: ModuleDescriptor(
      id: ModuleId.analytics,
      name: 'Practice analytics',
      description: 'Caseload, throughput and follow-up compliance.',
      tier: ModuleTier.clinicPlus,
      icon: Icons.insights_outlined,
      dependsOn: <ModuleId>[ModuleId.encounters],
    ),
    ModuleId.cloudSync: ModuleDescriptor(
      id: ModuleId.cloudSync,
      name: 'Cloud sync & backup',
      description: 'Encrypted sync across devices once a backend exists.',
      tier: ModuleTier.clinicPlus,
      icon: Icons.cloud_sync_outlined,
    ),
    ModuleId.multiUser: ModuleDescriptor(
      id: ModuleId.multiUser,
      name: 'Multiple users',
      description: 'Per-clinician sign-in and attribution on one device.',
      tier: ModuleTier.clinicPlus,
      icon: Icons.groups_outlined,
    ),
    ModuleId.export: ModuleDescriptor(
      id: ModuleId.export,
      name: 'Export & referral letters',
      description: 'PDF referral letters and record export.',
      tier: ModuleTier.professional,
      icon: Icons.ios_share_outlined,
      dependsOn: <ModuleId>[ModuleId.notes],
    ),
  };

  static ModuleDescriptor describe(ModuleId id) => all[id]!;

  static List<ModuleId> ofTier(ModuleTier tier) => all.values
      .where((d) => d.tier == tier)
      .map((d) => d.id)
      .toList(growable: false);

  /// Closes [granted] over its dependency graph, so a licence granting
  /// `voiceNotes` implicitly grants `attachments` and `patients` too.
  static Set<ModuleId> resolve(Set<ModuleId> granted) {
    final resolved = <ModuleId>{};
    void visit(ModuleId id) {
      if (!resolved.add(id)) return;
      for (final dependency in describe(id).dependsOn) {
        visit(dependency);
      }
    }

    for (final id in granted) {
      visit(id);
    }
    return resolved;
  }
}
