/// The core agentic seam a screen uses to become operable by an agent.
///
/// A screen imports this, publishes an [AgentSurface] describing the fields it
/// will let an agent fill, and drops an [AgentSlot] where the affordance
/// should appear. That is the whole surface it depends on — the agentic module
/// itself (`lib/agentic/`) is never imported by feature code, so it stays
/// removable. The host/scope wiring lives in `agent_host.dart` /
/// `agent_scope.dart`, used only at the composition root.
library;

export 'agent_slot.dart' show AgentSlot;
export 'agent_surface.dart' show AgentField, AgentFieldKind, AgentSurface;
