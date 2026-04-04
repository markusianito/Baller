-->> RemotePortsBegin.luau
-- Initializes all remote events and functions in sword masters.
--> Scripted by Marcos

--[[ developer notes:
client-side: refers to the function that executes when the server fires the event to a client (OnClientEvent)
server-side: refers to the function that executes when a client fires the event to the server (OnServerEvent)

]]

local storage = game:GetService("ReplicatedStorage");
local bin = storage.Packages;
local net = require(bin.Net);


--[[
	cam (CameraUpdate)
	client-side: camera update
		params:
			props: {}
				A table with properties to update the camera with.
	server-side: n/a
]]
local cam = net:RemoteEvent("CameraUpdate")