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
  local nodes_by_uid = {}

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
      nodes_by_uid[unique_id] = entry
    end
  end

  for unique_id, node in pairs(manifest.sources or {}) do
    local abs_path = info.root .. "/" .. node.original_file_path
    local entry = {
      unique_id = unique_id,
      source_name = node.source_name,
      name = node.name,
      package = node.package_name,
      path = abs_path,
      resource_type = "source",
    }
    sources_by_pair[node.source_name .. "." .. node.name] = entry
    nodes_by_uid[unique_id] = entry
  end

  for unique_id, node in pairs(manifest.macros or {}) do
    local abs_path = info.root .. "/" .. node.original_file_path
    local entry = {
      unique_id = unique_id,
      name = node.name,
      package = node.package_name,
      path = abs_path,
      resource_type = "macro",
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
    nodes_by_uid = nodes_by_uid,
    parent_map = manifest.parent_map or {},
    child_map = manifest.child_map or {},
  }
end

local function neighbors(idx, unique_id, direction)
  local map = direction == "up" and idx.parent_map or idx.child_map
  local result = {}
  for _, uid in ipairs(map[unique_id] or {}) do
    local entry = idx.nodes_by_uid[uid]
    if entry then result[#result + 1] = entry end
  end
  return result
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

function M.parents_of(unique_id, start_path)
  local idx, err = M.load(start_path)
  if not idx then return nil, err end
  return neighbors(idx, unique_id, "up"), nil
end

function M.children_of(unique_id, start_path)
  local idx, err = M.load(start_path)
  if not idx then return nil, err end
  return neighbors(idx, unique_id, "down"), nil
end

function M.adjacency(start_path)
  local idx, err = M.load(start_path)
  if not idx then return nil, err end
  return {
    parent_map = idx.parent_map,
    child_map = idx.child_map,
    nodes_by_uid = idx.nodes_by_uid,
  }, nil
end

function M.clear_cache()
  cache = {}
end

return M
