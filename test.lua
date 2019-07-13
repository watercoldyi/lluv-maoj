local uv = require 'lluv'
local http = require 'maoj.http.httpserv'
local thread = require 'maoj.thread'

local server = http.create('127.0.0.1',5001)
server:location {
    ['/'] = function(req)
        return 200,'hello maoj'
    end
}

uv.run()