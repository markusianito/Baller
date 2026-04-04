-->> ClientBegin.lua
--> Starts all SM controllers, and setups stuff for client.
--> Scripted by Marcos Saenz.

print("Hello world, from client!")

local tws = game:GetService("TweenService");
local content = game:GetService("ContentProvider");
local storage = game:GetService("ReplicatedStorage");
local bin = storage:WaitForChild("Packages");
local knit = require(bin:WaitForChild("Knit"):WaitForChild("KnitClient"));


--> ControllersBegin


knit.AddControllers(game:GetService("StarterPlayer").StarterPlayerScripts:WaitForChild("Controllers"));
knit.AddControllers(game:GetService("StarterPlayer").StarterPlayerScripts:WaitForChild("Listeners"));

knit.Start():andThen(function()
	print(`Knit Started in {knit.Player.Name}`);
end):catch(function(err)
	warn(err);
	knit.Player:Kick("Failed to start client services, exit code 1");
end)
