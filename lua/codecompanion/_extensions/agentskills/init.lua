local Skill = require("codecompanion._extensions.agentskills.skill")
local log = require("codecompanion.utils.log")

local Extension = {}

---@class CodeCompanion.AgentSkills.Opts
---@field paths (string | { [1]: string, recursive: boolean })[] List of paths to search for skills
---@field ignore_dirs table<string, boolean> Directories to ignore while scanning
---@field external_allowlist string[] Additional resource roots allowed for AgentSkills
---@field enforce_workspace_boundary boolean Enforce external_allowlist paths to be inside vim.uv.cwd()
---@field allow_direct_commands boolean Allow direct command execution mode in run_skill_script


---@type CodeCompanion.AgentSkills.Opts
local current_opts = {
  paths = {},
  ignore_dirs = {},
  external_allowlist = {},
  enforce_workspace_boundary = true,
  allow_direct_commands = true,
}


---@type {
--- workspace_root: string,
--- external_roots: string[],
--- enforce_workspace_boundary: boolean,
--- allow_direct_commands: boolean,
---}
local current_policy = {
  workspace_root = vim.fs.normalize(vim.uv.cwd()),
  external_roots = {},
  enforce_workspace_boundary = true,
  allow_direct_commands = true,
}

---@type table<string, CodeCompanion.AgentSkills.Skill>?
local skills

local function normalize_allowlist_path(path, workspace_root)

  if type(path) ~= "string" or path == "" then
    return nil, "path must be a non-empty string"
  end
  local normalized = vim.fs.normalize(path)
  if not vim.startswith(normalized, "/") then
    normalized = vim.fs.normalize(vim.fs.joinpath(workspace_root, normalized))
  end
  return normalized
end

local function is_path_within_root(path, root)
  local rel = vim.fs.relpath(root, path)
  return rel ~= nil
end

local function build_policy_from_opts()
  local workspace_root = vim.fs.normalize(vim.uv.cwd())
  local vetted_roots = {}
  local seen = {}

  for _, entry in ipairs(current_opts.external_allowlist or {}) do
    local normalized, err = normalize_allowlist_path(entry, workspace_root)
    if not normalized then
      log:warn("Rejected agentskills.external_allowlist entry '%s': %s", tostring(entry), err)
    elseif current_opts.enforce_workspace_boundary and not is_path_within_root(normalized, workspace_root) then
      log:warn(
        "Rejected agentskills.external_allowlist entry '%s': outside workspace root '%s'",
        normalized,
        workspace_root
      )
    else
      local canonical = vim.uv.fs_realpath(normalized) or normalized
      if current_opts.enforce_workspace_boundary and not is_path_within_root(canonical, workspace_root) then
        log:warn(
          "Rejected agentskills.external_allowlist entry '%s': real path escapes workspace root '%s'",
          canonical,
          workspace_root
        )
      elseif not seen[canonical] then
        seen[canonical] = true
        table.insert(vetted_roots, canonical)
      end
    end
  end

  current_policy = {
    workspace_root = workspace_root,
    external_roots = vetted_roots,
    enforce_workspace_boundary = current_opts.enforce_workspace_boundary,
    allow_direct_commands = current_opts.allow_direct_commands,
  }

  current_opts.external_allowlist = vim.deepcopy(vetted_roots)
end



