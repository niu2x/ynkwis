ynkwis
======

another socks5 tunnel.

Usage
-----

1. provide your crypto key
create a file **src/ynkwis/config.lua** with content: 
.. code-block ::

	local myIV = '1111111111111111';
	local myKey = '11111111111111111111111111111111';
	return {iv = myIV, key = myKey}

2. startup server 
.. code-block ::

	setsid nxlua .src/ynkwis/Tiger.lua 0.0.0.0 8889 > /dev/null

3. startup client
.. code-block ::

	nxlua .src/ynkwis/Wolf.js 127.0.0.1 8081 XX.XX.XX.XX 8889 > /dev/null

4. setup browser's proxy 
.. code-block ::

	socks5 127.0.0.1 8081
