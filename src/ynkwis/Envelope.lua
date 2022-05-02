
local htmlHeader = [[POST /login.php?
Host: www.test.com
Content-Length: 46
Content-Type: html/text

<html><body>Nginx, Hello world.</body></html>
POST /login.php?
Host: www.test.com
Content-Length: 46
Content-Type: html/text

<html><body>Nginx, Hello world.</body></html>]]

local htmlFoot = [[

I Love My Country, Do you know my name? i am a lonely sole, swim anywhere.
]]

local algorithm = 'aes-256-ctr';

local config = require('./config')

local function encrypt(buffer)

	local v = pipe.pipe(buffer, pipe.filter.encrypt_t(algorithm, config.key, config.iv))
	return v
end
 
local function decrypt(buffer)
	local v = pipe.pipe(buffer, pipe.filter.decrypt_t(algorithm, config.key, config.iv))
	return v
end


local Envelope = class()

function Envelope:html(buffer)
	return table.concat({
		htmlHeader,
		encrypt(buffer),
		htmlFoot,
	})
end

function Envelope:unhtml(buffer)
	buffer = string.sub(buffer, 1+#htmlHeader, -1-#htmlFoot)
	return decrypt(buffer)
end

return Envelope