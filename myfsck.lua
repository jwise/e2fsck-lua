--
-- myfsck.lua
-- Main entry point
-- myfsck, Joshua Wise
--

require"DiskIO"
require"Partition"
require"Ext3"
require"Fsck"
require"Verbose"

local image = "../disk"

function usage() return function()
	print"usage:"
	print"  myfsck MODE PARAMS"
	print"  where MODE is one of:"
	print"    -p <partition number>   print information about a specific partition"
	print"    -P                      print information about all partitions"
	print"    -f <partition number>   runs fsck on a partition"
	print"    -f 0                    runs fsck on all partitions"
	print"  where PARAMS are some of:"
	print"    -i <filename>           use a specific file as the disk image"
	print"    -v                      be verbose"
end end

function printpart(n) return function()
	local d = DiskIO:new{path=image}:open()
	local p = PartitionTable:new{disk=d}:read()
	
	if not p.partitions[tonumber(n)] then
		print"-1"
		return
	end
	
	local pn = p.partitions[tonumber(n)]
	
	print(string.format("0x%02x %d %d", pn.type, pn.start, pn.size))
end end

function printparts() return function()
	local d = DiskIO:new{path=image}:open()
	local p = PartitionTable:new{disk=d}:read()
	
	for k,v in ipairs(p.partitions) do
		print(string.format("%d 0x%02x %d %d", k, v.type, v.start, v.size))
	end
end end

function runfsck(n) return function()
	local d = DiskIO:new{path=image}:open()
	local p = PartitionTable:new{disk=d}:read()
	
	n = tonumber(n)
	
	if n == 0 then
		for k,v in ipairs(p.partitions) do
			if v.type == 0x83 then
				vprint("Running fsck on partition "..k.."...")
				Fsck.fsck(Ext3:new{disk=v}:open())
			end
		end
	else
		Fsck.fsck(Ext3:new{disk=p.partitions[n]}:open())
	end
end end

mode = usage()
next = nil

for k,v in ipairs(arg) do
	if next then
		next(v)
		next = nil
	elseif v == "-p" then
		next = function (v) mode = printpart(v) end
	elseif v == "-P" then
		mode = printparts()
	elseif v == "-v" then
		verbose = true
	elseif v == "-f" then
		next = function (v) mode = runfsck(v) end
	elseif v == "-i" then
		next = function (v) image = v end
	else
		print("unknown argument "..v)
		usage()()
		return
	end
end

mode()
