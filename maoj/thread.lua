local uv = require 'lluv'

local _mod = {}

function _mod.fork(f,...)
    local co = coroutine.wrap(f)
    uv.defer(co,...)
end

return _mod