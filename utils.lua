
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

local isIgnored = function(entry, cfg)
  -- Check the entry against all the ignore patterns:
  for _,pat in ipairs(cfg.ignored or {}) do
    if entry:match(pat) then
      return true
    end
  end

  return false
end

-- cf. http://lua-users.org/wiki/DirTreeIterator
require "lfs"

function dirtree(dir, cfg)
  assert(dir and dir ~= "", "directory parameter is missing or empty")
  if string.sub(dir, -1) == "/" or string.sub(dir, -1) == "\\" then
    dir=string.sub(dir, 1, -2)
  end

  local function yieldtree(dir)
    for entry in lfs.dir(dir) do
      if entry ~= "." and entry ~= ".." then
        entry=dir.."/"..entry
        -- Check if this entry should be ignored:
        if isIgnored(entry, cfg) then
          log("Ignoring entry ", entry)
        else
          local attr=lfs.attributes(entry)
          -- Return all the content before returning the folder itself:
          if attr.mode == "directory" then
            yieldtree(entry)
          end
          coroutine.yield(entry,attr)
        end
      end
    end
  end

  return coroutine.wrap(function() yieldtree(dir) end)
end

local md5 = require("md5")

local computeFileHash = function(fname)
  
  local m = md5.new()
  local file = io.open(fname, "rb")
  while true do
    local chunk = file:read(16*1024) -- 16kB at a time
    if not chunk then break end
    m:update(chunk)
  end

  return md5.tohex(m:finish())
end

local checkEntry = function(attr, fname, dmap)
  dmap.files = dmap.files or {}
  dmap.folders = dmap.folders or {}
  
  local list = dmap.files

  local bdir = dmap.basedir;
  local key = fname:sub(#bdir+1)

  if attr.mode == "directory" then
    list = dmap.folders
    return
  end

  if attr.mode == "file" then
    -- Retrieve the record on this element if any:
    local desc = list[key]
    if not desc then
      desc = {}
      list[key] = desc
    end

    if not desc.time or desc.time~=attr.modification then
      if desc.time then
        log("Content from ",fname," was updated.")
      end

      -- Compute the file hash:
      local hash = computeFileHash(fname)

      -- Add this hash for the file:
      desc.hash = hash

      -- Write the last modification time:
      desc.time = attr.modification
    end

    return
  end

  log("Ignoring entry ",fname," of type ", attr.mode)
end

local serpent = require("serpent")

local writeData = function(data, fname)
  if file_exists(fname) then
    -- Make a backup:
    local f = io.open(fname,"r")
    local str = f:read("*a")
    f:close()
    f = io.open(fname..".bak","w")
    f:write(str)
    f:close()
  end

  local f = io.open(fname,"w")
  f:write("return "..serpent.block(data,{comment=false}))
  f:close()
end

return {
  dirtree = dirtree,
  checkEntry = checkEntry,
  writeData = writeData
}

