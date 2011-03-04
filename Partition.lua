local bit = require"bit"
local serial = require"serial"

serial.struct.partition = {
	{'status', 'uint8'},
	{'chs_first', 'bytes', 3},
	{'type', 'uint8'},
	{'chs_last', 'bytes', 3},
	{'lba', 'uint32', 'le'},
	{'sectors', 'uint32', 'le'}
}

PartitionTable = {}

PartitionTable.types = {}
PartitionTable.types.UNUSED = 0x00
PartitionTable.types.EXT2 = 0x83
PartitionTable.types.LINUXSWAP = 0x82
PartitionTable.types.EXTENDED = 0x05


PartitionTable.mbr = {
	{'code', 'bytes', 446},
	{'partitions', 'array', 4, 'partition'},
	{'signature', 'uint16', 'le'}
}

PartitionTable.ebr = {
	{'unused', 'bytes', 446},
	{'partitions', 'array', 2, 'partition'},
	{'signature', 'uint16', 'le'}
}

function PartitionTable:new(o)
	o = o or {}
	
	assert(o.disk)
	
	setmetatable(o, self)
	self.__index = self
	return o
end

function PartitionTable:read()
	if self.partitions then
		return self.partitions
	end
	
	self.partitions = {}
	local next = 0
	local mbr = true
	
	while next ~= nil do
		local data = self.disk:read(next)
		local st = serial.read.struct(serial.buffer(data), mbr and self.mbr or self.ebr)
		local ofs = next
		next = nil
	
		for k,v in ipairs(st.partitions) do
			if mbr or k == 1 then
				table.insert(self.partitions,
					Partition:new{
						disk = self.disk,
						start = ofs + v.lba,
						size = v.sectors,
						type = v.type,
						status = v.status})
			end
		
			if v.type == self.types.EXTENDED then
				next = ofs + v.lba
			end
		end
		
		mbr = false
	end
	
	return self
end

Partition = {}

function Partition:new(o)
	o = o or {}
	
	assert(o.disk)
	assert(o.start)
	assert(o.size)
	
	o.BYTES_PER_SECTOR = o.disk.BYTES_PER_SECTOR
	
	setmetatable(o, self)
	self.__index = self
	return o
end

function Partition:read(sector, nsectors)
	nsectors = nsectors or 1
	assert((sector + nsectors) <= self.size)
	return self.disk:read(self.start + sector, nsectors)
end

function Partition:write(sector, value)
	assert((value:len() % 512) == 0)
	local nsectors = value:len() / 512
	assert((sector + nsectors) <= self.size)
	return self.disk:write(self.start + sector, value)
end
