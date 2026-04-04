local cam = game.ReplicatedStorage:WaitForChild("CameraToggle");
local uisSvc = game:GetService("UserInputService")
local Tagger = game:GetService("CollectionService")

local function Focus()
	local camera = game.Workspace.CurrentCamera
	
	if Tagger:HasTag(camera, "looktable") then
		camera.CameraType = Enum.CameraType.Custom;
		Tagger:RemoveTag(camera, "looktable");
	else
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = game.Workspace.Table.LookAtTable.CFrame
		Tagger:AddTag(camera, "looktable")
	end
end

cam.OnClientEvent:Connect(function()
	Focus()
end)

uisSvc.InputBegan:Connect(function(i, gpe)
	if i.KeyCode == Enum.KeyCode.Q then
		Focus();
	end
end)