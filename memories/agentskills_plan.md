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

Implementation progress
- Step 1 completed:
  - Added policy opts in setup/defaults.
  - Added `Extension.get_policy()` export.
- Step 2 completed:
  - Added policy builder with allowlist normalization/validation against workspace.
  - Canonicalizes with `fs_realpath` when possible.
  - Rejects entries escaping workspace (including symlink escape).
  - De-duplicates vetted roots.
  - `get_policy()` now returns `workspace_root` + vetted allowlist.
  - Fixed regression: restored local `skills` declaration.
- Step 3 completed:
  - Added `Skill.set_policy()` and module-level `active_policy` in skill.lua.
  - Replaced strict skill-only resolver with policy-aware resolver:
    - allows `self.path` and vetted `external_allowlist` roots.
    - checks symlink escapes via realpath containment.
    - provides access-kind aware errors/logging.
  - Applied resolver to `read_file` and path-based `run_script` entry.
  - Wired setup to propagate policy: `Skill.set_policy(Extension.get_policy())`.
- Step 4 completed:
  - Added run target resolution split in `Skill:run_script`:
    - Path mode for allowed files under skill root or vetted allowlist.
    - Direct command mode fallback when target is not resolvable as allowed path and `allow_direct_commands=true`.
  - Added `${SKILL_DIR}` placeholder expansion helper reused for script target and args.
  - Added mode-aware logging (`path` vs `direct`) and fallback logging.
- Step 5 completed:
  - Added direct-command argv normalization helper.
  - Supports legacy single-string direct command inputs such as `/bin/sh -c ls -r` by converting into argv.
  - Preserves existing explicit args handling and placeholder expansion.

Next step suggestion
- Step 6: run focused validation (manual cases or tests) to confirm behavior in:
  - in-skill file load,
  - allowlisted workspace file load,
  - denied outside-workspace file,
  - path script mode,
  - direct command mode with `/bin/sh -c ...`.
