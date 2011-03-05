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


function Fsck.fsck(e)
	Fsck.pass1(e)
	Fsck.pass2(e)
	Fsck.pass3(e)
end
