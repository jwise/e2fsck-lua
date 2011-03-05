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

function Fsck.fsck(e)
	Fsck.pass1(e)
end
