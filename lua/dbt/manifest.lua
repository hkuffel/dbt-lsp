local project = require("dbt.project")

local M = {}

local cache = {}

local function mtime(path)
  local stat = vim.uv.fs_stat(path)
  return stat and stat.mtime.sec or nil
end

local function build_indexes(manifest, info)
  local models_by_name = {}
  local models_by_pkg_name = {}
  local sources_by_pair = {}
  local macros_by_name = {}
  local macros_by_pkg_name = {}
  local path_to_unique_id = {}

  for unique_id, node in pairs(manifest.nodes or {}) do
    local rt = node.resource_type
    if rt == "model" or rt == "snapshot" or rt == "seed" then
      local abs_path = info.root .. "/" .. node.original_file_path
      local entry = {
        unique_id = unique_id,
        name = node.name,
        package = node.package_name,
        path = abs_path,
        resource_type = rt,
      }
      models_by_pkg_name[node.package_name .. "." .. node.name] = entry
      if not models_by_name[node.name] or node.package_name == info.name then
        models_by_name[node.name] = entry
      end
      path_to_unique_id[abs_path] = unique_id
    end
  end

  for unique_id, node in pairs(manifest.sources or {}) do
    sources_by_pair[node.source_name .. "." .. node.name] = {
      unique_id = unique_id,
      source_name = node.source_name,
      name = node.name,
      package = node.package_name,
      path = info.root .. "/" .. node.original_file_path,
    }
  end

  for unique_id, node in pairs(manifest.macros or {}) do
    local abs_path = info.root .. "/" .. node.original_file_path
    local entry = {
      unique_id = unique_id,
      name = node.name,
      package = node.package_name,
      path = abs_path,
    }
    macros_by_pkg_name[node.package_name .. "." .. node.name] = entry
    -- Prefer current project's macros over package macros for bare lookup.
    local existing = macros_by_name[node.name]
    if not existing or node.package_name == info.name then
      macros_by_name[node.name] = entry
    end
  end

  return {
    models_by_name = models_by_name,
    models_by_pkg_name = models_by_pkg_name,
    sources_by_pair = sources_by_pair,
    macros_by_name = macros_by_name,
    macros_by_pkg_name = macros_by_pkg_name,
    path_to_unique_id = path_to_unique_id,
  }
end

local function load(info)
  local mt = mtime(info.manifest_path)
  if not mt then return nil, "manifest.json not found at " .. info.manifest_path end

  local cached = cache[info.root]
  if cached and cached.mtime == mt then return cached end

  local fd = io.open(info.manifest_path, "r")
  if not fd then return nil, "could not open " .. info.manifest_path end
  local raw = fd:read("*a")
  fd:close()

  local ok, manifest = pcall(vim.json.decode, raw)
  if not ok then return nil, "failed to parse manifest.json: " .. tostring(manifest) end

  local indexes = build_indexes(manifest, info)
  indexes.mtime = mt
  cache[info.root] = indexes
  return indexes
end

function M.load(start_path)
  local info = project.info(start_path)
  if not info then return nil, "not in a dbt project" end
  local indexes, err = load(info)
  if not indexes then return nil, err end
  return indexes, nil, info
end

function M.get_model(name, package, start_path)
  local idx, err = M.load(start_path)
  if not idx then return nil, err end
  if package then
    return idx.models_by_pkg_name[package .. "." .. name], nil
  end
  return idx.models_by_name[name], nil
end

function M.get_source(source_name, name, start_path)
  local idx, err = M.load(start_path)
  if not idx then return nil, err end
  return idx.sources_by_pair[source_name .. "." .. name], nil
end

function M.get_macro(name, package, start_path)
  local idx, err = M.load(start_path)
  if not idx then return nil, err end
  if package then
    return idx.macros_by_pkg_name[package .. "." .. name], nil
  end
  return idx.macros_by_name[name], nil
end

function M.clear_cache()
  cache = {}
end

return M
