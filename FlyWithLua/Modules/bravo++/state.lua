local M = {}
local state = {
  selector = nil,
  rotary = 0,
  trim = nil
}
local subscribers = {}

function M.get_selector() return state.selector end
function M.set_selector(v)
  if state.selector == v then return end
  state.selector = v
  if subscribers.selector then
    for _,fn in ipairs(subscribers.selector) do pcall(fn, v) end
  end
end

function M.get_rotary() return state.rotary end
function M.set_rotary(v)
  state.rotary = v
  if subscribers.rotary then
    for _,fn in ipairs(subscribers.rotary) do pcall(fn, v) end
  end
end

function M.get_trim() return state.trim end
function M.set_trim(v)
  if state.trim == v then return end
  state.trim = v
  if subscribers.trim then
    for _,fn in ipairs(subscribers.trim) do pcall(fn, v) end
  end
end

function M.subscribe_state(name, fn)
  subscribers[name] = subscribers[name] or {}
  subscribers[name][#subscribers[name]+1] = fn
end

function M.snapshot() return { selector = state.selector, rotary = state.rotary, trim = state.trim } end

return M
