Date: 2026-03-12
Topic: Safely allow AgentSkills resources outside skill folder (workspace-constrained)
Language preference
- User may write in Spanish.
- Assistant responses and generated artifacts must be in English.

Confirmed decisions
1) Keep secure default behavior.
   - If no external allowlist configured: only skill directory is accessible.

2) External resources policy (current phase)
   - User configures external allowlist paths.
   - Enforce that each configured external path must resolve inside current workspace root.
   - No absolute arbitrary paths outside workspace for now (for file/resource access).

3) No per-skill metadata required right now.
   - Do not require editing each SKILL.md.
   - Authorization is driven by user setup allowlist only (workspace-scoped).

4) Centralized path resolver.
   - One resolver used by read_file and path-based script execution.
   - Uses normalize + realpath/relpath checks to prevent traversal/symlink escapes.

5) Script execution nuance (BMAD)
   - BMAD may execute direct commands (e.g., `/bin/sh -c ...`) instead of workspace script files.
   - Need to preserve current BMAD behavior without forcing skill rewrites.
   - Therefore, run_script policy must distinguish:
     a) path-based script file execution (workspace + allowlist constrained), and
     b) direct command/binary execution (allowed with explicit user approval flow, existing tool approval stays required).
   - Additional hardening can be added later (e.g., binary allowlist), but not to break existing BMAD now.

6) Logging/audit
   - Log denials with reason.
   - Log allowed external access with selected root.

7) Compatibility
   - Preserve tool schemas and behavior.
   - Existing skills keep working without modification.

Locked decision
- Workspace root source: `vim.uv.cwd()`.

Implementation outline
- Step 1 (implemented):
  - Added opts to AgentSkills setup:
    - external_allowlist = { "relative/or/absolute/path" }
    - enforce_workspace_boundary = true (default true)
    - allow_direct_commands = true (BMAD compatibility)
  - Added option normalization/coercion in setup.
  - Added `Extension.get_policy()` and exported it.
  - No runtime path resolver/execution changes yet.
- Step 2 (next):
  - Validate/normalize allowlist against workspace boundary (`vim.uv.cwd()`).
  - Store only vetted roots for later resolver use.
