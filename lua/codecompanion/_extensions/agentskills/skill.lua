local log = require("codecompanion.utils.log")
local yaml = require("codecompanion._extensions.agentskills.3rd.yaml")

local MD_YAML_FRONTMATTER_QUERY =
  vim.treesitter.query.parse("markdown", "(document (minus_metadata) @yaml_frontmatter)")

---@param path string path to the SKILL.md
---@return table<string, any>
local function parse_skill_meta(path)
  local content = vim.fn.readblob(path)
  local md_parser = vim.treesitter.get_string_parser(content, "markdown")
  md_parser:parse()
  local tree = md_parser:trees()[1]
  return vim
    .iter(MD_YAML_FRONTMATTER_QUERY:iter_captures(tree:root()))
    :map(function(capture_id, node)
      if MD_YAML_FRONTMATTER_QUERY.captures[capture_id] ~= "yaml_frontmatter" then
        return
      end
      local yaml_text = vim.treesitter.get_node_text(node, content)
      local ok, meta = pcall(yaml.eval, yaml_text)
      if ok then
        return meta
      end
    end)
    :next()
end

---@class CodeCompanion.AgentSkills.Skill
---@field path string
---@field meta table<string, any>
local Skill = {
  SKILL_DIR_PLACEHOLDER = "${SKILL_DIR}",
}
Skill.__index = Skill

---@type {
--- workspace_root: string,
--- external_allowlist: string[],
--- enforce_workspace_boundary: boolean,
--- allow_direct_commands: boolean,
---}
local active_policy = {
  workspace_root = vim.fs.normalize(vim.uv.cwd()),
  external_allowlist = {},
  enforce_workspace_boundary = true,
  allow_direct_commands = true,
}

---@param policy? table
function Skill.set_policy(policy)
  if type(policy) ~= "table" then
    return
  end

  active_policy = {
    workspace_root = vim.fs.normalize(policy.workspace_root or vim.uv.cwd()),
    external_allowlist = vim.deepcopy(policy.external_allowlist or {}),
    enforce_workspace_boundary = policy.enforce_workspace_boundary ~= false,
    allow_direct_commands = policy.allow_direct_commands ~= false,
  }
end


---@param path string
function Skill.load(path)
  path = vim.fs.normalize(path)
  local meta = parse_skill_meta(vim.fs.joinpath(path, "SKILL.md"))
  if meta == nil then
    error("Failed to parse SKILL.md frontmatter at " .. path)
  end
  return setmetatable({
    path = path,
    meta = meta,
  }, Skill)
end

---@return string
function Skill:name()
  return vim.trim(self.meta.name)
end

---@return string
function Skill:description()
  return vim.trim(self.meta.description)
end

function Skill:_normalize_path_in_skill(path_in_skill, access_kind)
  access_kind = access_kind or "resource"

  local candidate
  if vim.startswith(path_in_skill, "/") then
    candidate = vim.fs.normalize(path_in_skill)
  else
    candidate = vim.fs.normalize(vim.fs.joinpath(self.path, path_in_skill))
  end

  local allowed_roots = { self.path }
  for _, root in ipairs(active_policy.external_allowlist or {}) do
    table.insert(allowed_roots, root)
  end

  for _, root in ipairs(allowed_roots) do
    local normalized_root = vim.fs.normalize(root)
    if vim.fs.relpath(normalized_root, candidate) ~= nil then
      local real_root = vim.uv.fs_realpath(normalized_root) or normalized_root
      local real_candidate = vim.uv.fs_realpath(candidate)

      if real_candidate and vim.fs.relpath(real_root, real_candidate) == nil then
        log:warn(
          "Denied %s path '%s' for skill '%s': symlink escape from root '%s'",
          access_kind,
          candidate,
          self:name(),
          normalized_root
        )
      else
        return candidate
      end
    end
  end

  error(string.format("Attempted to access %s outside allowed roots: %s", access_kind, path_in_skill))
end


---@return string
function Skill:read_content()
  return self:read_file("SKILL.md")
end

---@param path_in_skill string
---@return string
function Skill:read_file(path_in_skill)
  return vim.fn.readblob(self:_normalize_path_in_skill(path_in_skill, "file"))
end


---@param script string
---@param args string[]
---@param callback fun(ok: boolean, output_or_error: string)
function Skill:run_script(script, args, callback)
  local cmd = { self:_normalize_path_in_skill(script, "script") }

  local placeholder_pattern = vim.pesc(self.SKILL_DIR_PLACEHOLDER)
  for _, arg in ipairs(args or {}) do
    arg = string.gsub(arg, placeholder_pattern, self.path)
    table.insert(cmd, arg)
  end
  log:info("Running skill script: %s", cmd)
  vim.system(cmd, {
    stdout = true,
    stderr = true,
  }, function(out)
    log:info("Skill script exited with code %d: %s", out.code, cmd)
    callback = vim.schedule_wrap(callback)
    if out.code == 0 then
      callback(true, out.stdout)
    else
      local msg
      if out.signal and out.signal ~= 0 then
        msg = string.format("Script terminated with signal %d", out.signal)
      else
        msg = string.format("Script exited with code %d", out.code)
      end
      local output = { msg }
      if out.stdout and out.stdout ~= "" then
        table.insert(output, "Standard Output:")
        table.insert(output, out.stdout)
      end
      if out.stderr and out.stderr ~= "" then
        table.insert(output, "Standard Error:")
        table.insert(output, out.stderr)
      end
      callback(false, table.concat(output, "\n"))
    end
  end)
end

return Skill
