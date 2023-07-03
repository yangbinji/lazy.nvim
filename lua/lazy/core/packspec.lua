local Config = require("lazy.core.config")
local Util = require("lazy.util")

---@class PackSpec
---@field dependencies? table<string, string>
---@field lazy? LazySpec
local M = {}

M.lazy_file = "lazy-pkg.lua"
M.pkg_file = "pkg.json"

---@alias LazyPkg {lazy?:(fun():LazySpec), pkg?:PackSpec}

---@type table<string, LazyPkg>
M.packspecs = nil
---@type table<string, LazySpec>
M.specs = {}

---@param spec LazyPkg
---@return LazySpec?
local function convert(spec)
  local ret = spec.lazy and spec.lazy() or {}
  local pkg = spec.pkg
  if pkg then
    if pkg.dependencies then
      ret = { ret }
      for url, version in pairs(pkg.dependencies) do
        if version == "*" or version == "" then
          version = nil
        end
        table.insert(ret, 1, { url = url, version = version })
      end
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
  M.specs[dir] = M.specs[dir] or convert(M.packspecs[dir])
  return M.specs[dir]
end

function M.update()
  local ret = {}
  for _, plugin in pairs(Config.plugins) do
    local spec = {
      pkg = M.pkg(plugin),
      lazy = M.lazy_pkg(plugin),
    }
    if not vim.tbl_isempty(spec) then
      ret[plugin.dir] = spec
    end
  end
  local code = "return " .. Util.dump(ret)
  Util.write_file(Config.options.packspec.path, code)
  M.packspecs = nil
end

---@param plugin LazyPlugin
function M.lazy_pkg(plugin)
  local file = Util.norm(plugin.dir .. "/" .. M.lazy_file)
  if Util.file_exists(file) then
    ---@type LazySpec
    local chunk = Util.try(function()
      return loadfile(file)
    end, "`" .. M.lazy_file .. "` for **" .. plugin.name .. "** has errors:")
    if chunk then
      return { _raw = ([[function() %s end]]):format(Util.read_file(file)) }
    else
      Util.error("Invalid `package.lua` for **" .. plugin.name .. "**")
    end
  end
end

---@param plugin LazyPlugin
function M.pkg(plugin)
  local file = Util.norm(plugin.dir .. "/" .. M.pkg_file)
  if Util.file_exists(file) then
    ---@type PackSpec
    return Util.try(function()
      return vim.json.decode(Util.read_file(file))
    end, "`" .. M.pkg_file .. "` for **" .. plugin.name .. "** has errors:")
  end
end

return M
