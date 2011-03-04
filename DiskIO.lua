assert(0x7FFFFFFFFFFFFFFF ~= 0x7FFFFFFFFFFFFFFE, "IO.lua requires at least 64-bit numbers")

local bit = require"bit"

DiskIO = {}

DiskIO.BYTES_PER_SECTOR = 512

function DiskIO:new(o)
	o = o or {}
	o.path = o.path or "disk"
	
	setmetatable(o, self)
	self.__index = self
	return o
end

function DiskIO:open()
	self.fd = self.fd or assert(io.open(self.path, "rb"))
	
	return self
end

function DiskIO:close()
	if self.fd then
		self.fd:close()
		self.fd = nil
	end
	
	return self
end

function DiskIO:read(sector)
	assert(self.fd:seek("set", sector * 512))
	return assert(self.fd:read(512))
end

function DiskIO:write(sector, value)
	assert(self.fd:seek("set", sector * 512))
	assert(value:len() == 512)
end
