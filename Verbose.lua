Verbose = {}

verbose = false
function vprint(...)
	if not verbose then return end
	print(...)
end
