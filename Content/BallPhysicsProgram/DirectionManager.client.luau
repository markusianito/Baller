local shotted:BindableFunction = script.Parent.Parent:WaitForChild("PoolEvents"):WaitForChild("ShotSuccess");
local baller = require(game.ReplicatedStorage:WaitForChild("PoolModules"):WaitForChild("Baller"))

local VISIBLE_POINTS = true;
local SILENT = false;
local RECURSIVE = false;
local LIMITS = workspace:WaitForChild("Table")

local dirInstances = {}

repeat task.wait() until #workspace:WaitForChild("Balls"):GetChildren() == workspace:WaitForChild("Balls"):GetAttribute("Mode")

for _,v in pairs(workspace:WaitForChild("Balls"):GetChildren()) do
	dirInstances[v.Name] = baller.NewDirectional(v, RECURSIVE, LIMITS);
end

shotted.OnInvoke = function(cball, vel, shotCF, velocity)
	local sc, err = pcall(function()
		dirInstances[cball.Name]:StartDirection(vel, shotCF, VISIBLE_POINTS, SILENT);
		task.wait(0.1)
		cball.AssemblyLinearVelocity = vel;

		print(dirInstances[cball.Name])
		repeat wait() until not baller.IsMoving(cball);

		dirInstances[cball.Name]:StopDirection(true);
	end)
	
	if not sc then
		warn("Uncharged")
		warn(err)
	end
end