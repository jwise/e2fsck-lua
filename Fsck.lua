require"Verbose"

Fsck = {}

function Fsck.printpath(path)
	s="/"
	for k,v in ipairs(path) do
		s = s .. v .. "/"
	end
	return s
end

function Fsck.pass1(e)
	local path = {}
	local ipath = {2, 2}
	
	vprint"Pass 1: Directory pointers"
	
	function verify(inum)
		local ino = e:inode(inum)
		if not ino.mode.IFDIR then return end
		
		vprint(Fsck.printpath(path) .. " ...")
		
		local dir = ino:file():directory()
		for name,namei in pairs(dir) do
			if name == "." then
				if namei ~= inum then
					error("incorrect .")
				end
			elseif name == ".." then
				if namei ~= ipath[#ipath - 1] then
					error("incorrect ..")
				end
			else
				table.insert(path, name)
				table.insert(ipath, namei)
				
				verify(namei)
				
				table.remove(path)
				table.remove(ipath)
			end
		end
	end
	
	verify(Ext3.inodes.ROOT)
end

function Fsck.pass2(e)
	vprint"Pass 2: Inode allocation bitmap"
	
	local ifound = {}
	local iondisk = {}
	local depth = 0
	local lostfound = nil
	
	function walk(inum)
		local ino = e:inode(inum)
		ifound[inum] = true
		
		if not ino.mode.IFDIR then return end
		
		local dir = ino:file():directory()
		for name,namei in pairs(dir) do
			if name == "." then
			elseif name == ".." then
			else
				if name == "lost+found" and depth == 0 then
					lostfound = namei
				end
				depth = depth + 1
				walk(namei)
				depth = depth - 1
			end
		end
	end
	
	walk(Ext3.inodes.ROOT)
	iondisk = e:iall()
	assert(lostfound)
	
	for k,v in pairs(ifound) do
		if not iondisk[k] and k >= Ext3.inodes.FIRST_GOOD then
			error("inode "..k.." in memory, but not marked as allocated")
		end
	end
	
	for k,v in pairs(iondisk) do
		if not ifound[k] and k >= Ext3.inodes.FIRST_GOOD then
			error("inode "..k.." on disk, but not found in semantic tree")
		end
	end
end

function Fsck.pass3(e)
	vprint"Pass 3: Inode link count"
	
	local ilinks = {}
	
	function link(inum)
		ilinks[inum] = ilinks[inum] or 0
		ilinks[inum] = ilinks[inum] + 1
	end
	
	function walk(inum)
		local ino = e:inode(inum)
		
		if not ino.mode.IFDIR then return end
		
		local dir = ino:file():directory()
		for name,namei in pairs(dir) do
			if name == "." then
				link(namei)
			elseif name == ".." then
				link(namei)
			else
				link(namei)
				walk(namei)
			end
		end
	end
	
	walk(Ext3.inodes.ROOT)
	
	for inum,count in pairs(ilinks) do
		local ino = e:inode(inum)
		if ino.links_count ~= count then
			error("inode "..k.." has inconsistent link count (expected "..count..", got "..ino.links_count..")")
		end
	end
end

function ispow(n, p)
	while n ~= 0 and n ~= 1 do
		n = n / p
	end
	return n == 1
end

function Fsck.pass4(e)
	vprint"Pass 4: block allocation table"
	
	local ifound = {}
	local bfound = {}
	local bondisk = {}
	
	function walk(inum)
		local ino = e:inode(inum)
		
		if ifound[inum] then
			return
		end
		ifound[inum] = true
		
		for bnum,v in pairs(ino:allblocks()) do
			if bfound[bnum] then
				error("inode "..inum.." has crosslinked block "..bnum)
			end
			bfound[bnum] = true
		end
		
		if not ino.mode.IFDIR then return end
		
		local dir = ino:file():directory()
		for name,namei in pairs(dir) do
			if name == "." then
			elseif name == ".." then
			else
				walk(namei)
			end
		end
	end
	
	walk(Ext3.inodes.ROOT)
	
	bondisk = e:ball()
	
	-- Clean up after superblocks.
	for bgn,bg in pairs(e.blockgroups) do
		if (not e.feature_ro_compat.SPARSE_SUPER) or
		   (bgn == 0) or
		   (bgn == 1) or
		   ispow(bgn, 3) or
		   ispow(bgn, 5) or
		   ispow(bgn, 7) then
			bfound[e.startblock + bgn * e.blocks_per_group] = true
			local nbgs = ceildiv(e.blocks_count, e.blocks_per_group)
			local bgdtsz = Ext3.formats.bgd.length * nbgs
			local bgdtblocks = ceildiv(bgdtsz, e.block_size)
			local bgdtblock = e.startblock + bgn * e.blocks_per_group + 1
			for i=bgdtblock,bgdtblock+bgdtblocks-1 do
				bfound[i] = true
			end
		end
	end
		   
	for bgn,bg in pairs(e.blockgroups) do
		assert(ceildiv(e.blocks_per_group, 8 * e.block_size) == 1)
		assert(ceildiv(e.inodes_per_group, 8 * e.block_size) == 1)
	
		bfound[bg.block_bitmap] = true
		bfound[bg.inode_bitmap] = true
		
		local iblocks = ceildiv(e.inodes_per_group * e.inode_size, e.block_size)
		for i = bg.inode_table, (bg.inode_table + iblocks - 1) do
			bfound[i] = true
		end
		
	end
	
	for k,v in pairs(bfound) do
		if not bondisk[k] then
			error("block "..k.." in memory, but not marked as allocated")
		end
	end
	
	for k,v in pairs(bondisk) do
		if not bfound[k] and k < e.blocks_count then
			print("block "..k.." on disk, but not found in semantic tree")
		end
	end
end

function Fsck.fsck(e)
	Fsck.pass1(e)
	Fsck.pass2(e)
	Fsck.pass3(e)
	Fsck.pass4(e)
end
