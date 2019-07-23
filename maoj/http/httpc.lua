local socket = require "maoj.http.socket"
local url = require "maoj.http.url"
local internal = require "maoj.http.internal"
local dns = require 'maoj.dns'
local string = string
local table = table

local httpc = {}

local function request(fd, method, host, url, recvheader, header, content)
	local read = socket.readfunc(fd)
	local write = socket.writefunc(fd)
	local header_content = ""
	if header then
		if not header.host then
			header.host = host
		end
		for k,v in pairs(header) do
			header_content = string.format("%s%s:%s\r\n", header_content, k, v)
		end
	else
		header_content = string.format("host:%s\r\n",host)
	end

	if content then
		local data = string.format("%s %s HTTP/1.1\r\n%scontent-length:%d\r\n\r\n", method, url, header_content, #content)
		write(data)
		write(content)
	else
		local request_header = string.format("%s %s HTTP/1.1\r\n%scontent-length:0\r\n\r\n", method, url, header_content)
		write(request_header)
	end

	local tmpline = {}
	local body = internal.recvheader(read, tmpline, "")
	if not body then
		error(socket.socket_error)
	end

	local statusline = tmpline[1]
	local code, info = statusline:match "HTTP/[%d%.]+%s+([%d]+)%s+(.*)$"
	code = assert(tonumber(code))

	local header = internal.parseheader(tmpline,2,recvheader or {})
	if not header then
		error("Invalid HTTP response header")
	end

	local length = header["content-length"]
	if length then
		length = tonumber(length)
	end
	local mode = header["transfer-encoding"]
	if mode then
		if mode ~= "identity" and mode ~= "chunked" then
			error ("Unsupport transfer-encoding")
		end
	end

	if mode == "chunked" then
		body, header = internal.recvchunkedbody(read, nil, header, body)
		if not body then
			error("Invalid response body")
		end
	else
		-- identity mode
		if length then
			if #body >= length then
				body = body:sub(1,length)
			else
				local padding = read(length - #body)
				body = body .. padding
			end
		else
			-- no content-length, read all
			body = body .. socket.readall(fd)
		end
	end

	return code, body,header
end

function httpc.request(method,uri,recvheader, header, content,nredirect)
	local protcol,host,port,path = url.unpack(uri)
	if port == "" or port == nil then
		port = 80
	end
	if path == '' then
		path = '/'
	end
	local ip = dns.query(host)[1]
	local fd = socket.connect(ip, port)
	local ok , statuscode, body,h = pcall(request, fd,method, host, path, recvheader, header, content)
	fd:close()
	nredirect = nredirect or 0
	if ok then
		if string.match(tostring(statuscode),'3%d%d') and h.location and nredirect < 10 then
			nredirect = nredirect + 1
			return httpc.request(method,h.location,recvheader,header,content,nredirect)
		else
			return statuscode, body
		end
	else
		error(statuscode)
	end
end

function httpc.get(...)
	return httpc.request("GET", ...)
end

local function escape(s)
	return (string.gsub(s, "([^A-Za-z0-9_])", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

function httpc.post(url, form, recvheader)
	local header = {
		["content-type"] = "application/x-www-form-urlencoded"
	}
	local body = {}
	for k,v in pairs(form) do
		table.insert(body, string.format("%s=%s",escape(k),escape(v)))
	end

	return httpc.request("POST",url, recvheader, header, table.concat(body , "&"))
end

return httpc