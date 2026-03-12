local Tools = {}

local Skill = require("codecompanion._extensions.agentskills.skill")

local function make_system_prompt()
  local AS = require("codecompanion._extensions.agentskills")
  local skill_list = vim
    .iter(AS.get_skills())
    :map(function(name, skill)
      return string.format("- **%s**: %s", name, skill:description())
    end)
    :join("\n")
  return string.format(
    [[# Agent Skills System

You are equipped with a **Progressive Disclosure Agent Skills System**. This allows you to dynamically load specialized domain knowledge and tools to solve complex user tasks.

## 🚀 Workflow
1. **Identify**: Review the "Available Skills" list below. If a skill matches the user's intent, choose it.
2. **Activate**: Call `activate_skill` with the skill name. This injects the skill's specific instructions (SOPs) into your context.
3. **Execute**: Strictly follow the new instructions provided by the skill.
4. **Resource Access**: If the skill instructions reference files (docs, templates) or scripts:
   - Use `load_skill_file` to read text content.
   - Use `run_skill_script` to execute executable scripts.

## ⚠️ CRITICAL RULES
1. **SKILL RESOURCE ACCESS ONLY VIA SKILL TOOLS**:
   - ❌ **NEVER** use standard file tools (`read_file`, `grep`, etc.) to access skill resources.
   - ✅ **ONLY** use `load_skill_file` and `run_skill_script`.
2. **PATH SEMANTICS**:
   - `load_skill_file.file_path` can be either:
     - skill-relative (e.g., `assets/template.md`), or
     - workspace-rooted using placeholders: `{project-root}`, `${PROJECT_ROOT}`, `${WORKSPACE_ROOT}`.
   - If skill instructions reference `{project-root}/...`, pass that path directly to `load_skill_file`.
3. **SCRIPT EXECUTION SEMANTICS**:
   - `run_skill_script.script_path` can be a skill/workspace path (using the same placeholders) or a direct command target.
   - For shell commands, prefer argv form:
     - `script_path`: `/bin/sh`
     - `args`: `[-c, "<command>"]`
4. **CONTEXT SWITCHING**: When a skill is activated, its instructions take precedence for that specific sub-task.
5. **TRANSPARENCY**: Inform the user when you are activating a skill (e.g., "I will use the `git-expert` skill to handle this...").


## 📦 Available Skills
%s]],
    skill_list
  )
end

