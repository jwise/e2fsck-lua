module((...), package.seeall)

local util = require(_NAME..".util")

serialize = {}
read = {}
write = {}
struct = {}
fstruct = {}
alias = {}

_M.verbose = false

local function warning(message, level)
	if not level then
		level = 1
	end
	if _M.verbose then
		print(debug.traceback("warning: "..message, level+1))
	end
end

-- function serialize.typename(value, typeparams...) return string end
-- function write.typename(stream, value, typeparams...) return true end
-- function read.typename(stream, typeparams...) return value end

local err_stack = {}
local function push(x)
	err_stack[#err_stack+1] = x
end
local function pop()
	err_stack[#err_stack] = nil
end
local function ioerror(msg)
	local t = {}
	for i=#err_stack,1,-1 do
		t[#t+1] = err_stack[i]
	end
	local str = "io error:\n\tin "..table.concat(t, "\n\tin ").."\nwith message: "..msg
	err_stack = {}
	return str
end

------------------------------------------------------------------------------

function serialize.uint8(value)
	push 'uint8'
	local a = value
	if value < 0 or value >= 2^8 or math.floor(value)~=value then
		error("invalid value")
	end
	local data = string.char(a)
	pop()
	return data
end

function read.uint8(stream)
	push 'uint8'
	local data,err = stream:receive(1)
	if not data then return nil,ioerror(err) end
	pop()
	return string.byte(data)
end

------------------------------------------------------------------------------

function serialize.sint8(value)
	push 'sint8'
	if value < -2^7 or value >= 2^7 or math.floor(value)~=value then
		error("invalid value")
	end
	if value < 0 then
		value = value + 2^8
	end
	pop()
	return serialize.uint8(value)
end

function read.sint8(stream)
	push 'sint8'
	local value,err = read.uint8(stream)
	if not value then return nil,err end
	if value >= 2^7 then
		value = value - 2^8
	end
	pop()
	return value
end

------------------------------------------------------------------------------

function serialize.uint16(value, endianness)
	push 'uint16'
	if value < 0 or value >= 2^16 or math.floor(value)~=value then
		error("invalid value")
	end
	local b = value % 256
	value = (value - b) / 256
	local a = value % 256
	local data
	if endianness=='le' then
		data = string.char(b, a)
	elseif endianness=='be' then
		data = string.char(a, b)
	else
		error("unknown endianness")
	end
	pop()
	return data
end

function read.uint16(stream, endianness)
	push 'uint16'
	local data,err = stream:receive(2)
	if not data then return nil,ioerror(err) end
	local a,b
	if endianness=='le' then
		b,a = string.byte(data, 1, 2)
	elseif endianness=='be' then
		a,b = string.byte(data, 1, 2)
	else
		error("unknown endianness")
	end
	pop()
	return a * 256 + b
end

------------------------------------------------------------------------------

function serialize.sint16(value, endianness)
	push 'sint16'
	if value < -2^15 or value >= 2^15 or math.floor(value)~=value then
		error("invalid value")
	end
	if value < 0 then
		value = value + 2 ^ 16
	end
	pop()
	return serialize.uint16(value, endianness)
end

function read.sint16(stream, endianness)
	push 'sint16'
	local value,err = read.uint16(stream, endianness)
	if not value then return nil,err end
	if value >= 2^15 then
		value = value - 2^16
	end
	pop()
	return value
end

------------------------------------------------------------------------------

function serialize.uint32(value, endianness)
	push 'uint32'
	if type(value)~='number' then
		error("bad argument #1 to serialize.uint32 (number expected, got "..type(value)..")", 2)
	end
	if value < 0 or value >= 2^32 or math.floor(value)~=value then
		error("invalid value")
	end
	local d = value % 256
	value = (value - d) / 256
	local c = value % 256
	value = (value - c) / 256
	local b = value % 256
	value = (value - b) / 256
	local a = value % 256
	local data
	if endianness=='le' then
		data = string.char(d, c, b, a)
	elseif endianness=='be' then
		data = string.char(a, b, c, d)
	else
		error("unknown endianness")
	end
	pop()
	return data
end

function read.uint32(stream, endianness)
	push 'uint32'
	local data,err = stream:receive(4)
	if not data then return nil,ioerror(err) end
	local a,b,c,d
	if endianness=='le' then
		d,c,b,a = string.byte(data, 1, 4)
	elseif endianness=='be' then
		a,b,c,d = string.byte(data, 1, 4)
	else
		error("unknown endianness")
	end
	pop()
	return ((a * 256 + b) * 256 + c) * 256 + d
end

------------------------------------------------------------------------------

function serialize.sint32(value, endianness)
	push 'sint32'
	if value < -2^31 or value >= 2^31 or math.floor(value)~=value then
		error("invalid value")
	end
	if value < 0 then
		value = value + 2^32
	end
	local value,err = serialize.uint32(value, endianness)
	if not value then return nil,err end
	pop()
	return value
end

function read.sint32(stream, endianness)
	push 'sint32'
	local value,err = read.uint32(stream, endianness)
	if not value then return nil,err end
	if value >= 2^31 then
		value = value - 2^32
	end
	pop()
	return value
end

------------------------------------------------------------------------------

local maxbytes = {}
do
	function n(a,b,c,d,e,f,g,h) return (((((((a or 0) * 256 + (b or 0)) * 256 + (c or 0)) * 256 + (d or 0)) * 256 + (e or 0)) * 256 + (f or 0)) * 256 + (g or 0)) * 256 + (h or 0) end
	-- find maximum byte values
	local a,b,c,d,e,f,g,h
	local ma,mb,mc,md,me,mf,mg,mh
	for i=1,8 do
		a,b,c,d,e,f,g,h = 000,000,000,000,000,000,2^i-1,255; if n(a,b,c,d,e,f,g,0) ~= n(a,b,c,d,e,f,g,1) then ma,mb,mc,md,me,mf,mg,mh = a,b,c,d,e,f,g,h end
	end
	for i=1,8 do
		a,b,c,d,e,f,g,h = 000,000,000,000,000,2^i-1,255,255; if n(a,b,c,d,e,f,g,0) ~= n(a,b,c,d,e,f,g,1) then ma,mb,mc,md,me,mf,mg,mh = a,b,c,d,e,f,g,h end
	end
	for i=1,8 do
		a,b,c,d,e,f,g,h = 000,000,000,000,2^i-1,255,255,255; if n(a,b,c,d,e,f,g,0) ~= n(a,b,c,d,e,f,g,1) then ma,mb,mc,md,me,mf,mg,mh = a,b,c,d,e,f,g,h end
	end
	for i=1,8 do
		a,b,c,d,e,f,g,h = 000,000,000,2^i-1,255,255,255,255; if n(a,b,c,d,e,f,g,0) ~= n(a,b,c,d,e,f,g,1) then ma,mb,mc,md,me,mf,mg,mh = a,b,c,d,e,f,g,h end
	end
	for i=1,8 do
		a,b,c,d,e,f,g,h = 000,000,2^i-1,255,255,255,255,255; if n(a,b,c,d,e,f,g,0) ~= n(a,b,c,d,e,f,g,1) then ma,mb,mc,md,me,mf,mg,mh = a,b,c,d,e,f,g,h end
	end
	for i=1,8 do
		a,b,c,d,e,f,g,h = 000,2^i-1,255,255,255,255,255,255; if n(a,b,c,d,e,f,g,0) ~= n(a,b,c,d,e,f,g,1) then ma,mb,mc,md,me,mf,mg,mh = a,b,c,d,e,f,g,h end
	end
	for i=1,8 do
		a,b,c,d,e,f,g,h = 2^i-1,255,255,255,255,255,255,255; if n(a,b,c,d,e,f,g,0) ~= n(a,b,c,d,e,f,g,1) then ma,mb,mc,md,me,mf,mg,mh = a,b,c,d,e,f,g,h end
	end
	assert(ma)
	assert(mb)
	assert(mc)
	assert(md)
	assert(me)
	assert(mf)
	assert(mg)
	assert(mh)
	maxbytes.uint64 = {ma,mb,mc,md,me,mf,mg,mh}
end

function serialize.uint64(value, endianness)
	push 'uint64'
	local data
	local tvalue = type(value)
	if tvalue=='number' then
		if value < 0 or value >= 2^64 or math.floor(value)~=value then
			error("invalid value")
		end
		local h = value % 256
		value = (value - h) / 256
		local g = value % 256
		value = (value - g) / 256
		local f = value % 256
		value = (value - f) / 256
		local e = value % 256
		value = (value - e) / 256
		local d = value % 256
		value = (value - d) / 256
		local c = value % 256
		value = (value - c) / 256
		local b = value % 256
		value = (value - b) / 256
		local a = value % 256
		if endianness=='le' then
			data = string.char(h, g, f, e, d, c, b, a)
		elseif endianness=='be' then
			data = string.char(a, b, c, d, e, f, g, h)
		else
			error("unknown endianness")
		end
	elseif tvalue=='string' then
		assert(#value==8)
		-- uint64 as string is little-endian
		if endianness=='le' then
			data = value
		elseif endianness=='be' then
			data = value:reverse()
		else
			error("unknown endianness")
		end
	else
		error("uint64 value must be a number or a string")
	end
	pop()
	return data
end

function read.uint64(stream, endianness)
	push 'uint64'
	local data,err = stream:receive(8)
	if not data then return nil,ioerror(err) end
	local a,b,c,d,e,f,g,h
	if endianness=='le' then
		h,g,f,e,d,c,b,a = string.byte(data, 1, 8)
	elseif endianness=='be' then
		a,b,c,d,e,f,g,h = string.byte(data, 1, 8)
	else
		error("unknown endianness")
	end
	local ma,mb,mc,md,me,mf,mg,mh = unpack(maxbytes.uint64)
	local value
	if a>ma or b>mb or c>mc or d>md or e>me or f>mf or g>mg or h>mh then
		-- uint64 as string is little-endian
		if endianness=='le' then
			value = data
		else
			value = data:reverse()
		end
	else
		value = ((((((a * 256 + b) * 256 + c) * 256 + d) * 256 + e) * 256 + f) * 256 + g) * 256 + h
	end
	pop()
	return value
end

------------------------------------------------------------------------------

function serialize.enum(value, enum, int_t, ...)
	push 'enum'
	if type(int_t)~='table' or select('#', ...)>=1 then
		int_t = {int_t, ...}
	end
	local ivalue
	if type(value)=='number' then
		ivalue = value
	else
		ivalue = enum[value]
	end
	assert(ivalue, "unknown enum string '"..tostring(value).."'")
	local serialize = assert(serialize[int_t[1]], "unknown integer type "..tostring(int_t[1]).."")
	local sdata,err = serialize(ivalue, unpack(int_t, 2))
	if not sdata then return nil,err end
	pop()
	return sdata
end

function read.enum(stream, enum, int_t, ...)
	push 'enum'
	if type(int_t)~='table' or select('#', ...)>=1 then
		int_t = {int_t, ...}
	end
	local read = assert(read[int_t[1]], "unknown integer type "..tostring(int_t[1]).."")
	local value,err = read(stream, unpack(int_t, 2))
	if not value then
		return nil,err
	end
	local svalue = enum[value]
	if not svalue then
		warning("unknown enum number "..tostring(value)..", keeping numerical value")
		svalue = value
	end
	pop()
	return svalue
end

------------------------------------------------------------------------------

local success,libbit = pcall(require, 'bit')
if success then

function serialize.flags(value, flagset, int_t, ...)
	push 'flags'
	if type(int_t)~='table' or select('#', ...)>=1 then
		int_t = {int_t, ...}
	end
	local ints = {}
	for flag,k in pairs(value) do
		assert(k==true, "flag has value other than true ("..tostring(k)..")")
		ints[#ints+1] = flagset[flag]
	end
	if #ints==0 then
		value = 0
	else
		value = libbit.bor(unpack(ints))
	end
	local serialize = assert(serialize[int_t[1]], "unknown integer type "..tostring(int_t[1]).."")
	local sdata,err = serialize(value, unpack(int_t, 2))
	if not sdata then return nil,err end
	pop()
	return sdata
end

function read.flags(stream, flagset, int_t, ...)
	push 'flags'
	if type(int_t)~='table' or select('#', ...)>=1 then
		int_t = {int_t, ...}
	end
	local read = assert(read[int_t[1]], "unknown integer type "..tostring(int_t[1]).."")
	local int,err = read(stream, unpack(int_t, 2))
	if not int then
		return nil,err
	end
	local value = {}
	for k,v in pairs(flagset) do
		-- ignore reverse or invalid mappings (allows use of same dict in enums)
		if type(v)=='number' and libbit.band(int, v) ~= 0 then
			value[k] = true
		end
	end
	pop()
	return value
end

end

------------------------------------------------------------------------------

function serialize.sizedbuffer(value, size_t, ...)
	push 'sizedbuffer'
	if type(size_t)~='table' or select('#', ...)>=1 then
		size_t = {size_t, ...}
	end
	local serialize = assert(serialize[size_t[1]], "unknown size type "..tostring(size_t[1]).."")
	local size = #value
	local ssize,err = serialize(size, unpack(size_t, 2))
	if not ssize then return nil,err end
	pop()
	return ssize .. value
end

function read.sizedbuffer(stream, size_t, ...)
	push 'sizedbuffer'
	if type(size_t)~='table' or select('#', ...)>=1 then
		size_t = {size_t, ...}
	end
	local read = assert(read[size_t[1]], "unknown size type "..tostring(size_t[1]).."")
	local size,err = read(stream, unpack(size_t, 2))
	if not size then return nil,err end
	if stream.length then
		assert(stream:length() >= size, "invalid sizedbuffer size, stream is too short")
	end
	local value,err = stream:receive(size)
	if not value then return nil,ioerror(err) end
	pop()
	return value
end

------------------------------------------------------------------------------

function serialize.array(value, size, value_t, ...)
	push 'array'
	if type(value_t)~='table' or select('#', ...)>=1 then
		value_t = {value_t, ...}
	end
	local serialize = assert(serialize[value_t[1]], "unknown value type "..tostring(value_t[1]).."")
	if size=='*' then
		size = #value
	end
	assert(size == #value, "provided array size doesn't match")
	local data,temp,err = ""
	for i=1,size do
		temp,err = serialize(value[i], unpack(value_t, 2))
		if not temp then return nil,err end
		data = data .. temp
	end
	pop()
	return data
end

function write.array(stream, value, size, value_t, ...)
	push 'array'
	if type(value_t)~='table' or select('#', ...)>=1 then
		value_t = {value_t, ...}
	end
	local write = assert(write[value_t[1]], "unknown value type "..tostring(value_t[1]).."")
	if size=='*' then
		size = #value
	end
	assert(size == #value, "provided array size doesn't match")
	for i=1,size do
		local success,err = write(stream, value[i], unpack(value_t, 2))
		if not success then return nil,err end
	end
	pop()
	return true
end

function read.array(stream, size, value_t, ...)
	push 'array'
	if type(value_t)~='table' or select('#', ...)>=1 then
		value_t = {value_t, ...}
	end
	local read = assert(read[value_t[1]], "unknown value type "..tostring(value_t[1]).."")
	local value = {}
	if size=='*' then
		assert(stream.length, "infinite arrays can only be read from buffers, not infinite streams")
		while stream:length() > 0 do
			local elem,err = read(stream, unpack(value_t, 2))
			if not elem then return nil,err end
			value[#value+1] = elem
		end
	else
		for i=1,size do
			local elem,err = read(stream, unpack(value_t, 2))
			if not elem then return nil,err end
			value[i] = elem
		end
	end
	pop()
	return value
end

------------------------------------------------------------------------------

function serialize.sizedvalue(value, size_t, value_t, ...)
	push 'sizedvalue'
	if type(value_t)~='table' or select('#', ...)>=1 then
		value_t = {value_t, ...}
	end
	-- get serialization functions
	local size_serialize
	if type(size_t)=='table' then
		assert(size_t[1], "size type definition array is empty")
		size_serialize = assert(serialize[size_t[1]], "unknown size type "..tostring(size_t[1]).."")
	elseif type(size_t)=='number' then
		size_serialize = size_t
	else
		error("size_t should be a type definition array or a number")
	end
	assert(type(value_t)=='table', "value type definition should be an array")
	assert(value_t[1], "value type definition array is empty")
	local value_serialize = assert(serialize[value_t[1]], "unknown value type "..tostring(value_t[1]).."")
	-- serialize value
	local svalue,err = value_serialize(value, unpack(value_t, 2))
	if not svalue then return nil,err end
	-- if value has trailing bytes append them
	if type(value)=='table' and value.__trailing_bytes then
		svalue = svalue .. value.__trailing_bytes
	end
	local size = #svalue
	if type(size_serialize)=='number' then
		assert(size==size_serialize, "value size doesn't match sizedvalue size")
		return svalue
	else
		local ssize,err = size_serialize(size, unpack(size_t, 2))
		if not ssize then return nil,err end
		pop()
		return ssize .. svalue
	end
end

function read.sizedvalue(stream, size_t, value_t, ...)
	push 'sizedvalue'
	if type(value_t)~='table' or select('#', ...)>=1 then
		value_t = {value_t, ...}
	end
	-- get serialization functions
	local size_read
	if type(size_t)=='table' then
		assert(size_t[1], "size type definition array is empty")
		size_read = assert(read[size_t[1]], "unknown size type "..tostring(size_t[1]).."")
	elseif type(size_t)=='number' then
		size_read = size_t
	else
		error("size type definition should be an array")
	end
	assert(type(value_t)=='table', "value type definition should be an array")
	assert(value_t[1], "value type definition array is empty")
	local value_read = assert(read[value_t[1]], "unknown size type "..tostring(value_t[1]).."")
	-- read size
	local size,err
	if type(size_read)=='number' then
		size = size_read
	else
		size,err = size_read(stream, unpack(size_t, 2))
	end
	if not size then return nil,err end
	-- read serialized value
	local svalue,err = stream:receive(size)
	if not svalue then return nil,ioerror(err) end
	-- build a buffer stream
	local bvalue = _M.buffer(svalue)
	-- read the value from the buffer
	local value,err = value_read(bvalue, unpack(value_t, 2))
	if not value then return nil,err end
	-- if the buffer is not empty save trailing bytes or generate an error
	if bvalue:length() > 0 then
		local msg = "trailing bytes in sized value not read by value serializer "..tostring(value_t[1])..""
		if type(value)=='table' then
			warning(msg)
			value.__trailing_bytes = bvalue:receive("*a")
		else
			error(msg)
		end
	end
	pop()
	return value
end

------------------------------------------------------------------------------

function serialize.sizedarray(value, size_t, value_t, ...)
	push 'sizedarray'
	if type(value_t)~='table' or select('#', ...)>=1 then
		value_t = {value_t, ...}
	end
	assert(type(size_t)=='table', "size type definition should be an array")
	assert(size_t[1], "size type definition array is empty")
	assert(type(value_t)=='table', "value type definition should be an array")
	assert(value_t[1], "value type definition array is empty")
	local data,temp,err = ""
	-- get serialization functions
	local size_serialize = assert(serialize[size_t[1]], "unknown size type "..tostring(size_t[1]).."")
	-- serialize size
	local size = #value
	temp,err = size_serialize(size, unpack(size_t, 2))
	if not temp then return nil,err end
	data = data .. temp
	-- serialize array itself
	temp,err = serialize.array(value, size, unpack(value_t))
	if not temp then return nil,err end
	data = data .. temp
	-- return size..array
	pop()
	return data
end

function write.sizedarray(stream, value, size_t, value_t, ...)
	push 'sizedarray'
	if type(value_t)~='table' or select('#', ...)>=1 then
		value_t = {value_t, ...}
	end
	assert(type(size_t)=='table', "size type definition should be an array")
	assert(size_t[1], "size type definition array is empty")
	assert(type(value_t)=='table', "value type definition should be an array")
	assert(value_t[1], "value type definition array is empty")
	local success,err
	-- get serialization functions
	local size_write = assert(write[size_t[1]], "unknown size type "..tostring(size_t[1]).."")
	-- write size
	local size = #value
	success,err = size_write(stream, size, unpack(size_t, 2))
	if not success then return nil,err end
	-- write array itself
	success,err = write.array(stream, value, size, unpack(value_t))
	if not success then return nil,err end
	-- return success
	pop()
	return true
end

function read.sizedarray(stream, size_t, value_t, ...)
	push 'sizedarray'
	if type(value_t)~='table' or select('#', ...)>=1 then
		value_t = {value_t, ...}
	end
	assert(type(size_t)=='table', "size type definition should be an array")
	assert(size_t[1], "size type definition array is empty")
	assert(type(value_t)=='table', "value type definition should be an array")
	assert(value_t[1], "value type definition array is empty")
	-- get serialization functions
	local size_read = assert(read[size_t[1]], "unknown size type "..tostring(size_t[1]).."")
	-- read size
	local size,err = size_read(stream, unpack(size_t, 2))
	if not size then return nil,err end
	-- read array
	local value,err = read.array(stream, size, unpack(value_t))
	if not value then return nil,err end
	-- return array
	pop()
	return value
end

------------------------------------------------------------------------------

function serialize.cstring(value)
	push 'cstring'
	assert(not value:find('\0'), "cannot serialize a string containing embedded zeros as a C string")
	pop()
	return value..'\0'
end

function read.cstring(stream)
	push 'cstring'
	local bytes = {}
	repeat
		local byte = read.uint8(stream)
		bytes[#bytes+1] = byte
	until byte==0
	pop()
	return string.char(unpack(bytes, 1, #bytes-1)) -- remove trailing 0
end

------------------------------------------------------------------------------

local success,libstruct = pcall(require, 'struct')
if success then

function serialize.float(value, endianness)
	push 'float'
	local format
	if endianness=='le' then
		format = "<f"
	elseif endianness=='be' then
		format = ">f"
	else
		error("unknown endianness")
	end
	local data = libstruct.pack(format, value)
	if #data ~= 4 then
		error("struct library \"f\" format doesn't correspond to a 32 bits float")
	end
	pop()
	return data
end

function read.float(stream, endianness)
	push 'float'
	local format
	if endianness=='le' then
		format = "<f"
	elseif endianness=='be' then
		format = ">f"
	else
		error("unknown endianness")
	end
	local data,err = stream:receive(4)
	if not data then return nil,ioerror(err) end
	pop()
	return libstruct.unpack(format, data)
end

------------------------------------------------------------------------------

function serialize.double(value, endianness)
	push 'double'
	local format
	if endianness=='le' then
		format = "<d"
	elseif endianness=='be' then
		format = ">d"
	else
		error("unknown endianness")
	end
	local data = libstruct.pack(format, value)
	if #data ~= 8 then
		error("struct library \"f\" format doesn't correspond to a 64 bits float")
	end
	pop()
	return data
end

function read.double(stream, endianness)
	push 'double'
	local format
	if endianness=='le' then
		format = "<d"
	elseif endianness=='be' then
		format = ">d"
	else
		error("unknown endianness")
	end
	local data,err = stream:receive(8)
	if not data then return nil,ioerror(err) end
	local value,err = libstruct.unpack(format, data)
	if not value then return nil,err end
	pop()
	return value
end

end

------------------------------------------------------------------------------

function serialize.bytes(value, count)
	push 'bytes'
	assert(type(value)=='string', "bytes value is not a string")
	assert(#value==count or count=='*', "byte string has not the correct length")
	pop()
	return value
end

function read.bytes(stream, count)
	push 'bytes'
	if count=='*' then
		assert(stream.length, "infinite arrays can only be read from buffers, not infinite streams")
		count = stream:length()
	end
	local data,err = stream:receive(count)
	if not data then return nil,ioerror(err) end
	pop()
	return data
end

------------------------------------------------------------------------------

function serialize.bytes2hex(value, count)
	push 'bytes2hex'
	assert(type(value)=='string', "bytes2hex value is not a string")
	value = util.hex2bin(value)
	assert(#value==count, "byte string has not the correct length")
	pop()
	return value
end

function read.bytes2hex(stream, count)
	push 'bytes2hex'
	local value,err = stream:receive(count)
	if not value then return value,ioerror(err) end
	pop()
	return util.bin2hex(value)
end

------------------------------------------------------------------------------

function serialize.bytes2base32(value, count)
	push 'bytes2base32'
	assert(type(value)=='string', "bytes2base32 value is not a string")
	value = util.base322bin(value)
	assert(#value==count, "byte string has not the correct length")
	return value
end

function read.bytes2base32(stream, count)
	push 'bytes2base32'
	local value,err = stream:receive(count)
	if not value then return value,ioerror(err) end
	pop()
	return util.bin2base32(value)
end

------------------------------------------------------------------------------

function serialize.boolean(value, int_t, ...)
	push 'boolean'
	if type(int_t)~='table' or select('#', ...)>=1 then
		int_t = {int_t, ...}
	end
	if type(value)=='boolean' then
		value = value and 1 or 0
	end
	local serialize = assert(serialize[int_t[1]], "unknown integer type "..tostring(int_t[1]).."")
	local sdata,err = serialize(value, unpack(int_t, 2))
	if not sdata then return nil,err end
	pop()
	return sdata
end

function read.boolean(stream, int_t, ...)
	push 'boolean'
	if type(int_t)~='table' or select('#', ...)>=1 then
		int_t = {int_t, ...}
	end
	local read = assert(read[int_t[1]], "unknown integer type "..tostring(int_t[1]).."")
	local value,err = read(stream, unpack(int_t, 2))
	if not value then return nil,err end
	local result
	if value==0 then
		result = false
	elseif value==1 then
		result = true
	else
		warning("boolean value is not 0 or 1, it's "..tostring(value))
		result = value
	end
	pop()
	return result
end

alias.boolean8 = {'boolean', 'uint8'}

------------------------------------------------------------------------------

function serialize._struct(value, fields)
	local data = ""
	for _,field in ipairs(fields) do
		local name,type = field[1],field[2]
		local serialize = assert(serialize[type], "no function to read field of type "..tostring(type))
		local temp,err = serialize(value[name], select(3, unpack(field)))
		if not temp then return nil,err end
		data = data .. temp
	end
	return data
end

function serialize.struct(value, fields)
	push 'struct'
	local data,err = serialize._struct(value, fields)
	if data==nil then return nil,err end
	pop()
	return data
end

function write.struct(stream, value, fields)
	local data = ""
	for _,field in ipairs(fields) do
		local name,type = field[1],field[2]
		local write = assert(write[type], "no function to read field of type "..tostring(type))
		local success,err = write(stream, value[name], select(3, unpack(field)))
		if not success then return nil,err end
	end
	return true
end

function write.struct(stream, value, fields)
	push 'struct'
	local success,err = write._struct(stream, value, fields)
	if not success then return nil,err end
	pop()
	return true
end

function read._struct(stream, fields)
	local object = {}
	for _,field in ipairs(fields) do
		local name,type = field[1],field[2]
		push(name)
		local read = assert(read[type], "no function to read field of type "..tostring(type))
		local value,err = read(stream, select(3, unpack(field)))
		if value==nil then return nil,err end
		object[name] = value
		pop()
	end
	return object
end

function read.struct(stream, fields)
	push 'struct'
	local object,err = read._struct(stream, fields)
	if not object then return nil,err end
	pop()
	return object
end

------------------------------------------------------------------------------

local cyield = coroutine.yield
local cwrap,unpack = coroutine.wrap,unpack

function serialize.fstruct(object, f, ...)
	push 'fstruct'
	local params = {n=select('#', ...), ...}
	local str = ""
	local wrapper = setmetatable({}, {
		__index = object,
		__newindex = object,
		__call = function(self, field, ...)
			if select('#', ...)>0 then
				local type = ...
				local serialize = serialize[type]
				if not serialize then error("no function to serialize field of type "..tostring(type)) end
				local temp,err = serialize(object[field], select(2, ...))
				if not temp then cyield(nil, err) end
				str = str .. temp
			else
				return function(type, ...)
					local serialize = serialize[type]
					if not serialize then error("no function to serialize field of type "..tostring(type)) end
					local temp,err = serialize(object[field], ...)
					if not temp then cyield(nil, err) end
					str = str .. temp
				end
			end
		end,
	})
	local coro = cwrap(function()
		f(wrapper, wrapper, unpack(params, 1, params.n))
		return true
	end)
	local success,err = coro()
	if not success then return nil,err end
	pop()
	return str
end

function write.fstruct(stream, object, f, ...)
	push 'fstruct'
	local params = {n=select('#', ...), ...}
	local wrapper = setmetatable({}, {
		__index = object,
		__newindex = object,
		__call = function(self, field, ...)
			if select('#', ...)>0 then
				local type = ...
				local write = write[type]
				if not write then error("no function to write field of type "..tostring(type)) end
				local success,err = write(stream, object[field], select(2, ...))
				if not success then cyield(nil, err) end
			else
				return function(type, ...)
					local write = write[type]
					if not write then error("no function to write field of type "..tostring(type)) end
					local success,err = write(stream, object[field], ...)
					if not success then cyield(nil, err) end
				end
			end
		end,
	})
	local coro = cwrap(function()
		f(wrapper, wrapper, unpack(params, 1, params.n))
		return true
	end)
	local success,err = coro()
	if not success then return nil,err end
	pop()
	return true
end

function read.fstruct(stream, f, ...)
	push 'fstruct'
	local params = {n=select('#', ...), ...}
	local object = {}
	local wrapper = setmetatable({}, {
		__index = object,
		__newindex = object,
		__call = function(self, field, ...)
			if select('#', ...)>0 then
				local type = ...
				local read = read[type]
				if not read then error("no function to read field of type "..tostring(type)) end
				local value,err = read(stream, select(2, ...))
				if value==nil then cyield(nil, err) end
				object[field] = value
			else
				return --[[util.wrap("field "..field, ]]function(type, ...)
					local read = read[type]
					if not read then error("no function to read field of type "..tostring(type)) end
					local value,err = read(stream, ...)
					if value==nil then cyield(nil, err) end
					object[field] = value
				end--[[)]]
			end
		end,
	})
	local coro = cwrap(function()
		f(wrapper, wrapper, unpack(params, 1, params.n))
		return true
	end)
	local success,err = coro()
	if not success then return nil,err end
	pop()
	return object
end

------------------------------------------------------------------------------

serialize.fields = serialize.struct

function read.fields(stream, object, fields)
	local part,err = read.struct(stream, fields)
	if not part then return nil,err end
	for k,v in pairs(part) do
		object[k] = v
	end
	return true
end

------------------------------------------------------------------------------

setmetatable(serialize, {__index=function(self,k)
	local struct = struct[k]
	if struct then
		local serialize = function(object)
			return _M.serialize.struct(object, struct)
		end
		self[k] = serialize
		return serialize
	end
	local fstruct = fstruct[k]
	if fstruct then
		local serialize = function(object, ...)
			return _M.serialize.fstruct(object, fstruct, ...)
		end
		self[k] = serialize
		return serialize
	end
	local alias = alias[k]
	if alias then
		assert(type(alias)=='table', "alias type definition should be an array")
		assert(alias[1], "alias type definition array is empty")
		local serialize = function(value)
			local alias_serialize = assert(serialize[alias[1]], "unknown alias type "..tostring(alias[1]).."")
			return alias_serialize(value, unpack(alias, 2))
		end
		self[k] = serialize
		return serialize
	end
end})

setmetatable(read, {__index=function(self,k)
	local struct = struct[k]
	if struct then
		local read = function(stream)
			push("struct<"..tostring(k)..">")
			local value,err = _M.read._struct(stream, struct)
			if value==nil then return nil,err end
			pop()
			return value
		end
		self[k] = read
		return read
	end
	local fstruct = fstruct[k]
	if fstruct then
		local read = function(stream, ...)
			return _M.read.fstruct(stream, fstruct, ...)
		end
		self[k] = read
		return read
	end
	local alias = alias[k]
	if alias then
		assert(type(alias)=='table', "alias type definition should be an array")
		assert(alias[1], "alias type definition array is empty")
		local read = function(stream)
			local alias_read = assert(read[alias[1]], "unknown alias type "..tostring(alias[1]).."")
			return alias_read(stream, unpack(alias, 2))
		end
		self[k] = read
		return read
	end
end})

local pack = function(...) return {n=select('#', ...), ...} end

setmetatable(write, {__index=function(self,k)
	local struct = struct[k]
	if struct then
		local write = function(stream, object)
			push("struct<"..tostring(k)..">")
			local result,err = _M.write.struct(stream, object, struct)
			if not result then return nil,err end
			pop()
			return result
		end
		local wrapper = util.wrap("write."..k, write)
		self[k] = wrapper
		return wrapper
	end
	local fstruct = fstruct[k]
	if fstruct then
		local write = function(stream, object, ...)
			return select(1, _M.write.fstruct(stream, object, fstruct, ...))
		end
		local wrapper = util.wrap("write."..k, write)
		self[k] = wrapper
		return wrapper
	end
	local alias = alias[k]
	if alias then
		assert(type(alias)=='table', "alias type definition should be an array")
		assert(alias[1], "alias type definition array is empty")
		local write = function(stream, value)
			local write = assert(write[alias[1]], "unknown alias type "..tostring(alias[1]).."")
			local wrapper = util.wrap("write."..alias[1], write)
			return select(1, wrapper(stream, value, unpack(alias, 2)))
		end
		local wrapper = util.wrap("write."..k, write)
		self[k] = wrapper
		return wrapper
	end
	local serialize = serialize[k]
	if serialize then
		local write = function(stream, ...)
			local data,err = serialize(...)
			if not data then
				return nil,err
			end
			local success,err = stream:send(data)
			if not success then return nil,ioerror(err) end
			return true
		end
		self[k] = write
		return write
	end
end})

-- force function instanciation for all known types
for type in pairs(serialize) do
	local _ = write[type]
end
for type in pairs(struct) do
	local _ = write[type] -- this forces write and serialize creation
	local _ = read[type]
end

------------------------------------------------------------------------------

local buffer_methods = {}
local buffer_mt = {__index=buffer_methods}

function buffer(data)
	return setmetatable({data=data}, buffer_mt)
end

local smatch = string.match
function buffer_methods:receive(pattern, prefix)
	local prefix = prefix or ""
	local data = self.data
	if not data then
		return nil,"end of buffer"
	end
	if smatch(pattern, "^%*a") then
		self.data = nil
		return prefix..data
	elseif smatch(pattern, "^%*l") then
		return nil,"unsupported pattern"
	elseif type(pattern)=='number' then
		if pattern~=math.floor(pattern) or pattern < 0 then
			return nil,"invalid numerical pattern"
		end
		if pattern > #data then
			self.data = nil
			return nil,"end of buffer",prefix..data
		elseif pattern == #data then
			self.data = nil
			return prefix..data
		else
			self.data = data:sub(pattern+1)
			return prefix..data:sub(1,pattern)
		end
	else
		return nil,"unknown pattern"
	end
end

function buffer_methods:length()
	local data = self.data
	return data and #data or 0
end

------------------------------------------------------------------------------

local filestream_methods = {}
local filestream_mt = {__index=filestream_methods}
local filestream_methods_verbose = {}
local filestream_mt_verbose = {__index=filestream_methods_verbose}

function filestream(file, verbose)
	-- assume the passed object behaves like a file
--	if io.type(file)~='file' then
--		error("bad argument #1 to filestream (file expected, got "..(io.type(file) or type(file))..")", 2)
--	end
	local self
	if verbose then
		self = setmetatable({file=file}, filestream_mt_verbose)
		self.len = self:length()
		self.cur = 0
		io.write(string.format("read: %.2f%% (%d / %d)", 0, 0, self.len))
	else
		self = setmetatable({file=file}, filestream_mt)
	end
	return self
end

function filestream_methods:receive(pattern, prefix)
	local prefix = prefix or ""
	local file = self.file
	local data,err = file:read(pattern)
	if not data then return data,err end
	return prefix..data
end

function filestream_methods:send(data)
	return self.file:write(data)
end

function filestream_methods:length()
	local cur = self.file:seek()
	local len = self.file:seek('end')
	self.file:seek('set', cur)
	return len - cur
end

function filestream_methods:skip(nbytes)
	self.file:seek('cur', nbytes)
end

for k,v in pairs(filestream_methods) do
	filestream_methods_verbose[k] = v
end

function filestream_methods_verbose:receive(pattern, prefix)
	local prefix = prefix or ""
	local file = self.file
	local data,err = file:read(pattern)
	if not data then return data,err end
	self.cur = self.cur + #data
	io.write(string.format("\rread: %.2f%% (%d / %d)", (self.cur/self.len)*100, self.cur, self.len))
	return prefix..data
end

function filestream_methods_verbose:skip(nbytes)
	self.file:seek('cur', nbytes)
	self.cur = self.cur + nbytes
	io.write(string.format("\rread: %.2f%% (%d / %d)", (self.cur/self.len)*100, self.cur, self.len))
end

--[[
Copyright (c) 2009 Jérôme Vuarand

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
]]

-- vi: ts=4 sts=4 sw=4 encoding=utf-8
