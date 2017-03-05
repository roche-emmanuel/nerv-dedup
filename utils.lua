local serpent = require("serpent")
require "lfs"

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
  io.write(write(...).."\n")
  io.flush()
  -- print(write(...))
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
          if not attr then
            log("[ERROR]: Cannot retrieve attributes for entry ".. entry)
          else
            if attr.mode == "directory" then
              yieldtree(entry)
            end
            coroutine.yield(entry,attr)
          end
        end
      end
    end
  end

  return coroutine.wrap(function() yieldtree(dir) end)
end

-- cf. https://luapower.com/md5
local md5 = require("md5")
local glue = require("glue")

local computeFileHash = function(fname)
  
  -- local m = md5.new()
  local m = md5.digest()
  local file = io.open(fname, "rb")
  while true do
    local chunk = file:read(64*1024) -- 64kB at a time
    if not chunk then break end
    -- m:update(chunk)
    m(chunk)
  end

  -- return md5.tohex(m:finish())
  return glue.tohex(m())
end

local saveHash = function(key, hash, state)
  -- check if this hash is already in the list:
  state.hashes[hash] = state.hashes[hash] or {}
  table.insert(state.hashes[hash], key)
end

local checkDuplicates = function(state, cfg)
  local found = false

  local tt = {}
  local emp = ""

  for hash,val in pairs(state.hashes) do
    if hash == "" then
      if cfg.remove_empty_folders then
        for _,folder in ipairs(val) do
          log("Removing empty folder: ", folder)
          lfs.rmdir(folder)
        end
      else
        emp = "\n\n=> List of empty folders: ".. serpent.block(val,{comment=false})
      end
    elseif #val > 1 then
      table.insert(tt, "\n\n=> Found duplicates with hash "..hash..":\n")
      table.insert(tt, serpent.block(val,{comment=false}))
      found = true
    end
  end

  if not found then
    log("No duplicates found.")
    -- Remove the dedup file log if any:
    if(file_exists("dedup.log")) then
      os.remove("dedup.log")
    end
  else
    local str = table.concat(tt)..emp
    log(str)
    f = io.open("dedup.log","w")
    f:write(str)
    f:close();
  end
end

local checkEntry = function(attr, fname, dmap, state)
  dmap.files = dmap.files or {}
  dmap.times = dmap.times or {}
  dmap.folders = dmap.folders or {}
  
  local list = dmap.files

  local bdir = dmap.basedir;
  local key = fname:sub(#bdir+1)

  if attr.mode == "directory" then
    -- This folder is found so we should remove it from the previous folders list:
    -- eg. we only keep the not found/removed folders in that list
    state.folders[key] = nil

    list = dmap.folders

    local phash = list[key]

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
        -- Ensure that this is a direct file:
        local suffix = k:sub(nf+1) 
        if not suffix:find("/") and not suffix:find("\\") then 
          table.insert(hashes, v)
        end
      end
    end

    for k,v in pairs(dmap.folders) do
      -- Check if this file is in this folder:
      -- And if it was not removed.
      if k:sub(1, nf) == prefix and not state.folders[k] then
        -- Ensure that this is a direct file:
        local suffix = k:sub(nf+1) 
        if not suffix:find("/") and not suffix:find("\\") then 
          table.insert(hashes, v)
        end
      end
    end

    -- sort all hashes:
    table.sort(hashes)

    -- Concatenate all the hashes in a string:
    local str = table.concat(hashes)

    -- if the content hashes are empty, this means we have no content in this folder.
    -- In that case we use an emtpy hash:

    -- and hash this string:
    -- local hash = str=="" and "" or md5.sumhexa(str)
    local hash = str=="" and "" or glue.tohex(md5.sum(str))

    -- Chekc if this folder was updated:
    if phash and phash ~= hash then
      log("Content for folder ", key," was updated.")
    end

    list[key] = hash

    saveHash(key, hash, state)
    return
  end

  if attr.mode == "file" then
    -- This file is found so we should remove it from the previous files list:
    -- eg. we only keep the not found/removed files in that list
    state.files[key] = nil

    -- Retrieve the record on this element if any:
    local phash = list[key]
    local ptime = dmap.times[key]

    if not ptime or ptime~=attr.modification then
      if ptime then
        log("Content from ",key," was updated.")
      end

      -- Compute the file hash:
      log("Computing hash for file ", key,"...")
      local hash = computeFileHash(fname)

      -- Add this hash for the file:
      phash = hash
      list[key] = hash

      -- Write the last modification time:
      dmap.times[key] = attr.modification
    end

    saveHash(key, phash, state)
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

