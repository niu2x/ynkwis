local Message = require('Message')

local argv = sys.argv

if(#argv <  3) then
	print("params too few");
	return
end

local localHost = argv[2]
local localPort = argv[3]

local Tiger = class()
function Tiger:ctor(localSocket)
	self.localBuffer = ''
	self.remoteBuffer = ''
	self.localSocket = localSocket;

	self.localSocket:read_start(function(err, chunk)
		if err then
		elseif chunk then
			self.localBuffer = self.localBuffer .. chunk
			self:process()
		else
			self:destroy()
		end
	end)

	self.process = self.readTargetInfo;
	self:process()
end

function Tiger:destroy()
	if self.localSocket ~= nil then
		self.localSocket:close();
		self.localSocket = nil
	end
	if(self.remoteSocket ~= nil) then
		self.remoteSocket:close();
		self.remoteSocket = nil
	end
	self.process = self.doNothing
end

function Tiger:process()
end

function Tiger:doNothing()
end

function Tiger:readTargetInfo() 
	local message
	message, self.localBuffer = Message:unpack(self.localBuffer);
	if(message ~= nil and message.action == 'target') then
		self.targetHost = message.host;
		self.targetPort = message.port;
		self.process = self.doNothing;
		self:connectToRemote()
	end

	if(#(self.localBuffer) > 0 and message == nil) then
		local html = [[HTTP/1.1 200 OK
Server: nginx/1.19.10
Date: Sun, 16 May 2021 15:21:53 GMT
Content-Type: text/html
Content-Length: 210
Last-Modified: Sat, 15 May 2021 18:04:40 GMT
Connection: keep-alive
ETag: "60a00d38-d2"
Accept-Ranges: bytes

<a href=/video2/480P_600K_232069222.mp4> 480P_600K_232069222.mp4 </a>
<a href=/video2/480P_600K_237840311.mp4> 480P_600K_237840311.mp4 </a>
<a href=/video2/480P_600K_328569982.mp4> 480P_600K_328569982.mp4 </a>]]
		self.localSocket:write(html)
	end
end

function Tiger:connectToRemote()

	self.remoteSocket = luv.new_tcp()
	-- print(self.targetHost)
	-- print(self.targetPort)
	if not string.match(self.targetHost, '%d+.%d+.%d+.%d') then
		local dns = luv.getaddrinfo(self.targetHost)
		for i, v in ipairs(dns or {}) do
			if v.family == 'inet' and v.protocol == 'tcp' and v.socktype=='stream' then
				self.targetHost = v.addr
				-- print(self.targetHost)
				break
			end
		end
	end

	if not string.match(self.targetHost, '%d+%.%d+%.%d+%.%d') then
		self:destroy()
		return
	end

	self.remoteSocket:connect(self.targetHost, tonumber(self.targetPort), function(err)
		if err then
			return
		end
		self:writeTargetReply()
		self.remoteSocket:read_start(function(err, chunk)
			if err then
				return
			end
			if chunk then
				self.remoteBuffer = table.concat({
					self.remoteBuffer,
					chunk,
				});
				self:process();
			else
				self:destroy()
			end
		end)
	end)
end


function Tiger:writeTargetReply()
	-- print("writeTargetReply")
	self.localSocket:write(Message:pack({
		action = 'confirm',
	}))
	self.process = self.readData;
	self:process()
end

function Tiger:readData()
	local message
	message, self.localBuffer = Message:unpack(self.localBuffer);
	while(message ~= nil) do
		if (message.action == 'data') then
			local to = pipe.pipe(message.data, 'unbase64')
			self.remoteSocket:write(to);
		end
		message, self.localBuffer = Message:unpack(self.localBuffer);
	end
	
	if(#(self.remoteBuffer) > 0) then
		self.localSocket:write(Message:pack({
			['action'] = 'data',
			['data'] = pipe.pipe(self.remoteBuffer, 'base64'),
		}))
		self.remoteBuffer = ''
	end
end

local tcp = luv.new_tcp()
tcp:bind(localHost, tonumber(localPort))
tcp:listen(2, function(err)
    if err then return end
    local client_tcp = luv.new_tcp()
    tcp:accept(client_tcp)
    Tiger:new_local(client_tcp)
end)

luv.run()
