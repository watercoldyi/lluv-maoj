local url = {}

local function decode_func(c)
	return string.char(tonumber(c, 16))
end

local function decode(str)
	local str = str:gsub('+', ' ')
	return str:gsub("%%(..)", decode_func)
end

function url.parse(u)
	local path,query = u:match "([^?]*)%??(.*)"
	if path then
		path = decode(path)
	end
	return path, query
end

function url.parse_query(q)
	local r = {}
	for k,v in q:gmatch "(.-)=([^&]*)&?" do
		r[decode(k)] = decode(v)
	end
	return r
end

function url.unpack(s)
	s = s:gsub("\\","/")
	local proto,host,port,path = s:match "^(%a*)://([^:/]*):?(%d*)(/?.*)"
	return proto,host,tonumber(port),path
end

return url