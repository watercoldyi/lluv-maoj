local socket = require 'maoj.socket'

local _mod = {}

function _mod.connect(host,port)
    local fd,err = socket.connect(host,port)
    assert(fd,err)
    return fd
end

function _mod.readfunc(sock)
    return function(n)
        local s = sock:read(n)	
		if not s then error() end
		return s
	end
end

function _mod.writefunc(sock)
    return function(data)
        sock:write(data)
    end
end

function _mod.readall(sock)
    return sock:readall()
end

function _mod.listen(ip,port,accept)
    local fd,err = socket.listen(ip..':'..port,accept)
    if fd then
        fd:start()
    end
    return fd,err
end


return _mod