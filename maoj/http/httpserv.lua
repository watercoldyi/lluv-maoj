local httpd = require "maoj.http.httpd"
local ls = require "maoj.http.socket"
local task = require "maoj.thread"
local urllib = require "maoj.http.url"

local serv = {}

function serv.on_exit(obj,exit_cb)
	obj._exit_cb = exit_cb
end

function serv.exit(obj)
	obj._exit = true
end

function serv.location(obj,l)
	local lcts = {}
	for k,v in pairs(l) do
		assert(type(k) == "string" and type(v) == "function","unknow location")
		table.insert(lcts,{rule = k,handler = v})
	end
	table.sort(lcts,function(a,b)
		 return #a.rule > #b.rule
	end)
	obj._location = lcts 
end

local _serv_meta = { __index = serv}

local function response(sock,...)
	httpd.write_response(ls.writefunc(sock),...)	
end

local function _log(info)
	print(os.date("[%Y-%m-%d %H:%M:%S]"),info)
end

local function req_worke(self,sock)
	sock:start()
	local code,url,method,heads,body = httpd.read_request(ls.readfunc(sock))
	local log = ''
	if code then
		if code ~= 200 then
			response(sock,code)
		else
			
			local path,query = 	urllib.parse(url)
			local arg = urllib.parse_query(query)
			local handler = nil
			for _,v in ipairs(self._location) do
				local h,e = string.find(path,v.rule)
				if h then
					handler = v.handler
					break
				end
			end
			if not handler then
				response(sock,404)
				log = log .. " "..method.." "..url.." 404"
			else
				local ok,rcode,rbody,rhead = pcall(handler,{args = arg,path = path,url = url,heades = heads,method = method,body = body})
				if ok then
					log = log .. " "..method.." "..url.." "..rcode
					response(sock,rcode,rbody,rhead)
				else
					log = log .. " "..method.." "..url.." 500"
					response(sock,500)
				end
			end
		
		end
	else
		log = log.." unkown"
	end
	sock:close()
	_log(log)
end

local function create(ip,port)
	local self = setmetatable({},_serv_meta)		
	self._handler = {}
	local sock,err = ls.listen(ip,port,function(s,c,err)
		if c then
			task.fork(req_worke,self,c)
		else
			local f = self._exit_cb
			if f then
				f()	
			end
		end
	end)
	assert(sock,err)
	_log('start http://'..ip..':'..port)
	return self
end

return {
	create = create
}