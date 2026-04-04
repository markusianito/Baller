-->> ServerBegin.lua
--> Starts all services scripts
--> Scripted by Marcos Saenz.

print("Hello world, from Server!")

local players = game:GetService("Players")
local sss = game:GetService("ServerScriptService")
local storage = game:GetService("ReplicatedStorage");
local bin = storage.Packages;
local knit = require(bin.Knit);
local net = require(bin.Net);
local sv = require(script.Server);


local ok = true;
local CloseServer = function()
	ok = false;
	sv.ShutDownServer(0x1)
end


xpcall(function()
	knit.AddServices(sss.Services);
	knit.AddServices(sss.Providers);
end, CloseServer)



if ok then
	knit.Start():andThen(function()
		print("Knit Started");
	end):catch(CloseServer)
else
	return
end