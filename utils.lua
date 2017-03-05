local serpent = require("serpent")

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

function dirtree(dir, cfg, basedir)
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
          log("Ignoring entry ", entry:sub(#basedir+1))
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

local saveHash = function(key, hash, state)
  -- check if this hash is already in the list:
  state.hashes[hash] = state.hashes[hash] or {}
  table.insert(state.hashes[hash], key)
end

local checkDuplicates = function(state)
  local found = false

  for hash,val in pairs(state.hashes) do
    if #val > 1 then
      log("\n=> Found duplicates with hash ", hash,":\n", serpent.block(val,{comment=false}))
      found = true
    end
  end

  if not found then
    log("No duplicates found.")
  end
end

local checkEntry = function(attr, fname, dmap, state)
  dmap.files = dmap.files or {}
  dmap.folders = dmap.folders or {}
  
  local list = dmap.files

  local bdir = dmap.basedir;
  local key = fname:sub(#bdir+1)

  if attr.mode == "directory" then
    -- This folder is found so we should remove it from the previous folders list:
    -- eg. we only keep the not found/removed folders in that list
    state.folders[key] = nil

    list = dmap.folders

    local desc = list[key]
    if not desc then
      desc = {}
      list[key] = desc
    end

    -- We cannot rely on the modification date for a folder, so we have to concatenate all the content hashes
    -- Taking into account that the "removed files" are still in the current file list.
    -- But we can assume that the hash for all the valid files have been updated already.
    local hashes = {}
    local prefix = key.."/"
    local nf = #prefix 

    for k,v in pairs(dmap.files) do
      -- Check if this file is in this folder:
      -- And if it was not removed.
      if k:sub(1, nf) == prefix and not state.files[k] then
        table.insert(hashes, v.hash)
      end
    end

    -- sort all hashes:
    table.sort(hashes)

    -- Concatenate all the hashes in a string:
    local str = table.concat(hashes)

    -- and hash this string:
    local hash = md5.sumhexa(str)

    -- Chekc if this folder was updated:
    if desc.hash and desc.hash ~= hash then
      log("Content for folder ", key," was updated.")
    end

    desc.hash = hash

    saveHash(key, desc.hash, state)
    return
  end

  if attr.mode == "file" then
    -- This file is found so we should remove it from the previous files list:
    -- eg. we only keep the not found/removed files in that list
    state.files[key] = nil

    -- Retrieve the record on this element if any:
    local desc = list[key]
    if not desc then
      desc = {}
      list[key] = desc
    end

    if not desc.time or desc.time~=attr.modification then
      if desc.time then
        log("Content from ",key," was updated.")
      end

      -- Compute the file hash:
      local hash = computeFileHash(fname)

      -- Add this hash for the file:
      desc.hash = hash

      -- Write the last modification time:
      desc.time = attr.modification
    end

    saveHash(key, desc.hash, state)
    return
  end

  log("Ignoring entry ",key," of type ", attr.mode)
end

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

local processRemoved = function(dmap, state)
  -- Process all the removed files:
  for k,v in pairs(state.files) do
    log("File ", k, " was removed.")
    dmap.files[k] = nil
  end
  for k,v in pairs(state.folders) do
    log("Folder ", k, " was removed.")
    dmap.folders[k] = nil
  end
end

return {
  dirtree = dirtree,
  checkEntry = checkEntry,
  writeData = writeData,
  processRemoved = processRemoved,
  checkDuplicates = checkDuplicates
}

