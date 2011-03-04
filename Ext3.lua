local bit = require"bit"
local serial = require"serial"

Ext3 = {}

Ext3.MAGIC_NUMBER = 0xEF53
Ext3.inodes = {}
Ext3.inodes.BAD = 1
Ext3.inodes.ROOT = 2
Ext3.inodes.ACL_IDX = 3
Ext3.inodes.ACL_DATA = 4
Ext3.inodes.BOOT_LOADER = 5
Ext3.inodes.UNDEL_DIR = 6

Ext3.formats = {}

Ext3.formats.sb = {
	{'inodes_count', 'uint32', 'le'},
	{'blocks_count', 'uint32', 'le'},
	{'r_blocks_count', 'uint32', 'le'},
	{'free_blocks_count', 'uint32', 'le'},
	{'free_inodes_count', 'uint32', 'le'},
	{'first_data_block', 'uint32', 'le'},
	{'log_block_size', 'uint32', 'le'},
	{'log_frag_size', 'uint32', 'le'},
	{'blocks_per_group', 'uint32', 'le'},
	{'frags_per_group', 'uint32', 'le'},
	{'inodes_per_group', 'uint32', 'le'},
	{'mtime', 'uint32', 'le'},
	{'wtime', 'uint32', 'le'},
	{'mnt_count', 'uint16', 'le'},
	{'max_mnt_count', 'uint16', 'le'},
	{'magic', 'uint16', 'le'},
	{'state', 'uint16', 'le'},
	{'errors', 'uint16', 'le'},
	{'minor_rev_level', 'uint16', 'le'},
	{'lastcheck', 'uint32', 'le'},
	{'checkinterval', 'uint32', 'le'},
	{'creator_os', 'uint32', 'le'},
	{'rev_level', 'uint32', 'le'},
	{'def_resuid', 'uint16', 'le'},
	{'def_resgid', 'uint16', 'le'},
	{'first_ino', 'uint32', 'le'},
	{'inode_size', 'uint16', 'le'},
	{'block_group_nr', 'uint16', 'le'},
	{'feature_compat', 'flags', {
		DIR_PREALLOC = 1,
		IMAGIC_INODES = 2,
		HAS_JOURNAL = 4,
		EXT_ATTR = 8,
		RESIZE_INO = 16,
		DIR_INDEX = 32,
		ANY = 0xFFFFFFFF}, 'uint32', 'le'}, -- This is actually a bitmask!
	{'feature_incompat', 'flags', {
		COMPRESSION = 1,
		FILETYPE = 2,
		RECOVER = 4,
		JOURNAL_DEV = 8,
		META_BG = 16,
		ANY = 0xFFFFFFFF}, 'uint32', 'le'},
	{'feature_ro_compat', 'flags', {
		SPARSE_SUPER = 1,
		LARGE_FILE = 2,
		BTREE_DIR = 4,
		ANY = 0xFFFFFFFF}, 'uint32', 'le'},
	{'uuid', 'bytes', 16},
	{'volume_name', 'bytes', 16},
	{'last_mounted', 'bytes', 64},
	{'algorithm_usage_bitmap', 'uint32', 'le'},
	{'s_prealloc_blocks', 'uint8'},
	{'s_prealloc_dir_blocks', 'uint8'},
	{'s_padding1', 'uint16', 'le'}
}

Ext3.formats.bgd = {
	{'block_bitmap', 'uint32', 'le'},
	{'inode_bitmap', 'uint32', 'le'},
	{'inode_table', 'uint32', 'le'},
	{'free_blocks_count', 'uint16', 'le'},
	{'free_inodes_count', 'uint16', 'le'},
	{'used_dirs_count', 'uint16', 'le'},
	{'pad', 'uint16', 'le'},
	{'reserved', 'bytes', 12}
}
Ext3.formats.bgd.length = 32

Ext3.formats.inode = {
	{'mode', 'flags', {
		-- access
		IXOTH = 0x0001,
		IWOTH = 0x0002,
		IROTH = 0x0004,
		IXGRP = 0x0008,
		IWGRP = 0x0010,
		IRGRP = 0x0020,
		IXUSR = 0x0040,
		IWUSR = 0x0080,
		IRUSR = 0x0100,
		-- exec user/group override (?)
		ISVTX = 0x0200,
		ISGID = 0x0400,
		ISUID = 0x0800,
		-- file format... except not
		x1000 = 0x1000,
		x2000 = 0x2000,
		x4000 = 0x4000,
		x8000 = 0x8000}, 'uint16', 'le'},
	{'uid', 'uint16', 'le'},
	{'size', 'uint32', 'le'},
	{'atime', 'uint32', 'le'},
	{'ctime', 'uint32', 'le'},
	{'mtime', 'uint32', 'le'},
	{'dtime', 'uint32', 'le'},
	{'gid', 'uint16', 'le'},
	{'links_count', 'uint16', 'le'},
	{'blocks', 'uint32', 'le'},
	{'flags', 'uint32', 'le'},
	{'osd1', 'uint32', 'le'},
	{'block', 'array', 15, 'uint32', 'le'},
	{'generation', 'uint32', 'le'},
	{'file_acl', 'uint32', 'le'},
	{'dir_acl', 'uint32', 'le'},
	{'faddr', 'uint32', 'le'},
	{'osd2', 'bytes', 12}
}
Ext3.formats.inode.length = 128