local function discover_skills()
  skills = {}
  for _, path_spec in ipairs(current_opts.paths) do
    -- Normalize path specification
    local path, recursive
    if type(path_spec) == "string" then
      path = path_spec
      recursive = false
    else
      path = path_spec[1] or path_spec.path
      recursive = path_spec.recursive or false
    end
    path = vim.fs.normalize(path)

    log:info("Scanning skills in %s", path_spec)
    -- Custom scan to follow symlinked directories
    local function is_dir_or_symlink_dir(p)
      local stat = vim.uv.fs_lstat(p)
      if not stat then
        return false
      end
      if stat.type == "directory" then
        return true
      end
      if stat.type == "link" then
        local target_stat = vim.uv.fs_stat(p)
        return target_stat and target_stat.type == "directory"
      end
      return false
    end

    local function scan_skills(dir, depth, max_depth, result, visited)
      if depth > max_depth then
        return
      end
      local real = vim.uv.fs_realpath(dir)
      if not real or visited[real] then
        return
      end
      visited[real] = true
      if not is_dir_or_symlink_dir(dir) then
        return
      end
      local skill_md = vim.fs.joinpath(dir, "SKILL.md")
      if vim.uv.fs_stat(skill_md) then
        table.insert(result, dir)
      end
      local handle = vim.uv.fs_scandir(dir)
      if not handle then
        return
      end

      while true do
        local name, typ = vim.uv.fs_scandir_next(handle)
        if not name then
          break
        end
        -- Skip hidden directories and commonly ignored directories
        if name:sub(1, 1) ~= "." and not current_opts.ignore_dirs[name] then
          local child = vim.fs.joinpath(dir, name)
          if is_dir_or_symlink_dir(child) then
            scan_skills(child, depth + 1, max_depth, result, visited)
          end
        end
      end
    end

    local skill_files = {}
    scan_skills(path, 0, recursive and 99 or 1, skill_files, {})
    log:info("Found skill files: %s", skill_files)


    for _, skill_dir in ipairs(skill_files) do
      local ok, skill = pcall(Skill.load, skill_dir)
      if ok and skill and skill.name then
        skills[skill:name()] = skill
      else
        log:warn("Failed to load skill %s: %s", skill_dir, skill)
      end
    end
  end
end

---@param opts CodeCompanion.AgentSkills.Opts
function Extension.setup(opts)
  current_opts = vim.tbl_deep_extend("force", current_opts, opts or {})

  if type(current_opts.external_allowlist) ~= "table" then
    log:warn("agentskills.external_allowlist must be a list; falling back to empty list")
    current_opts.external_allowlist = {}
  end


  if current_opts.enforce_workspace_boundary == nil then
    current_opts.enforce_workspace_boundary = true
  else
    current_opts.enforce_workspace_boundary = not not current_opts.enforce_workspace_boundary
  end

  if current_opts.allow_direct_commands == nil then
    current_opts.allow_direct_commands = true
  else
    current_opts.allow_direct_commands = not not current_opts.allow_direct_commands
  end

  build_policy_from_opts()



  -- Detect CodeCompanion version
  local ok, cc = pcall(require, "codecompanion")
  local version = 18
  if ok and cc and cc.version then
    version = tonumber(cc.version():match("^(%d+)")) or 18
  end

  discover_skills()

  -- Apply version compatibility decorator
  local cc_compat = require("codecompanion._extensions.agentskills.cc_compat")
  local tools_module = require("codecompanion._extensions.agentskills.tools")

  local tools_config = require("codecompanion.config").interactions.chat.tools
  tools_config.activate_skill = {
    callback = cc_compat.decorate_tool(tools_module.activate_skill, version),
    visible = false,
  }
  tools_config.load_skill_file = {
    callback = cc_compat.decorate_tool(tools_module.load_skill_file, version),
    visible = false,
  }
  tools_config.run_skill_script = {
    callback = cc_compat.decorate_tool(tools_module.run_skill_script, version),
    opts = {
      allowed_in_yolo_mode = false,
      require_approval_before = true,
      require_cmd_approval = true,
    },
    visible = false,
  }
  tools_config.groups.agent_skills = {
    description = "Agent Skills",
    tools = { "activate_skill", "load_skill_file", "run_skill_script" },
    opts = { collapse_tools = true },
  }
end

---@return {
--- workspace_root: string,
--- external_allowlist: string[],
--- enforce_workspace_boundary: boolean,
--- allow_direct_commands: boolean
---}
function Extension.get_policy()
  return {
    workspace_root = current_policy.workspace_root,
    external_allowlist = vim.deepcopy(current_policy.external_roots),
    enforce_workspace_boundary = current_policy.enforce_workspace_boundary,
    allow_direct_commands = current_policy.allow_direct_commands,
  }
end


---@return table<string, CodeCompanion.AgentSkills.Skill>?
function Extension.get_skills()

  return skills
end

---@param name string
---@return CodeCompanion.AgentSkills.Skill?
function Extension.get_skill(name)
  return skills and skills[name]
end

Extension.exports = {
  Skill = Skill,
  discover = discover_skills,
  get_skills = Extension.get_skills,
  get_policy = Extension.get_policy,
}


return Extension
