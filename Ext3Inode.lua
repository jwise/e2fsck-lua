--
-- Ext3Inode.lua
-- Filesystem file/inode/directory routines
-- myfsck, Joshua Wise
--

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

function Ext3.Inode:write()
	self.fs:inodewrite(self.inum, self)
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
		
		if self.blocks[n+1] == 0 then return nil end
		return self.blocks[n+1]
	end
	
	n = n - bpb
	if n < bpb * bpb then
		local i1 = self.blocks[Ext3.Inode.Blocks.INDIRECT2 + 1]
		if i1 == 0 then return nil end
		
		local rblock = self.fs:readblock(i1)
		local block = serial.read.array(serial.buffer(rblock), bpb, 'uint32', 'le')
		
		if self.blocks[n/bpb+1] == 0 then return nil end
		local i2 = self.blocks[n/bpb+1]
		
		rblock = self.fs:readblock(i2)
		block = serial.read.array(serial.buffer(rblock), bpb, 'uint32', 'le')
		
		if self.blocks[n%bpb+1] == 0 then return nil end
		return self.blocks[n%bpb+1]
	end
	
	n = n - bpb*bpb
	if n < bpb * bpb * bpb then
		local i1 = self.blocks[Ext3.Inode.Blocks.INDIRECT3 + 1]
		if i1 == 0 then return nil end
		
		local rblock = self.fs:readblock(i1)
		local block = serial.read.array(serial.buffer(rblock), bpb, 'uint32', 'le')
		
		if self.blocks[n/(bpb*bpb)+1] == 0 then return nil end
		local i2 = self.blocks[n/(bpb*bpb)+1]
		
		rblock = self.fs:readblock(i2)
		block = serial.read.array(serial.buffer(rblock), bpb, 'uint32', 'le')
		
		if self.blocks[(n/bpb)%bpb + 1] == 0 then return nil end
		local i3 = self.blocks[(n/bpb)%bpb + 1]
		
		rblock = self.fs:readblock(i3)
		block = serial.read.array(serial.buffer(rblock), bpb, 'uint32', 'le')
		
		if self.blocks[n%bpb+1] == 0 then return nil end
		return self.blocks[n%bpb+1]
	end
	
	error("wow, what a colossal file!")
end

function Ext3.Inode:allblocks()
	local bpb = self.fs.block_size / 4
	local bs = {}
	
	if self.mode.IFLNK and self.size <= 60 then return {} end
	
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
				
				for i2 = 1,bpb do
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

function Ext3.Inode:file()
	return Ext3.File:new{i = self, fs = self.fs}
end

function Ext3.Inode:target()
	assert(self.mode.IFLNK)
	
	if self.size > 60 then
		return self:file():read(self.size)
	end
	
	s = serial.serialize.array(self.blocks, 15, 'uint32', 'le'):gsub("%z.*", "")
	return s
end

Ext3.File = {}

function Ext3.File:new(o)
	o = o or {}
	
	assert(o.i)
	assert(o.fs)
	
	o.pos = 0
	o.size = o.i.size

	setmetatable(o, self)
	self.__index = self
	return o
end

function Ext3.File:read(bytes)
	d = ""
	
	while bytes ~= 0 do
		local blockofs = self.pos % self.fs.block_size
		local blockleft = self.fs.block_size - blockofs
		local szleft = self.size - self.pos
		local nbytes = bytes
		
		if nbytes > blockleft then nbytes = blockleft end
		if nbytes > szleft then nbytes = szleft end
		
		if nbytes == 0 then
			return d
		end
		
		local block = self.i:block(self.pos / self.fs.block_size)
		local ld
		if block == nil then
			ld = string.rep(string.char(0), self.fs.block_size)
		else
			ld = self.fs:readblock(block)
		end
		ld = ld:sub((self.pos % self.fs.block_size) + 1,
		            (self.pos + nbytes - 1) % self.fs.block_size + 1)
		
		d = d .. ld
		self.pos = self.pos + nbytes
		bytes = bytes - nbytes
	end
	return d
end

function Ext3.File:write(s)
	while s ~= "" do
		local blockofs = self.pos % self.fs.block_size
		local blockleft = self.fs.block_size - blockofs
		local szleft = self.size - self.pos
		local nbytes = s:len()
		
		if nbytes > blockleft then nbytes = blockleft end
		if nbytes > szleft then nbytes = szleft end
		
		if nbytes == 0 then
			error("Ext3.File:write cannot yet grow file")
		end
		
		local block = self.i:block(self.pos / self.fs.block_size)
		if block == nil then
			error("Ext3.File:write cannot yet fill sparse blocks")
		end
		
		local ld = self.fs:readblock(block)
		local strim = s:sub(1, nbytes)
		s = s:sub(nbytes+1)
		
		-- strreplace defined in Ext3.lua
		local blkdat = strreplace(ld, strim, self.pos % self.fs.block_size)
		
		assert(blkdat:len() == self.fs.block_size)
		self.fs:writeblock(block, blkdat)
		
		self.pos = self.pos + nbytes
	end
end

function Ext3.File:seek(pos)
	if pos == nil then return self.pos end
	
	assert(pos < self.size)
	self.pos = pos
end

-- For compatibility with the 'serial' stream interface.
Ext3.File.receive = Ext3.File.read
function Ext3.File:length()
	return self.size - self.pos
end

Ext3.File.dirent = function(value, declare_field)
	declare_field('inode', 'uint32', 'le')
	declare_field('rec_len', 'uint16', 'le')
	declare_field('name_len', 'uint8')
	declare_field('file_type', 'uint8')
	declare_field('name', 'bytes', value.name_len)
	declare_field('padding', 'bytes', value.rec_len - value.name_len - 8)
end

function Ext3.File:writedir(de)
	local d = serial.serialize.fstruct(de, Ext3.File.dirent)
	
	self:write(d)
end

function Ext3.File:readdir(nomatterwhat)
	if self.size == self.pos then
		return nil
	end
	
	local d = serial.read.fstruct(self, Ext3.File.dirent)
	if d.name_len == 0 and not nomatterwhat then
		return nil
	end
	
	if d.name:byte(1) == 0 and not nomatterwhat then
		return nil
	end
	
	return d
end

function Ext3.File:directory()
	if self._directory then return self._directory end
	
	self._directory = {}
	
	while self.size ~= self.pos do
		local d = self:readdir()
		
		if d then self._directory[d.name] = d.inode end
	end
	
	return self._directory
end
