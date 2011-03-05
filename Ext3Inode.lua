local bit = require"bit"
local serial = require"serial"

Ext3.Inode = {}
Ext3.Inode.Blocks = {}
Ext3.Inode.Blocks.INDIRECT1 = 12
Ext3.Inode.Blocks.INDIRECT2 = 13
Ext3.Inode.Blocks.INDIRECT3 = 14

function Ext3.Inode:new(o)
	o = o or {}
	
	assert(o.inum)
	assert(o.disk)
	assert(o.fs)
	
	format = (o.mode.x1000 and 1 or 0)
	       + (o.mode.x2000 and 2 or 0)
	       + (o.mode.x4000 and 4 or 0)
	       + (o.mode.x8000 and 8 or 0)
	o.mode.x1000 = nil
	o.mode.x2000 = nil
	o.mode.x4000 = nil
	o.mode.x8000 = nil
	
	    if format == 0x1 then o.mode.IFIFO = true
	elseif format == 0x2 then o.mode.IFCHR = true
	elseif format == 0x4 then o.mode.IFDIR = true
	elseif format == 0x6 then o.mode.IFBLK = true
	elseif format == 0x8 then o.mode.IFREG = true
	elseif format == 0xA then o.mode.IFLNK = true
	elseif format == 0xA then o.mode.IFSOCK = true
	else
		error("Ext3.Inode:new: invalid mode on inode "..o.inum)
	end
	
	setmetatable(o, self)
	self.__index = self
	return o
end

function Ext3.Inode:block(n)
	local bpb = self.fs.block_size / 4
	
	if n < Ext3.Inode.Blocks.INDIRECT1 then
		if self.blocks[n+1] == 0 then return nil end
		return self.blocks[n+1]
	end
	
	n = n - Ext3.Inode.Blocks.INDIRECT1
	if n < bpb then
		local i1 = self.blocks[Ext3.Inode.Blocks.INDIRECT1+1]
		if i1 == 0 then return nil end
		
		local rblock = self.fs:readblock(i1)
		local block = serial.read.array(serial.buffer(rblock), bpb, 'uint32', 'le')
		
		if blocks[n+1] == 0 then return nil end
		return blocks[n+1]
	end
	
	n = n - bpb
	if n < bpb * bpb then
		local i1 = self.blocks[Ext3.Inode.Blocks.INDIRECT2 + 1]
		if i1 == 0 then return nil end
		
		local rblock = self.fs:readblock(i1)
		local block = serial.read.array(serial.buffer(rblock), bpb, 'uint32', 'le')
		
		if blocks[n/bpb+1] == 0 then return nil end
		local i2 = blocks[n/bpb+1]
		
		rblock = self.fs:readblock(i2)
		block = serial.read.array(serial.buffer(rblock), bpb, 'uint32', 'le')
		
		if blocks[n%bpb+1] == 0 then return nil end
		return blocks[n%bpb+1]
	end
	
	n = n - bpb*bpb
	if n < bpb * bpb * bpb then
		local i1 = self.blocks[Ext3.Inode.Blocks.INDIRECT3 + 1]
		if i1 == 0 then return nil end
		
		local rblock = self.fs:readblock(i1)
		local block = serial.read.array(serial.buffer(rblock), bpb, 'uint32', 'le')
		
		if blocks[n/(bpb*bpb)+1] == 0 then return nil end
		local i2 = blocks[n/(bpb*bpb)+1]
		
		rblock = self.fs:readblock(i2)
		block = serial.read.array(serial.buffer(rblock), bpb, 'uint32', 'le')
		
		if blocks[(n/bpb)%bpb + 1] == 0 then return nil end
		local i3 = blocks[(n/bpb)%bpb + 1]
		
		rblock = self.fs:readblock(i3)
		block = serial.read.array(serial.buffer(rblock), bpb, 'uint32', 'le')
		
		if blocks[n%bpb+1] == 0 then return nil end
		return blocks[n%bpb+1]
	end
	
	error("wow, what a colossal file!")
end

function Ext3.Inode:allblocks()
	local bpb = self.fs.block_size / 4
	local bs = {}
	
	for v = 1,Ext3.Inode.Blocks.INDIRECT1 do
		if self.blocks[v] ~= 0 then bs[self.blocks[v]] = true end
	end
	
	if self.blocks[Ext3.Inode.Blocks.INDIRECT1 + 1] ~= 0 then
		local riblock1 = self.fs:readblock(self.blocks[Ext3.Inode.Blocks.INDIRECT1 + 1])
		local iblock1 = serial.read.array(serial.buffer(riblock1), bpb, 'uint32', 'le')
		
		bs[self.blocks[Ext3.Inode.Blocks.INDIRECT1 + 1]] = true
		
		for i1 = 1,bpb do
			if iblock1[i1] ~= 0 then bs[iblock1[i1]] = true end
		end
	end
	
	if self.blocks[Ext3.Inode.Blocks.INDIRECT2 + 1] ~= 0 then
		local riblock1 = self.fs:readblock(self.blocks[Ext3.Inode.Blocks.INDIRECT2 + 1])
		local iblock1 = serial.read.array(serial.buffer(riblock1), bpb, 'uint32', 'le')
		
		bs[self.blocks[Ext3.Inode.Blocks.INDIRECT2 + 1]] = true
		
		for i1 = 1,bpb do
			if iblock1[i1] ~= 0 then
				local riblock2 = self.fs:readblock(iblock1[i1])
				local iblock2 = serial.read.array(serial.buffer(riblock2), bpb, 'uint32', 'le')
				
				bs[iblock1[i1]] = true
				
				for i2 = 1,bpb+1 do
					if iblock2[i2] ~= 0 then bs[iblock2[i2]] = true end
				end
			end
		end
	end
	
	if self.blocks[Ext3.Inode.Blocks.INDIRECT3 + 1] ~= 0 then
		local riblock1 = self.fs:readblock(self.blocks[Ext3.Inode.Blocks.INDIRECT3 + 1])
		local iblock1 = serial.read.array(serial.buffer(riblock1), bpb, 'uint32', 'le')
		
		bs[self.blocks[Ext3.Inode.Blocks.INDIRECT3 + 1]] = true
		
		for i1 = 1,bpb do
			if iblock1[i1] ~= 0 then
				local riblock2 = self.fs:readblock(iblock1[i1])
				local iblock2 = serial.read.array(serial.buffer(riblock2), bpb, 'uint32', 'le')
				
				bs[iblock1[i1]] = true
				
				for i2 = 1,bpb do
					if iblock2[i2] ~= 0 then
						local riblock3 = self.fs:readblock(iblock2[i2])
						local iblock3 = serial.read.array(serial.buffer(riblock3), bpb, 'uint32', 'le')
						
						bs[iblock2[i2]] = true
						
						for i3 = 1,bpb do
							if iblock3[i3] ~= 0 then bs[iblock3[i3]] = true end
						end
					end
				end
			end
		end
	end
	
	return bs
end
