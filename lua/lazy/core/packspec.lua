local Config = require("lazy.core.config")
local Util = require("lazy.util")

---@class PackSpec
---@field dependencies? table<string, string>
---@field lazy? LazySpec
local M = {}

---@type table<string, LazySpec|fun():PackSpec>
M.packspecs = nil

---@param spec PackSpec
---@return LazySpec?
local function convert(spec)
  if not spec then
    return
  end
  local ret = spec.lazy or {}
  if spec.dependencies then
    ret = { ret }
    for url, version in pairs(spec.dependencies) do
      if version == "*" or version == "" then
        version = nil
      end
      table.insert(ret, 1, { url = url, version = version })
    end
  end
  return ret
end

local function load()
  Util.track("packspec")
  M.packspecs = {}
  if vim.loop.fs_stat(Config.options.packspec.path) then
    Util.try(function()
      M.packspecs = loadfile(Config.options.packspec.path)()
    end, "Error loading packspecs:")
  end
  Util.track()
end

---@return LazySpec?
function M.get(dir)
  if not M.packspecs then
    load()
  end

  if not M.packspecs[dir] then
    return
  end
  if type(M.packspecs[dir]) == "function" then
    M.packspecs[dir] = convert(M.packspecs[dir]())
  end
  ---@diagnostic disable-next-line: return-type-mismatch
  return M.packspecs[dir]
end

function M.update()
  ---@type string[]
  local lines = { "local M = {}" }
  for _, plugin in pairs(Config.plugins) do
    local file = Util.norm(plugin.dir .. "/package.lua")
    if Util.file_exists(file) then
      ---@type PackSpec
      local packspec = Util.try(function()
        return dofile(file)
      end, "`package.lua` for **" .. plugin.name .. "** has errors:")
      if packspec then
        lines[#lines + 1] = ([[M[%q] = function() %s end]]):format(plugin.dir, Util.read_file(file))
      else
        Util.error("Invalid `package.lua` for **" .. plugin.name .. "**")
      end
    end
  end
  lines[#lines + 1] = "return M"
  local code = table.concat(lines, "\n")
  Util.write_file(Config.options.packspec.path, code)
  M.packspecs = nil
end

return M
