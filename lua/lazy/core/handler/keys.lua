local Util = require("lazy.core.util")
local Loader = require("lazy.core.loader")

---@class LazyKeys
---@field [1] string lhs
---@field [2]? string|fun() rhs
---@field desc? string
---@field mode? string|string[]
---@field noremap? boolean
---@field remap? boolean
---@field expr? boolean
---@field id string

---@class LazyKeysHandler:LazyHandler
local M = {}

---@param feed string
function M.replace_special(feed)
  for special, key in pairs({ leader = vim.g.mapleader or "\\", localleader = vim.g.maplocalleader or "\\" }) do
    local pattern = "<"
    for i = 1, #special do
      pattern = pattern .. "[" .. special:sub(i, i) .. special:upper():sub(i, i) .. "]"
    end
    pattern = pattern .. ">"
    feed = feed:gsub(pattern, key)
  end
  return feed
end

---@private
---@param key string
---@return string
local t = function(key)
  return vim.api.nvim_replace_termcodes(key, true, true, true)
end

function M.retrigger(keys)
  local mode = vim.api.nvim_get_mode().mode

  -- not sure why we have to reselect visually
  local visual = {
    t("v"),
    t("V"),
    t("<c-v>"),
  }
  if vim.tbl_contains(visual, mode) then
    return "<esc>gv" .. keys
  end

  if mode:find("o") then
    return "<esc>" .. (vim.o.opfunc ~= "" and "g@" or vim.v.operator) .. keys
  end

  return "<esc>" .. keys
end

---@param value string|LazyKeys
function M.parse(value)
  local ret = vim.deepcopy(value)
  ret = type(ret) == "string" and { ret } or ret --[[@as LazyKeys]]
  ret.mode = ret.mode or "n"
  ret.id = (ret[1] or "")
  if ret.mode then
    local mode = ret.mode
    if type(mode) == "table" then
      ---@cast mode string[]
      table.sort(mode)
      ret.id = ret.id .. " (" .. table.concat(mode, ", ") .. ")"
    elseif mode ~= "n" then
      ret.id = ret.id .. " (" .. mode .. ")"
    end
  end
  return ret
end

---@param plugin LazyPlugin
function M:values(plugin)
  ---@type table<string,any>
  local values = {}
  ---@diagnostic disable-next-line: no-unknown
  for _, value in ipairs(plugin[self.type] or {}) do
    local keys = M.parse(value)
    if keys[2] == vim.NIL or keys[2] == false then
      values[keys.id] = nil
    else
      values[keys.id] = keys
    end
  end
  return values
end

function M.opts(keys)
  local opts = {}
  for k, v in pairs(keys) do
    if type(k) ~= "number" and k ~= "mode" and k ~= "id" then
      opts[k] = v
    end
  end
  return opts
end

---@param keys LazyKeys
function M:_add(keys)
  local lhs = keys[1]
  local opts = M.opts(keys)
  opts.remap = true
  opts.expr = true
  vim.keymap.set(keys.mode, lhs, function()
    local plugins = self.active[keys.id]

    -- always delete the mapping immediately to prevent recursive mappings
    self:_del(keys)
    self.active[keys.id] = nil

    Util.track({ keys = lhs })
    Loader.load(plugins, { keys = lhs })
    local expr = M.retrigger(lhs)
    Util.track()

    return expr
  end, opts)
end

---@param keys LazyKeys
function M:_del(keys)
  pcall(vim.keymap.del, keys.mode, keys[1])
  if keys[2] then
    vim.keymap.set(keys.mode, keys[1], keys[2], M.opts(keys))
  end
end

return M
