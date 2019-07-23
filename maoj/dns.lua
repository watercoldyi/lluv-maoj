local uv = require 'lluv'

local _mod = {}

function _mod.query(host)
    local co = coroutine.running()
    uv.getaddrinfo(host,'',function(loop,err,ret)
        if err then
            coroutine.resume(co,{})
        else
            coroutine.resume(co,ret)
        end
    end)
    local ret = coroutine.yield(co)
    local ips = {}
    for _,v in ipairs(ret) do
        table.insert(ips,v.address)
    end
    return ips
end

return _mod