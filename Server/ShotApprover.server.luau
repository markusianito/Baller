
local shared = game:GetService("ReplicatedStorage");
local lib = shared:WaitForChild("Packages");

local net = require(lib:WaitForChild("Net"));


local reqshot:RemoteFunction=net:RemoteFunction("RequireShot");


reqshot.OnServerInvoke = function(plr,ball)
	local balls = workspace.Balls:GetChildren()
	if ball == workspace.Balls:GetAttribute("CueBall") then
		print("Disparo recibido")
		for _,b in pairs(balls) do
			if b:IsA("Part") then
				if b.CollisionGroup == "Balls" then
					b:SetNetworkOwner(plr);
				end
			end
		end
		print("Aprobacion de disparo emitida")
		return true;
	end 
end