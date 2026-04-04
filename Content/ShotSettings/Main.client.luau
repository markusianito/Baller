-->> Main.lua
--> By MrSaenz
-- Main script for shot UI

local uisSvc = game:GetService("UserInputService");
local runSvc = game:GetService("RunService");
local ms = game.Players.LocalPlayer:GetMouse();

local frame = script.Parent
local spin:ImageLabel = frame:WaitForChild("Ball"):WaitForChild("Ball");
local spinc:ImageButton = spin:WaitForChild("Picker");
local spinset:Part = frame:WaitForChild("Spin")
local ActionOnFire;


local ap, as = "AbsolutePosition", "AbsoluteSize"


local CursorFucksBall = function(x,y)
	local vector = Vector2.new(
		(x - spin[ap].X) / spin[as].X,
		(y - spin[ap].y) / spin[as].Y
	);

	return not (math.abs((vector - (Vector2.one / 2)).Magnitude) > 1/2);
end

local CursorHitsBall = function(x,y)
	local vector = Vector2.new(
		(x - spin[ap].X) / spin[as].X,
		(y - spin[ap].y) / spin[as].Y
	);

	vector = (
		(math.abs((vector - Vector2.new(0.5,0.5)).Magnitude) > 0.5) and 
			(vector - Vector2.new(0.5,0.5)).Unit / 2 + Vector2.new(0.5,0.5) or 
			vector
	)

	spinc.Position = UDim2.new(
		vector.X,
		0,
		vector.Y,
		0
	)

	spinset.Value = Vector3.new(
		math.cos(spinc.Position.Y.Scale * math.pi), -- uiy
		-math.cos(spinc.Position.X.Scale * math.pi),
		0 -- uix
	)
	print(spinset.Value.X,spinset.Value.Y)
end


local CursorMeetsFrame = function()
	if CursorFucksBall(ms.X,ms.Y) then
		script.Parent.MainAimExecute.Enabled = false;
		CursorHitsBall(ms.X,ms.Y)
		ActionOnFire = runSvc.RenderStepped:Connect(function()
			CursorHitsBall(ms.X,ms.Y)
		end)
	end
end

local CursorLeavesFrame = function()
	if ActionOnFire then
		script.Parent.MainAimExecute.Enabled = true;
		ActionOnFire:Disconnect()
		ActionOnFire = nil;
	end
end




local pressing = false;
uisSvc.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		if frame.Enabled then
			pressing = true;
			CursorMeetsFrame()
		end
	end
end)

uisSvc.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		if frame.Enabled then
			CursorLeavesFrame()
			pressing = false;
		end
	end
end)