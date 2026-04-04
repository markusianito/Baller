-->> AimSet.lua
--> Get the aim data from the player and create aim stuf visible for everyone
--| By MrSaenz

coroutine.wrap(function()
	--repeat task.wait() for i,v in pairs(workspace.Balls:GetChildren()) do
			--v.AssemblyLinearVelocity = Vector3.zero;
			--v.AssemblyAngularVelocity = Vector3.zero;
		--end until workspace.Guide:FindFirstChild("stline")
	print("found")
end)()



local getaim:RemoteEvent=game:GetService("ReplicatedStorage"):WaitForChild("AimDataAdmin");
local getshot:RemoteEvent=game:GetService("ReplicatedStorage"):WaitForChild("ShotTrigger");


local cue = workspace:WaitForChild("Guide"):WaitForChild("Cue");
local cball:Part = workspace.Balls:WaitForChild("00Ball");



local radio = 5;
local d = "Distance"

local stline = Instance.new("Part");
stline.Position = Vector3.new(0,-1100,0)
stline.Shape = Enum.PartType.Cylinder;
stline.Material = Enum.Material.SmoothPlastic;
stline.Color = Color3.new(1,1,1);
stline.Transparency = 3/4;
stline.Position = cball.Position + Vector3.new(0,0,5);
stline.Size = Vector3.new(20,0.2,0.2)
stline.Anchored = true;
stline.CanCollide = false;
stline.Parent = game.ReplicatedStorage.Temporal;
stline.Name = "stline"


local ghost = Instance.new("Part")
ghost.Position = Vector3.new(0,-1100,0)
ghost.CanCollide = false;
ghost.Anchored = true;
ghost.Color = Color3.new(1,1,1);
ghost.Size = Vector3.new(1,1,1);
ghost.Material = "SmoothPlastic";
ghost.Shape = Enum.PartType.Ball;
ghost.Parent = game.ReplicatedStorage.Temporal
ghost.Transparency = 3/4
ghost.CollisionGroup = "Balls"



getaim.Event:Connect(function(radX,radZ)
	cball.AssemblyLinearVelocity = Vector3.zero;
	cball.AssemblyAngularVelocity = Vector3.zero
	ghost.Parent = workspace.Guide;
	stline.Parent = workspace.Guide;

	-- Aim the cue to the ball depending on the players cursor position;
	-- with a locked position of 5 studs away from the cueball

	local be = CFrame.new(Vector3.new(radX,cball.Position.Y,radZ),cball.Position);
	local _,y = be:ToOrientation();
	cue.Orientation = Vector3.new(0,math.deg(y) - 90,0);
	cue.Position = Vector3.new(
		cball.Position.X + radio * math.sin(math.rad(cue.Orientation.Y + 90)),
		cball.Position.Y,
		cball.Position.Z + radio * math.cos(math.rad(cue.Orientation.Y + 90))
	)

	cball.CFrame = CFrame.new(cball.Position,cue.Position);

	local raycast = RaycastParams.new();
	raycast.FilterDescendantsInstances = {workspace.Balls, workspace.Table};
	raycast.FilterType = Enum.RaycastFilterType.Include
	raycast.IgnoreWater = true;
	raycast.CollisionGroup = "Balls";
	
	local cp,ccf,len = cball.Position,cue.CFrame, -100
	local mod = {
		cball.Size.X/2 - 0.02,
		0,
		cball.Size.X/-2 + 0.02
	}
	
	local cfs = {ccf:ToWorldSpace(CFrame.new(len,0,mod[1])).Position,
				 ccf:ToWorldSpace(CFrame.new(len,0,mod[2])).Position,
				 ccf:ToWorldSpace(CFrame.new(len,0,mod[3])).Position}
	
	local rays = {}
	local org
	for i=1,3,2 do
		org = ccf:ToWorldSpace(CFrame.new(-5,0,mod[i])).Position
		rays[i] = workspace:Raycast(
			org,
			cfs[i] - org,
			raycast
		)
	end
	rays[2] = workspace:Raycast(
		cball.CFrame:ToWorldSpace(CFrame.new(0,0,0)).Position,
		cfs[2] - cball.CFrame:ToWorldSpace(CFrame.new(0,0,0)).Position,
		raycast
		
	)
	
	local FindFirstPos = function(...)
		local d1,d2,d3 = ...
		local mindist = math.min(d1[ d ], d2[ d ], d3[ d ]);

		return (d1[d] == mindist and d1) or (d2[d] == mindist and d2) or (d3[d] == mindist and d3) 
	end
	for i = 1,10 do 
		--[[
		ghost.CFrame = CFrame.new(rays[2].Position, cue.Position);
		ghost.CFrame = ghost.CFrame:ToWorldSpace(CFrame.new(mod[2],0,-cball.Size.X/2))


		stline.Size = Vector3.new((rays[2].Distance) - cball.Size.X / 2,stline.Size.Y,stline.Size.Z);
		stline.CFrame = CFrame.new(stline.Position,cball.CFrame:ToWorldSpace(CFrame.new(0,0,mod[2])).Position):ToWorldSpace(CFrame.Angles(0,math.rad(90),0))
		stline.Position = ghost.Position:Lerp(cp, 0.5) -- no cambiar
		]]
		

		local pos:RaycastResult = FindFirstPos(rays[1],rays[2],rays[3])
		print((pos==rays[1] and "ray1") or (pos==rays[2] and "ray2") or (pos==rays[3] and "ray3"))
		ghost.CFrame = CFrame.new(pos.Position, cue.Position)
		ghost.CFrame = ghost.CFrame:ToWorldSpace(CFrame.new(0,0,-cball.Size.X/2));
		ghost.CFrame = cball.CFrame:ToWorldSpace(CFrame.new(0,0,pos.Distance))
		
		stline.Size = Vector3.new((cp - ghost.Position).Magnitude, stline.Size.Y, stline.Size.Z)
		stline.CFrame = CFrame.new(stline.Position,cp):ToWorldSpace(CFrame.Angles(0,math.rad(90),0))
		stline.Position = ghost.Position:Lerp(cp,1/2)
		
	end
end)

local opened = true;
getshot.Event:Connect(function(factor, spin)
	if opened then
		opened = false;
		-- Obtener el factor de posicion de la bola fantasma con respecto a la posicion de la bola blanca
		-- para generar un vector compatible con la propiedad AssemblyLinearVelocity de la bola blanca,
		-- para luego multiplicarlo por un numero dependiendo de la fuerza
		-- deseada por el jugador y hacer que la blanca se mueva,
		-- no sin antes haber quitado las lineas de guia y la bola fantasma (opcional, deje para hacer pruebas)

		local acc = cball.CFrame.LookVector * Vector3.new(factor * -20,0, factor * -20)
		ghost.Parent = game.ReplicatedStorage.Temporal;
		stline.Parent = game.ReplicatedStorage.Temporal;
		cball:ApplyAngularImpulse(spin);
		cball.AssemblyLinearVelocity = acc;
		opened = true;
	end
end)


--[[
local s = false;
for i,v in pairs(workspace.Balls:GetChildren()) do
	if v:FindFirstChild("Trail") then
		v.Trail.Enabled = s;
	elseif v:FindFirstChild("Trail0") then
		v.Trail0.Enabled = s;
		v.Trail1.Enabled = s;
	end
end
]]
