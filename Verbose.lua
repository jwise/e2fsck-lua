--
-- verbose.lua
-- A silly way to encapsulate verbose print statements
-- myfsck, Joshua Wise
--

Verbose = {}

verbose = false
function vprint(...)
	if not verbose then return end
	print(...)
end
