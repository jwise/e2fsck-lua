require"DiskIO"
require"Partition"

local image = "../disk"

function usage() return function()
	print"usage:"
	print"  myfsck MODE PARAMS"
	print"  where MODE is one of:"
	print"    -p <partition number>   print information about a specific partition"
	print"    -P                      print information about all partitions"
	print"  where PARAMS are some of:"
	print"    -i <filename>           use a specific file as the disk image"
end end

function printpart(n) return function()
	local d = DiskIO:new{path=image}
	d:open()
	local p = PartitionTable:new{disk=d}
	p:read()
	
	if not p.partitions[tonumber(n)] then
		print"-1"
		return
	end
	
	local pn = p.partitions[tonumber(n)]
	
	print(string.format("0x%02x %d %d", pn.type, pn.start, pn.size))
end end

function printparts() return function()
	local d = DiskIO:new{path=image}
	d:open()
	local p = PartitionTable:new{disk=d}
	p:read()
	
	for k,v in ipairs(p.partitions) do
		print(string.format("%d 0x%02x %d %d", k, v.type, v.start, v.size))
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
	elseif v == "-i" then
		next = function (v) image = v end
	else
		print("unknown argument "..v)
		usage()()
		return
	end
end

mode()
