if(#arg == 0) then
  error("Wrong usage lua module path should be provided.")
end

package.path = arg[1].."?.lua;"..package.path
package.cpath = arg[1].."bin/?.so;"..arg[1].."bin/?.dll;"..package.cpath

-- print("package.path: "..package.path)

local utils = require("utils")

local fname = "." -- by default process current folder

if(#arg >= 2) then
  -- Override the search folder!
  fname = arg[2]
end

local lfs = require("lfs")
-- log("Current working directory: ", lfs.currentdir())

fname = lfs.currentdir().."/"..fname
log("Searching duplicates in folder '",fname,"'...")

local cfgFile="config.lua"

package.path = fname.."/?.lua;"..package.path

-- Load the configuration:
local cfg = require("dedup_config")

-- Init the data map:
local dmap = {}

-- Load the available data if any:
local dfile = fname.."/dedup_data.lua"

if(file_exists(dfile)) then
  log("Loading existing data map...")
  dmap = dofile(dfile)
  if not dmap then
    log("Could not load data from existing file. Rebuilding...")
    dmap = {}
  end
end

dmap.basedir = fname.."/"

-- keep the list of previous files and folders if any:
local state = {}

state.files = {}
state.folders = {}

for k,v in pairs(dmap.files or {}) do
  state.files[k] = true
end
for k,v in pairs(dmap.folders or {}) do
  state.folders[k] = true
end

-- Keep a list of hashes:
state.hashes = {}

for filename, attr in utils.dirtree(fname, cfg, dmap.basedir) do
  -- Check the provided entry:
  -- log("Found ",attr.mode,": ",filename)
  utils.checkEntry(attr, filename, dmap, state)
end

-- remove the deleted files and folders
utils.processRemoved(dmap, state)

-- Write the data file:
utils.writeData(dmap, dfile)

-- Check the current duplicates:
utils.checkDuplicates(state, cfg)

-- log("Done.")
