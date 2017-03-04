
-- Common utility elements to write log outputs conviniently:
local writtenTables = {};
local currentLevel = 0;
local maxLevel = 4;
local indentStr="  ";
local indent=0;

function pushIndent()
	indent = indent+1
end

function popIndent()
	indent = math.max(0,indent-1)
end

function incrementLevel()
	currentLevel = math.min(currentLevel+1,maxLevel)
	return currentLevel~=maxLevel; -- return false if we are on the max level.
end

function decrementLevel()
	currentLevel = math.max(currentLevel-1,0)
end

--- Write a table to the log stream.
function writeTable(t)
	local msg = "" -- we do not add the indent on the first line as this would 
	-- be a duplication of what we already have inthe write function.
	
	local id = tostring(t);
	
	if writtenTables[t] then
		msg = id .. " (already written)"
	else
		msg = id .. " {\n"
		
		-- add the table into the set:
		writtenTables[t] = true
		
		pushIndent()
		if incrementLevel() then
			local quote = ""
			for k,v in pairs(t) do
				quote = type(v)=="string" and not tonumber(v) and '"' or ""
				msg = msg .. string.rep(indentStr,indent) .. tostring(k) .. " = ".. quote .. writeItem(v) .. quote .. ",\n" -- 
			end
			decrementLevel()
		else
			msg = msg .. string.rep(indentStr,indent) .. "(too many levels)";
		end
		popIndent()
		msg = msg .. string.rep(indentStr,indent) .. "}"
	end
	
	return msg;
end

--- Write a single item as a string.
function writeItem(item)
	if type(item) == "table" then
		-- concatenate table:
		return item.__tostring and tostring(item) or writeTable(item)
	elseif item==false then
		return "false";
	else
		-- simple concatenation:
		return tostring(item);
	end
end

--- Write input arguments as a string.
function write(...)
	writtenTables = {};
	currentLevel = 0
	
	local msg = string.rep(indentStr,indent);	
	local num = select('#', ...)
	for i=1,num do
		local v = select(i, ...)
		msg = msg .. (v~=nil and writeItem(v) or "nil")
	end
	
	return msg;
end

_G.log = function(...)
  print(write(...))
end

-- see if the file exists
function file_exists(file)
  local f = io.open(file, "rb")
  if f then f:close() end
  return f ~= nil
end

return {

}

