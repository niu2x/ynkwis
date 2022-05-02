local Envelope = require 'Envelope'

local Message = class()

function Message:pack(message, oriBuffer)
	oriBuffer = oriBuffer or ''
	message = cjson.encode(message)
	message = Envelope:html(message)
	outputs = {
		oriBuffer,
		byte.serialize32(#message),
		message,
	} 
	local result =  table.concat(outputs)
	return result
end

function Message:unpack(output)
	if #output >= 4 then
		local len = byte.deserialize32(output)
		if #output >= len + 4 then
			local message = string.sub(output, 5, 5+len-1)

			message = Envelope:unhtml(message)
			message = cjson.decode(message)
			output = string.sub(output, 5+len)
			return message, output
		end
	end
	return nil, output
end

return Message
