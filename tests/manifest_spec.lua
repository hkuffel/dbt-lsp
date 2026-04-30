-- Smoke test for project + manifest reading against a fake dbt project.
-- Run: nvim --headless -u NONE -c "set rtp+=." -c "luafile tests/manifest_spec.lua" -c "qa"

local function tmpdir()
  local p = vim.fn.tempname()
  vim.fn.mkdir(p, "p")
  return p
end

local function write(path, content)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = assert(io.open(path, "w"))
  f:write(content)
  f:close()
end

local root = tmpdir()
write(root .. "/dbt_project.yml", [[
name: 'my_proj'
version: '1.0.0'
profile: 'default'
]])
write(root .. "/models/marts/orders.sql", "select 1")
write(root .. "/models/staging/stg_users.sql", "select 1")
write(root .. "/models/sources.yml", "version: 2")
write(root .. "/macros/my_macro.sql", "{% macro my_macro() %}{% endmacro %}")

local manifest = {
  metadata = { project_name = "my_proj" },
  nodes = {
    ["model.my_proj.orders"] = {
      resource_type = "model", name = "orders", package_name = "my_proj",
      original_file_path = "models/marts/orders.sql",
    },
    ["model.my_proj.stg_users"] = {
      resource_type = "model", name = "stg_users", package_name = "my_proj",
      original_file_path = "models/staging/stg_users.sql",
    },
    ["model.dbt_utils.helper"] = {
      resource_type = "model", name = "helper", package_name = "dbt_utils",
      original_file_path = "models/helper.sql",
    },
  },
  sources = {
    ["source.my_proj.raw.users"] = {
      source_name = "raw", name = "users", package_name = "my_proj",
      original_file_path = "models/sources.yml",
    },
  },
  macros = {
    ["macro.my_proj.my_macro"] = {
      name = "my_macro", package_name = "my_proj",
      original_file_path = "macros/my_macro.sql",
    },
  },
}
vim.fn.mkdir(root .. "/target", "p")
write(root .. "/target/manifest.json", vim.json.encode(manifest))

require("dbt.project").clear_cache()
require("dbt.manifest").clear_cache()

local p_info = require("dbt.project").info(root .. "/models/marts/orders.sql")
assert(p_info, "project info nil")
assert(p_info.name == "my_proj", "project name mismatch: " .. tostring(p_info.name))

local m = require("dbt.manifest")

local orders = m.get_model("orders", nil, root .. "/models/marts/orders.sql")
assert(orders, "orders not found")
assert(orders.path == root .. "/models/marts/orders.sql", "orders path: " .. orders.path)

local helper_curr = m.get_model("helper", nil, root .. "/models/marts/orders.sql")
assert(helper_curr.package == "dbt_utils", "helper from dep should be returned for bare lookup")

local users = m.get_source("raw", "users", root .. "/models/marts/orders.sql")
assert(users, "source not found")
assert(users.path == root .. "/models/sources.yml")

local mac = m.get_macro("my_macro", nil, root .. "/models/marts/orders.sql")
assert(mac, "macro not found")
assert(mac.path == root .. "/macros/my_macro.sql")

print("manifest_spec: 5 assertions passed")
