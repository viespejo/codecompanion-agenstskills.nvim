Date: 2026-03-12
Topic: Safely allow AgentSkills resources outside skill folder (workspace-constrained)
Language preference
- User may write in Spanish.
- Assistant responses and generated artifacts must be in English.

Status summary
- Placeholder expansion bug fixed (`string.gsub` multi-return issue) and path placeholders are now supported in skill.lua.
- System prompt/tool schema updated to instruct placeholder usage.

Latest observed behavior
- `load_skill_file` now correctly expands `{project-root}` / `${PROJECT_ROOT}` to an absolute workspace path.
- Access is denied with: `Attempted to access file outside allowed roots: /home/.../backend/_bmad/...`.

Interpretation
- This is expected under current policy: allowed roots are `skill.path` + configured `external_allowlist` only.
- Workspace placeholder expansion alone does NOT auto-authorize workspace files.
- To permit BMAD workflow file reads, user must include `_bmad` (or a narrower workspace path) in `external_allowlist`.

Suggested UX improvement
- Improve denial error to include current allowed roots and hint to configure `external_allowlist`.