function Tools.activate_skill()
  return {
    name = "activate_skill",
    system_prompt = make_system_prompt(),
    schema = {
      type = "function",
      ["function"] = {
        name = "activate_skill",
        description = "Activate an agent skill to load its instructions.",
        parameters = {
          type = "object",
          properties = {
            skill_name = {
              type = "string",
              description = "The name of the skill to activate.",
            },
          },
          required = { "skill_name" },
        },
        strict = true,
      },
    },
    cmds = {
      function(self, args)
        local AS = require("codecompanion._extensions.agentskills")
        local skill = AS.get_skill(args.skill_name)
        if not skill then
          return { status = "error", data = "Skill not found: " .. args.skill_name }
        else
          return { status = "success", data = skill }
        end
      end,
    },
    output = {
      success = function(self, output, meta)
        local skill = output[#output] ---@type CodeCompanion.AgentSkills.Skill
        local for_user = string.format("Activated skill: %s", skill:name())
        meta.tools.chat:add_tool_output(self, skill:read_content(), for_user)
      end,
      error = function(self, output, meta)
        local error_msg = string.format(
          "Failed to activate skill: %s. Error: %s",
          self.args.skill_name,
          output[#output]
        )
        meta.tools.chat:add_tool_output(self, error_msg)
      end,
    },
  }
end

function Tools.load_skill_file()
  return {
    name = "load_skill_file",
    schema = {
      type = "function",
      ["function"] = {
        name = "load_skill_file",
        description = "Load a file provided by a skill.",
        parameters = {
          type = "object",
          properties = {
            skill_name = {
              type = "string",
              description = "The name of the skill to load the file from.",
            },
            file_path = {
              type = "string",
              description = "The path of the file to load. Supports skill-relative paths and placeholders '{project-root}', '${PROJECT_ROOT}', or '${WORKSPACE_ROOT}' for workspace-rooted paths. Example: 'references/usage.md' or '{project-root}/_bmad/bmm/workflows/.../workflow.md'.",
            },

          },
          required = { "skill_name", "file_path" },
        },
        strict = true,
      },
    },
    cmds = {
      function(self, args)
        local AS = require("codecompanion._extensions.agentskills")
        local skill = AS.get_skill(args.skill_name)
        if not skill then
          return { status = "error", data = "Skill not found: " .. args.skill_name }
        end
        local content = skill:read_file(args.file_path)
        if not content then
          return { status = "error", data = "File not found in skill: " .. args.file_path }
        end
        return { status = "success", data = content }
      end,
    },
    output = {
      success = function(self, output, meta)
        local content = output[#output]
        local for_user = string.format(
          "Loaded skill file successfully: %s/%s",
          self.args.skill_name,
          self.args.file_path
        )
        meta.tools.chat:add_tool_output(self, content, for_user)
      end,
      error = function(self, output, meta)
        local error_msg = string.format(
          "Failed to load skill file: %s/%s. Error: %s",
          self.args.skill_name,
          self.args.file_path,
          output[#output]
        )
        meta.tools.chat:add_tool_output(self, error_msg)
      end,
    },
  }
end

function Tools.run_skill_script()
  return {
    name = "run_skill_script",
    schema = {
      type = "function",
      ["function"] = {
        name = "run_skill_script",
        description = string.format(
          [[Run a script provided by a skill. The script will be executed in user's current working directory. Use placeholder '%s' in arguments to refer to the skill directory.]],
          Skill.SKILL_DIR_PLACEHOLDER
        ),
        parameters = {
          type = "object",
          properties = {
            skill_name = {
              type = "string",
              description = "The name of the skill to run the script from.",
            },
            script_path = {
              type = "string",
              description = "The script target to run. Supports skill-relative script paths, workspace-root placeholders ('{project-root}', '${PROJECT_ROOT}', '${WORKSPACE_ROOT}'), or direct commands (e.g. '/bin/sh' with args ['-c', 'ls -r']).",
            },

            args = {
              type = "array",
              items = {
                type = "string",
              },
              description = string.format(
                [[Argument array to pass to the script. Placeholder '%s' will be replaced with the skill directory path. E.g: ["--template", "%s/assets/template.html"].]],
                Skill.SKILL_DIR_PLACEHOLDER,
                Skill.SKILL_DIR_PLACEHOLDER
              ),
            },
          },
          required = { "skill_name", "script_path" },
        },
        strict = true,
      },
    },
    cmds = {
      function(self, args, opts)
        local AS = require("codecompanion._extensions.agentskills")
        local skill = AS.get_skill(args.skill_name)
        if not skill then
          return { status = "error", data = "Skill not found: " .. args.skill_name }
        end
        skill:run_script(args.script_path, args.args or {}, function(ok, output)
          if ok then
            opts.output_cb({ status = "success", data = output })
          else
            opts.output_cb({ status = "error", data = output })
          end
        end)
      end,
    },
    output = {
      prompt = function(self)
        return string.format(
          "Confirm to run script from skill '%s' ?\n%s %s",
          self.args.skill_name,
          self.args.script_path,
          table.concat(self.args.args or {}, " ")
        )
      end,
      success = function(self, output, meta)
        local output = output[#output]
        local for_user = string.format(
          "Run skill script successfully: %s %s",
          self.args.script_path,
          table.concat(self.args.args or {}, " ")
        )
        meta.tools.chat:add_tool_output(self, output, for_user)
      end,
      error = function(self, output, meta)
        local error_msg = output[#output]
        local for_user = string.format(
          "Failed to run skill script: %s %s. Error: %s",
          self.args.script_path,
          table.concat(self.args.args or {}, " "),
          error_msg
        )
        meta.tools.chat:add_tool_output(self, error_msg, for_user)
      end,
    },
  }
end

return Tools