function Ext3:new(o)
	o = o or {}
	
	assert(o.disk)
	o.sbsector = o.sbsector or 2
	
	setmetatable(o, self)
	self.__index = self
	return o
end

function ceildiv(a, b)
	if (a % b) == 0 then
		return a / b
	else
		return a / b + 1
	end
end

function Ext3:open()
	local data = self.disk:read(self.sbsector)
	local sb = serial.read.struct(serial.buffer(data), self.formats.sb)
	
	for k,v in pairs(sb) do
		self[k] = v
	end
	
	if self.magic ~= Ext3.MAGIC_NUMBER then
		error("Ext3: read: superblock magic does not match")
	end
	
	self.block_size = bit.lshift(1024, self.log_block_size)
	self.opened = true
	
	-- Suck in the block group descriptor table.
	local sbend = self.sbsector * self.disk.BYTES_PER_SECTOR + 1024
	local bgdtblock = ceildiv(sbend, self.block_size)
	
	local nbgs = ceildiv(self.blocks_count, self.blocks_per_group)
	local bgdtsz = Ext3.formats.bgd.length * nbgs
	local bgdtblocks = ceildiv(bgdtsz, self.block_size)
	
	bgdt=""
	for i=bgdtblock,bgdtblock+bgdtblocks-1 do
		bgdt = bgdt..self:readblock(i)
	end
	
	local bgtds = assert(serial.read.array(serial.buffer(bgdt), nbgs, 'struct', self.formats.bgd))
	self.blockgroups = {}
	for k,v in ipairs(bgtds) do
		self.blockgroups[k-1] = v
	end
	
	return self
end

function Ext3:readblock(b)
	assert(self.opened)
	
	assert(b < self.blocks_count)
	local s = self.block_size * b / self.disk.BYTES_PER_SECTOR
	
	return self.disk:read(s, self.block_size / self.disk.BYTES_PER_SECTOR)
end

function Ext3:writeblock(b, data)
	assert(self.opened)
	
	assert(data:len() == self.block_size)
	local s = self.block_size * b / self.disk.BYTES_PER_SECTOR
	
	return self.disk:write(s, data)
end

function Ext3:inode(inum)
	assert(inum >= 1 and inum < self.inodes_count)
	
	local bgn = (inum - 1) / self.inodes_per_group
	local istart = self.blockgroups[bgn].inode_table
	local iofs = ((inum - 1) % self.inodes_per_group) * Ext3.formats.inode.length
	local iblock = istart + (iofs / self.block_size)
	
	local iraw = self:readblock(iblock):sub(iofs + 1)
	local idata = serial.read.struct(serial.buffer(iraw), Ext3.formats.inode)
	
	return idata
end

function Ext3:ialloc(inum)
	assert(inum >= 1 and inum < self.inodes_count)

	local bgn = (inum - 1) / self.inodes_per_group
	local istart = self.blockgroups[bgn].inode_bitmap
	local iofs = ((inum - 1) % self.inodes_per_group)
	local iblock = istart + (iofs / 8 / self.block_size)
	local ibyte = (iofs / 8) % self.block_size
	local ibit = iofs % 8

	local raw = self:readblock(iblock)
	local b = bit.band(raw:byte(ibyte+1), bit.lshift(1, ibit))

	return b ~= 0
end

function Ext3:balloc(bnum)
	assert(bnum >= 0 and bnum < self.blocks_count)

	local bgn = bnum / self.blocks_per_group
	local bstart = self.blockgroups[bgn].block_bitmap
	local bofs = bnum % self.blocks_per_group
	local bblock = bstart + (bofs / 8 / self.block_size)
	local bbyte = (bofs / 8) % self.block_size
	local bbit = bofs % 8

	local raw = self:readblock(bblock)
--	print("checking allocation of "..bnum..", lives in bgn "..bgn..", phys block "..bblock..", byte "..bbyte..", bit "..bbit..", byte is "..raw:byte(bbyte+1))
	local b = bit.band(raw:byte(bbyte+1), bit.lshift(1, bbit))

	return b ~= 0
end
