if(#arg == 0) then
  error("Wrong usage lua module path should be provided.")
end

package.path = arg[1].."?.lua;"..package.path

print("package.path: "..package.path)

local utils = require("utils")

if(#arg < 2) then
  log("Missing input folder, please provide input.")
  return;
end

local fname = arg[1]

log("Searching duplicates in folder '",fname,"'...")

local lfs = require("lfs")
log("Current working directory: ", lfs.currentdir())

local cfgFile="config.lua"

-- Load the config file:
-- local cfg=dofile(cfgFile)

log("Done.")
