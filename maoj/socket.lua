local uv = require 'lluv'
local thread = require 'maoj.thread'

local _mt = {}
_mt.__index = _mt
local _mod = {}
----- read buffer---------------
-- _head head of list
-- _tail tail of list
-- _lenght data size

local function _rbuf_create()
    local r = {
        _lenght = 0,
        _head = {},
    }
    r._tail = r._head
    return r
end

local function _rbuf_length(buf)
    return buf._lenght
end

local function _rbuf_push(buf,data)
    local block = {}
    block.data = data
    block.size = #data
    buf._tail.next = block
    buf._tail = block
    buf._lenght = buf._lenght + #data
end

local function _rbuf_pop(buf,n)
    if buf._lenght < n then return nil end
    local size = 0
    local ret = ''
    while size < n do
        local block = buf._head.next
        local except = n - size
        if block.size < except then
            except = block.size
        end
        local offset = #block.data - block.size + 1
        ret = ret .. string.sub(block.data,offset,offset + except - 1)
        block.size = block.size - except
        buf._lenght = buf._lenght - except
        size = size + except
        if block.size == 0 then
            buf._head.next = block.next
        end
    end
    if buf._lenght == 0 then
        buf._tail = buf._head
    end
    return ret
end

local function _rbuf_pop_sep(buf,sep)
    local p = buf._head.next
    local find = false
    local size = 0
    local nsep = 0
    while p do
        local offset = #p.data - p.size + 1
        local a,b = string.find(p.data,sep,offset)
        if a then
            size = size + a - 1
            nsep = b - a + 1
            find = true
            break
        else
            p = p.next
        end
    end
    if find then
        local data = _rbuf_pop(buf,size)
        _rbuf_pop(buf,nsep)
        return data
    else
        return nil
    end
end
----------------------
local function _parser_host(host)
    local ip,port = string.match(host,'([^:]+):(.+)')
    assert(ip and port)
    return ip,tonumber(port)
end

local function _create_client(fd)
    local c = {_fd = fd}
    c._type = 'client'
    c._buf = _rbuf_create()
    return setmetatable(c,_mt)
end

function _mt.close(sock)
    assert(sock)
    if not sock._fd then return end
    sock._fd:close()
    sock._fd = nil
end

function _mt.getip(sock)
    if sock._ip then return sock._ip end
    sock._ip = sock._fd:getpeername()
    return sock._ip
end

function _mt.read(sock,n)
   if n == nil then
        n = _rbuf_length(sock._buf)
   end
   if n == 0 then n = 1 end
   local data = _rbuf_pop(sock._buf,n)
   if data then
        return data
   else
      local co = coroutine.running()
      sock._co = co
      sock._wait = 'read'
      sock._wait_arg = n
      local state = coroutine.yield(co)
      sock._co,sock._wait = nil,nil
      if state == 'close' then
         sock._wait_arg = nil
         return nil
      else
         local r = _rbuf_pop(sock._buf,sock._wait_arg) 
         sock._wait_arg = nil
         return r
      end
   end
end

function _mt.readall(sock)
    local data = ''
    while true do
        local r = sock:read()
        if r then
            data = data .. r
        else
            return data
        end
    end
end

function _mt.readline(sock,sep)
    if sep == nil then
        sep = '\n'
    end
    assert(type(sep) == 'string')
    local data = _rbuf_pop_sep(sock._buf,sep)
    if data then
        return data
    else
        local co = coroutine.running()
        sock._wait = 'readline'
        sock._wait_arg = sep
        sock._co = co
        local state,data = coroutine.yield(co)
        if state == 'close' then
            sock._buf,sock._wait_arg = nil,nil
            return nil
        else
            sock._wait_arg = nil
            return data 
        end
    end
end

function _mt.write(sock,data)
   if  not data or #data == 0 then
       return true
   elseif not sock._fd  then
       return false
   end
   sock._fd:write(data)
   return true
end

local function _wakeup(sock,state,...)
    assert(sock._co)
    local ok,err = coroutine.resume(sock._co,state,...)
    assert(ok,err)
end

local function _check_wait(sock)
    if sock._wait == 'read' then
        assert(type(sock._wait_arg) == 'number')
        if _rbuf_length(sock._buf) >= sock._wait_arg then
            _wakeup(sock,'redy')
        end
    elseif sock._wait == 'readline' then
        assert(type(sock._wait_arg) == 'string')
        local data = _rbuf_pop_sep(sock._buf,sock._wait_arg)
        if data then
            _wakeup(sock,'redy',data)
        end
    end
end

local function _close(sock)
    sock._fd:close()
    sock._fd = nil
end

local function _read(sock)
    sock._fd:start_read(function(hd,err,data)
        if err then
            _close(sock)
            _wakeup(sock,'close')
        else
            _rbuf_push(sock._buf,data)
            _check_wait(sock)
        end
    end)
end

local function _listen(sock)
   assert(sock._type == 'server') 
   sock._fd:listen(1024,function(hd,err)
        if err then
            _close(sock)
            thread.fork(sock._accept,sock,err)
        else
            local cfd,err = hd:accept()
            if cfd then
                local client = _create_client(cfd)
                thread.fork(sock._accept,sock,client)
            else
                print('[socket accept] error '..err)
            end
        end
   end)
end

function _mt.start(sock)
    if sock._start then return end
    sock._start = true
    if sock._type == 'client' then
        _read(sock)
    else
        _listen(sock)
    end
end

function _mod.connect(ip,port)
    local fd,err = uv.tcp()
    assert(fd,err)
    local c = _create_client(fd)
    local co = coroutine.running()
    setmetatable(c,_mt)
    if port == nil then
        ip,port = _parser_host(ip)
    end
    fd:connect(ip,port,function(hd,err)
        if err then
            _close(c)
            coroutine.resume(co,nil,err)
        else
            coroutine.resume(co,c)
        end
    end)
    local fd,err = coroutine.yield(co)
    if fd then
        fd:start()
        return fd
    else
        return fd,err
    end
end

function _mod.listen(host,accepter)
    local fd,err = uv.tcp()
    assert(fd,err)
    local ok,err = fd:bind(_parser_host(host))
    if not ok then
        fd:close()
        return ok,err
    end
    local server = {
        _fd = fd,
        _type = 'server',
        _accept = accepter,
        close = function(obj)
            if obj._fd then
                obj._fd:close()
                obj._fd = nil
            end
        end,
        start = _mt.start
    }
    return server
end

return _mod