# Balaur Host Management

The concepts used to observe, explain, and eventually maintain the Balaur host while keeping human authority explicit.

## Language

**Maintenance Agent**:
An AI assistant intended to progress from observation and diagnosis toward explicitly authorized changes to the host. Its current authority is defined by its operating mode.
_Avoid_: OS agent, chatbot, Host Diagnostic Assistant

**Read-Only Mode**:
The Maintenance Agent mode that may inspect approved information and recommend actions but cannot change managed host state.
_Avoid_: Safe mode, maintenance mode

**Owner**:
The sole human authorized to use the Maintenance Agent and decide whether its recommendations become actions.
_Avoid_: User, administrator

**Host Inspection Surface**:
The explicitly approved operational information the Maintenance Agent may inspect. Personal data, credentials, application databases, and unrestricted host storage are outside this surface.
_Avoid_: The OS, everything readable

**Configuration Snapshot**:
An immutable version of the host's declared configuration made available for analysis, distinct from an editable working copy.
_Avoid_: Live repository, own codebase

**Deployed System**:
The configuration and operational state currently active on the host, which may differ from a Configuration Snapshot.
_Avoid_: Codebase, repository

**Diagnostic Report**:
An evidence-backed result that states a conclusion, confidence, observed sources, visibility limitations, and recommended human action.
_Avoid_: Answer, chat response
