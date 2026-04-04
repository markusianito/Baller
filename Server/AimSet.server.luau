-->> AimSet.lua
--> Get the aim data from the player and create aim stuf visible for everyone
--| By MrSaenz

coroutine.wrap(function()
	repeat task.wait() for i,v in pairs(workspace.Balls:GetChildren()) do
			v.AssemblyLinearVelocity = Vector3.zero;
			v.AssemblyAngularVelocity = Vector3.zero;
		end until workspace.Guide:FindFirstChild("stline")
	print("found")
end)()



local getaim:RemoteEvent=game:GetService("ReplicatedStorage"):WaitForChild("AimDataAdmin");
local getshot:RemoteEvent=game:GetService("ReplicatedStorage"):WaitForChild("ShotTrigger");


local cue = workspace:WaitForChild("Guide"):WaitForChild("Cue");
local cball:Part = workspace.Balls:WaitForChild("00Ball");



local radio = 5;


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
	ghost.CollisionGroup = "Balls;"



getaim.OnServerEvent:Connect(function(plr, radX,radZ)
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
	
	
	
	-- Generar la línea de guia, que a su vez genera una bola fantasma
	-- cuando la stlinea se encuentra con la banda, o con otra bola.
	-- en caso de encontrarse con otra bola se genera el angulo correspondiente a la alineacion de las bolas
	-- y su respectiva linea de dirección en ambas.
	
	
	cball.CFrame = CFrame.new(cball.Position,cue.Position);
	
	local x,y,z = CFrame.new(stline.Position, cball.Position):ToOrientation();
	stline.Orientation = Vector3.new(math.deg(x) - 90, math.deg(y), math.deg(z) - 90)


	local raycast = RaycastParams.new();
	local cf = cue.CFrame:ToWorldSpace(CFrame.new(-100,0,0))
	local Start,End = cball.Position, Vector3.new(cf.Position.X, cf.Position.Y, cf.Position.Z);
		raycast.FilterDescendantsInstances = {workspace.Balls, workspace.Table};
		raycast.FilterType = Enum.RaycastFilterType.Include;
		raycast.IgnoreWater = true;
		raycast.CollisionGroup = "Balls";
	local ray = workspace:Raycast(
		Start,
		End - Start,
		raycast
	)
	
	for i = 1,10 do
		ghost.CFrame = CFrame.new(ray.Position, cue.Position);
		ghost.CFrame = ghost.CFrame:ToWorldSpace(CFrame.new(0,0,-cball.Size.X/2))

		local x,y,z = CFrame.new(stline.Position,cball.Position):ToOrientation()
		stline.Size = Vector3.new(ray.Distance - cball.Size.X / 2,stline.Size.Y,stline.Size.Z);
		stline.CFrame = CFrame.new(stline.Position,cball.Position):ToWorldSpace(CFrame.Angles(0,math.rad(90),0))
		stline.Position = ghost.Position:Lerp(cball.Position, 0.5)
	end
end)

local opened = true;
getshot.OnServerEvent:Connect(function(plr, factor, spin)
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
		cball:ApplyImpulse(acc)
		opened = true;
	end
end)