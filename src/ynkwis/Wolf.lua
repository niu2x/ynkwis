local Message = require('Message')

local argv = sys.argv

if(#argv <  5) then
	print("params too few");
	return
end

local localHost = argv[2]
local localPort = argv[3]
local remoteHost = argv[4]
local remotePort = argv[5]

local Wolf = class() 
function Wolf:ctor(localSocket)
	self.localBuffer = ''
	self.remoteBuffer = ''

	self.methodNum = 0;
	self.command = 0
	self.addrType = 0
	self.ipv4 = nil
	self.ipv6 = nil
	self.domain = nil
	self.domainLength = 0
	self.port = 0

	self.clientRequest = ''
	self.localSocket = localSocket;

	self.reqBytes = 0
	self.resBytes = 0

	self.localSocket:read_start(function(err, chunk)
		if err then
			-- print('err')
		elseif chunk then
			-- print('chunk', #chunk)
			self.localBuffer = self.localBuffer .. chunk
			self:process()
		else
			-- print('closed')
			self:destroy()
		end
	end)

	self.process = self.readAuthHeader;
	self:process()

end

function Wolf:destroy()
	if self.localSocket then
		self.localSocket:close()
		self.localSocket = nil
	end

	if self.remoteSocket then
		self.remoteSocket:close()
		self.remoteSocket = nil
	end
	self.process = self.doNothing
end

function Wolf:process()
end

function Wolf:readAuthHeader()
	-- print('readAuthHeader', #(self.localBuffer))
	if #(self.localBuffer) >= 2 then
		self.methodNum = byte.deserialize8(string.sub(self.localBuffer, 2, 2))
		-- print('self.methodNum', self.methodNum)
		self.localBuffer = string.sub(self.localBuffer, 3)
		self.process = self.readAuthMethods;
		self:process()
	end
end


function Wolf:readAuthMethods()
	-- print('readAuthMethods')
	if #(self.localBuffer) >= self.methodNum then
		self.localBuffer = string.sub(self.localBuffer, self.methodNum+1)
		self:writeAuthResponse();
		self.process = self.readTargetInfo1
		self:process()
	end
end

function Wolf:writeAuthResponse()
	-- print('writeAuthResponse')
	local response = byte.serialize8(0x05) .. byte.serialize8(0x00)
	self.localSocket:write(response);
end

function Wolf:readTargetInfo1()
	-- print('readTargetInfo1', #(self.localBuffer))
	if(#(self.localBuffer) >= 4 ) then
		self.command = byte.deserialize8(string.sub(self.localBuffer, 2, 2))
		self.addrType = byte.deserialize8(string.sub(self.localBuffer, 4, 4))

		self.clientRequest = table.concat({
			self.clientRequest, 
			string.sub(self.localBuffer, 1, 4)
		});

		self.localBuffer = string.sub(self.localBuffer, 5)

		if(self.command ~= 0x01) then
			self:destroy();
			return
		end

		self.process = self.readTargetInfo2;
		self:process()
	end
end

function Wolf:readTargetInfo2()
	-- print('readTargetInfo2')
	if(self.addrType == 1) then
		if(#(self.localBuffer) >= 4 ) then
			self.ipv4 = string.sub(self.localBuffer, 1, 4)
			self.ipv4 = byte.deserialize8(string.sub(self.ipv4, 1)) 
				.. "." .. byte.deserialize8(string.sub(self.ipv4, 2)) 
				.. "." .. byte.deserialize8(string.sub(self.ipv4, 3)) 
				.. "." .. byte.deserialize8(string.sub(self.ipv4, 4)) ;

			self.clientRequest = table.concat({
				self.clientRequest, 
				string.sub(self.localBuffer, 1, 4),
			});
			self.localBuffer = string.sub(self.localBuffer, 5)
			self.process = self.readTargetInfo3;
			self:process()
		end
	end

	if(self.addrType == 3) then
		if(#(self.localBuffer) >= 1 ) then
			self.domainLength = byte.deserialize8(self.localBuffer);
			if(#(self.localBuffer) >= 1 + self.domainLength) then
				self.domain = string.sub(self.localBuffer, 2, 1+self.domainLength);
				self.clientRequest = table.concat({
					self.clientRequest, 
					string.sub(self.localBuffer, 1, 1+self.domainLength),
				});
				self.localBuffer = string.sub(self.localBuffer, 2+self.domainLength)
				self.process = self.readTargetInfo3;
				self:process()
			end
		end
	end
	if(self.addrType == 4) then
		self:destroy();
	end
end

function Wolf:readTargetInfo3()
	-- print('readTargetInfo3')
	if(#(self.localBuffer) >= 2 ) then
		self.port = byte.deserialize16(self.localBuffer)
		self.clientRequest = table.concat({
			self.clientRequest, 
			string.sub(self.localBuffer, 1, 2),
		});
		self.localBuffer = string.sub(self.localBuffer, 3)
		self.process = self.doNothing;
		self:process()
		self:connectToRemote()
	end
end

function Wolf:readData()
	-- print('readData')
	if(#(self.localBuffer) > 0 ) then
		local clientData = self.localBuffer;
		self.reqBytes = self.reqBytes + #clientData;

		self.localBuffer = '';
		local message = Message:pack({
			action =   'data',
			data =  pipe.pipe(clientData, 'base64'),
		});
		self.remoteSocket:write(message);
	end


	local message
	local oldLen = #(self.remoteBuffer);
	message, self.remoteBuffer = Message:unpack(self.remoteBuffer);
	while(message ~= nil) do
		if (message.action == 'data') then
			local to = pipe.pipe(message.data, 'unbase64')
			self.localSocket:write(to);
		end
		message, self.remoteBuffer = Message:unpack(self.remoteBuffer);
	end
	self.resBytes = self.resBytes + oldLen - #(self.remoteBuffer);
end

function Wolf:connectToRemote()
	-- print('connectToRemote')

	self.remoteSocket = luv.new_tcp()
	self.remoteSocket:connect(remoteHost, tonumber(remotePort), function(err)
		if err then
			-- print('connectToRemote fail', err)
			return
		end
		-- print('connectToRemote success')
		self:writeTargetToRemote()
		self.remoteSocket:read_start(function(err, chunk)
			if err then
				return
			end
			if chunk then
				-- print('read data from remote')
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

function Wolf:writeTargetToRemote()
	-- print('writeTargetToRemote')
	local m = {}
	if(self.addrType == 1) then
		m.host = self.ipv4;
	else
		m.host = self.domain;
	end

	m.port = self.port;
	m.action = 'target';
	m = Message:pack(m);

	self.remoteSocket:write(m)
	self.process = self.readRemoteReply;
end

function Wolf:readRemoteReply()
	-- print('readRemoteReply')
	local message
	message, self.remoteBuffer = Message:unpack(self.remoteBuffer);
	if(message ~= nil and message.action == 'confirm') then
		self.process = self.writeClientResponse;
		self:process()
	end
end

function Wolf:doNothing()
end

function Wolf:writeClientResponse()
	-- print('writeClientResponse')
	self.clientRequest = table.concat{
		string.sub(self.clientRequest, 1, 1),
		byte.serialize8(0),
		string.sub(self.clientRequest, 3),
	}
	self.localSocket:write(self.clientRequest);
	self.process = self.readData;
	self:process()
end


local tcp = luv.new_tcp()
tcp:bind(localHost, tonumber(localPort))
tcp:listen(2, function(err)
    if err then 
		print('x')
    	return 
    end
    local client_tcp = luv.new_tcp()
    tcp:accept(client_tcp)
    Wolf:new(client_tcp)
end)

luv.run()



