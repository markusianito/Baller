-->> AimShotController.luau
--> Controls aim and shot actions for the pool system, client side
--|> Marcos


-- type definition for the AimShotController Knit controller
-- declares all public methods and their returns for typechecking
export type AimShotController = {
	__index: AimShotController,
	KnitStart:	(self: AimShotController) -> (),
	KnitInit:	(self: AimShotController) -> (),
	AssignGuideObjectsVisible:	(self: AimShotController, t: boolean) -> (),
	AssignGuideVisible:			(self: AimShotController, t: boolean) -> (),
	FindFirstLateralPos:		(self: AimShotController, v1:Vector3, v2:Vector3) -> Vector3,
	AimUpdateAsync:				(self: AimShotController, radX: number , radZ: number) -> promise,
	ExecuteShotAsync:			(self: AimShotController, v1: Vector3, v2: Vector3, v3: Vector3) -> promise,
}


--  SERVICES
----------------------------------------

local uisSvc  = game:GetService("UserInputService") -- handles mouse/keyboard input detection
local runSvc  = game:GetService("RunService")        -- used to bind perframe logic (RenderStep)
local shared  = game:GetService("ReplicatedStorage") -- shared storage where packages live


--  PACKAGES / LIBRARIES
----------------------------------------

local lib     = shared:WaitForChild("Packages")
local knit    = require(lib:WaitForChild("Knit"):WaitForChild("KnitClient")) -- Knit framework (client side)
local promise = require(lib:WaitForChild("Promise"))                          -- promise library for async control flow
local net     = require(lib:WaitForChild("Net"))                              -- networking utility for remote calls



--  PLAYER / INPUT
----------------------------------------

local mouse: Mouse = game.Players.LocalPlayer:GetMouse() -- local players mouse object, used for aim direction and input events



--  MATH SHORTCUTS
----------------------------------------
-- caching frequently used math functions as locals for better performance
-- since luau (or lua) global lookups are slower than local ones

local min = 0.001          -- minimum threshold value (used to avoid zero length vectors)
local v3  = Vector3        -- shorthand alias for the vector3 type
local rad = math.rad       -- this converts degrees to radians
local sin, cos = math.sin, math.cos -- trig functions used for circular positioning of the cue



local transparency2 = 3/4

local balls             = workspace:WaitForChild("Balls")
local ballname: string  = balls:GetAttribute("CueBall")
local cball: Part -- reference to the actual cue ball Part (resolved at runtime)


--  WORKSPACE REFERENCES - GUIDE PARTS
----------------------------------------
-- these are all visual guide elements that appear during aiming
-- they live under workspace.guides are manipulated each frame

local cue: Part       = workspace:WaitForChild("Guide"):WaitForChild("Cue")
local stline: Part    = workspace.Guide:WaitForChild("CBallTraceLine")
local ghost: Part     = workspace.Guide:WaitForChild("GhostBall")
local objline: Part   = workspace.Guide:WaitForChild("CurrentBallAngleLine")
local cbline: Part    = workspace.Guide:WaitForChild("CBallAngleLine")
local objarr: MeshPart = workspace.Guide:WaitForChild("Arrowtip")
local adornment0: Part = workspace.Guide:WaitForChild("sphadd0")
local adornment1: Part = workspace.Guide:WaitForChild("sphadd1")


-- the remotefunc used to ask the server whether this client is allowed to shoot
-- the server validates that the requesting player is the one currently assigned to take the shot
-- preventing unauthorized or cheated shot executions.
local reqshot: RemoteFunction = net:RemoteFunction("RequireShot")


-- raycastparams configured to only detect balls and the table surface
-- used by the spherecast that determines where the cue ball will travel and what it will hit
local RayProps = RaycastParams.new()
RayProps.FilterDescendantsInstances = {balls, workspace:WaitForChild("Table")}
RayProps.FilterType    = Enum.RaycastFilterType.Include
RayProps.IgnoreWater   = true
RayProps.CollisionGroup = "Balls"



local cballPosition, cballCframe = v3.zero, CFrame.new() -- cached cue ball position and cue cframe, updated each aim tick
local rayLength = -100 -- length of the aim ray in studs (negative = forward along the cues local X axis)
local ray                -- stores the result of the latest spherecast/raycast during aiming
local finalcross         -- the lateral Vector3 position used to determine the cue ball's post-impact deflection direction

-- Tracks how long the player held right-click (shift + rmb), used to calculate shot power.
-- set on Button2Down and consumed on Button2Up.
local Time

-- the cframe representing the direction in which the cue ball will be launched when the shot is executed.
-- derived from the cues orientation relative to the cue ball each aim update.
local shotCF = CFrame.new()



--  CONTROLLER CREATION
----------------------------------------

-- create the knit controller instance with its name.
-- additional state flags are attached directly to the controller table:
--   opened  - acts as a mutex, prevents overlapping shot executions
--   approve - flag set once the server confirms the shot is authorized
--   watcher - reserved for future use (like a signal or connection handle)
local aimShot = knit.CreateController({Name = "AimShotController"})
aimShot.opened  = true
aimShot.approve = false
aimShot.watcher = nil


--  HELPER: FindFirstLateralPos
----------------------------------------

-- when the cue ball hits an object ball, it deflects to one side
-- to visualize this deflection, two candidate positions are computed on the lateral
-- sides of the ghost ball (perpendicular to the shot direction)
-- this function returns whichever of the two candidate positions is closest
-- to the cue ball, that side is where the cue ball will actually deflect toward
-- Params:
--   v1, v2 - the two lateral candidate Vector3 world positions
-- Returns:
--   The Vector3 closest to the cue balls current position
@native function aimShot.FindFirstLateralPos(self: AimShotController, v1: Vector3, v2: Vector3): Vector3
	local dist1 = (cball.Position - v1).Magnitude
	local dist2 = (cball.Position - v2).Magnitude

	local min = math.min(dist1, dist2)

	-- returns whichever lateral position is nearer to the cue ball
	return (min == dist1 and v1) or (min == dist2 and v2)
end


--  HELPER: AssignGuideObjectsVisible
----------------------------------------

-- controls the transparency of the secondary guide parts:
-- the object ball direction line (objline), the cue ball deflection line (cbline),
-- and both sphere adornments (adornment0, adornment1)
-- passing true makes them semi-transparent (visible); false makes them fully transparent (hidden)
-- the boolean parameter is converted into a number via lua ternary operator
function aimShot.AssignGuideObjectsVisible(self: AimShotController, t: boolean)
	t = t and transparency2 or 1 -- true = 0.75 (semi-visible), false = 1.0 (fully invisible)
	cbline.Transparency     = t
	objline.Transparency    = t - 0.25
	adornment0.Transparency = t - 0.25
	adornment1.Transparency = t - 0.25
end


--  HELPER: AssignGuideVisible
----------------------------------------

-- same as previous func but different guide objects
function aimShot.AssignGuideVisible(self: AimShotController, t: boolean)
	t = t and transparency2 or 1 -- true = 0.75 (semivisible), false = 1.0 (fully invisible)
	ghost.Transparency  = t
	stline.Transparency = t
end


--  AimUpdateAsync
----------------------------------------

-- core aiming logic, called every time the player moves the mouse while holding the aim input
-- it takes the workspace X and Z coordinates of the mouse hit position and updates
-- all guide visuals (cue position/rotation, ghost ball, trace lines, deflection lines)
-- returns a promise that resolves once the update loop completes.
--
-- Params:
--   radX - world X position of the mouse cursor on the table surface
--   radZ - same but with Z
function aimShot.AimUpdateAsync(self: AimShotController, radX: number, radZ: number): promise
	return promise.new(function(resolve, reject, _)

		-- if the cue ball no longer exists (was potted?), attempt to retrieve
		-- the fallback ball assigned by the server via the CueBall attribute
		-- the length check (== 6) validates that the attribute holds a proper ball name
		if not balls:FindFirstChild(ballname) then
			local other = balls:GetAttribute("CueBall")
			if #other == 6 then
				cball    = balls[other]
				ballname = cball.Name
			end
		end

		-- freeze the cue ball in place while the player is aiming,
		-- preventing any residual physics from drifting it during the turn
		cball.AssemblyLinearVelocity  = v3.zero
		cball.AssemblyAngularVelocity = v3.zero

		-- reveal all guide visuals now that aiming is active
		self:AssignGuideObjectsVisible(true)
		self:AssignGuideVisible(true)

		-- build a cframe at the mouse position (at cue ball height) looking toward the cue ball
		-- extract only the Y rotation from it, this gives us the horizontal aim angle
		local lookCF = CFrame.lookAt(v3.new(radX, cball.Position.Y, radZ), cball.Position)
		local _, y   = lookCF:ToOrientation()

		-- apply the extracted Y rotation to the cue, subtracting 90° so the cue
		-- points toward the cue ball rather than perpendicular to it
		cue.Orientation = v3.new(0, math.deg(y) - 90, 0)

		-- reposition the cue 5 studs away from the cue ball along the current aim direction
		-- sin/cos of the adjusted orientation angle gives us the correct offset in world space
		cue.Position = v3.new(
			cball.Position.X + 5 * sin(rad(cue.Orientation.Y + 90)),
			cball.Position.Y,
			cball.Position.Z + 5 * cos(rad(cue.Orientation.Y + 90))
		)

		-- build shotCF: the cframe representing the exact direction the cue ball will travel
		-- it looks FROM the cue ball TOWARD the cue, so the lookvector points into the shot
		shotCF = CFrame.lookAt(cball.Position, cue.Position)

		-- cache the cue balls current position and the cues cframe for use in the raycast below
		cballPosition, cballCframe = cball.Position, cue.CFrame

		-- perform a spherecast along the shot direction to find the first object the cue ball would hit
		-- the sphere radius matches the cue balls radius for accurate collision prediction
		-- the ray travels 100 studs forward along the cues local negative X axis (into the shot)
		ray = workspace:Spherecast(
			cballPosition, cball.Size.X / 2,
			cballCframe:ToWorldSpace(CFrame.new(rayLength, 0, 0)).Position - cballPosition,
			RayProps
		)

		-- if the spherecast returns nil (can happen when the cue ball is very close
		-- to a target ball, leaving no room for the sphere to travel), retry with a regular raycast
		if not ray then
			ray = workspace:Raycast(
				cballPosition,
				cballCframe:ToWorldSpace(CFrame.new(rayLength, 0, 0)).Position - cballPosition,
				RayProps
			)
		end

		-- run the visual update 10 times per call to smooth out any jitter in guide part movement
		for _ = 1, 10 do

			-- place the ghost ball at the point where the cue ball would make contact
			-- shotCF:ToWorldSpace shifts along its Z axis by the rays hit distance
			ghost.CFrame = shotCF:ToWorldSpace(CFrame.new(0, 0, ray.Distance))

			-- resize and reposition the trace line so it always spans the space
			-- between the cue ball and the ghost ball, centered between them
			stline.Size     = v3.new((cballPosition - ghost.Position).Magnitude, stline.Size.Y, stline.Size.Z)
			stline.CFrame   = CFrame.lookAt(stline.Position, cballPosition):ToWorldSpace(CFrame.Angles(0, rad(90), 0))
			stline.Position = ghost.Position:Lerp(cballPosition, 1/2)

			-- check whether the ray hit an actual ball Part (as opposed to a cushion/wall)
			local obj: Part? = ray.Instance:IsA("Part") and ray.Instance or nil

			if obj then
				-- paint the object ball direction line to match the color of the ball that was hit
				objline.Color = obj.Color

				-- calculate the alignment between the cue balls path and the object balls center
				-- a more centered hit means the cue ball transfers more energy and deflects less
				-- a glancing hit means the cue ball retains more speed and deflects more
				-- This alignment value drives the length of both direction lines
				local normal    = shotCF:ToWorldSpace(CFrame.new(0, 0, (obj.Position - cball.Position).Magnitude - (cball.Size.X * 30)))
				local align     = CFrame.lookAt(normal.Position, obj.Position)
				local alignalt  = CFrame.lookAt(normal.Position, ghost.Position):Inverse()

				local actualAlign = align * alignalt

				-- clamp the computed alignment ratio to a [1, 5] range for sane line lengths
				local unit = math.clamp((1 / actualAlign.Position.Magnitude) * 2, 1, 5)

				-- resize the object ball line (longer = glancing hit, object deflects less)
				objline.Size = v3.new(unit, objline.Size.Y, objline.Size.Z)

				-- resize the cue ball deflection line (longer = more deflection after impact)
				cbline.Size = v3.new(
					(actualAlign.Position.Magnitude * 2) + 1,
					cbline.Size.Y, cbline.Size.Z
				)

				-- orient the object ball direction line so it points away from the ghost ball
				-- (the direction the object ball will roll after being struck).
				-- offset it forward by half its length so it starts at the object balls surface.
				objline.CFrame = CFrame.lookAt(obj.Position, ghost.Position)
					:ToWorldSpace(CFrame.new(0, 0, objline.Size.X / 2))
					:ToWorldSpace(CFrame.Angles(0, rad(90), 0))

				-- determine the cue balls post impact deflection direction using the cross product
				-- of the object lines right vector against the world Y axis
				-- this gives two candidate lateral positions; FindFirstLateralPos picks the correct one
				local factor     = -(objline.CFrame.RightVector)
				local leftcross  = factor:Cross(v3.yAxis)  + ghost.Position
				local rightcross = factor:Cross(-v3.yAxis) + ghost.Position

				finalcross = self:FindFirstLateralPos(leftcross, rightcross)

				-- orient and position the cue ball deflection line toward the chosen lateral position,
				-- centered along its own length
				local looktocross = CFrame.lookAt(ghost.Position, finalcross)
					:ToWorldSpace(CFrame.new(0, 0, cbline.Size.X / 2))
					:ToWorldSpace(CFrame.Angles(0, rad(90), 0))
				cbline.CFrame = looktocross

			else
				-- the ray hit a cushion/wall rather than a ball
				-- keep all guide parts visible but don't draw the object/deflection lines
				self:AssignGuideObjectsVisible(true)
				self:AssignGuideVisible(true)
			end
		end

		resolve()
	end)
end



--  ExecuteShotAsync
----------------------------------------

-- Executes the actual shot when the player releases shift + rmb.
-- Uses "factor" (time held, clamped to [0, 4] seconds) to scale the shot force,
-- and "spin" is reserved for future sidespin/english mechanics.
-- The "opened" flag acts as a simple mutex to prevent duplicate shots being fired
-- while one is still being processed.
--
-- Params:
--   factor - scalar derived from how long the player held the shot input. controls shot power
--   spin   - (reserved) intended for future spin/english application
function aimShot.ExecuteShotAsync(self: AimShotController, factor, spin): promise
	if self.opened then
		self.opened = false -- lock: prevent another shot from being fired until this one completes

		return promise.new(function(resolve, reject, _)

			-- ask the server if this player is authorized to shoot right now
			-- the server checks that the requesting client matches the player assigned for this turn,
			-- preventing any unauthorized shot execution.
			self.approve = reqshot:InvokeServer(cball.Name)
			repeat task.wait() until self.approve -- Yield until server authorization is confirmed

			local lookVector = shotCF.LookVector

			-- scale the shot force by factor (hold duration) along the XZ plane
			-- the negative multiplier reverses the look direction so the ball travels
			-- away from the cue (into the table) rather than toward it
			local direction = lookVector * v3.new(factor * -50, 0, factor * -50)

			-- hide all guide visuals immediately after the shot is fired
			self:AssignGuideObjectsVisible(true)
			self:AssignGuideVisible(true)

			-- apply the computed velocity to the cue ball to physically launch it
			-- spin offset would be added here in a future update
			cball.AssemblyLinearVelocity = direction

			-- release the lock and clear the approval flag, ready for the next shot
			self.opened  = true
			self.approve = nil

			resolve()
		end)
	end
end



--  KnitInit - input binding
----------------------------------------

-- called by Knit during initialization (before KnitStart)
-- sets up all input event connections and the per-frame RenderStep binding
function aimShot.KnitInit(self: AimShotController)

	-- Mouse.Move fires every time the cursor moves
	-- if the player is holding the primary mouse button (lmb) and the cue ball is stationary,
	-- trigger an aim update using the mouses current world position on the table
	mouse.Move:Connect(function()
		if uisSvc:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
			cball = balls:FindFirstChild(balls:GetAttribute("CueBall"))
			if cball then
				-- Only allow aiming while the cue ball is essentially at rest
				-- (angular velocity magnitude below the 0.03 threshold)
				if (cball.AssemblyAngularVelocity:Abs().Magnitude <= 0.03) then
					local radX = mouse.Hit.Position.X
					local radZ = mouse.Hit.Position.Z
					self:AimUpdateAsync(radX, radZ)
				end
			end
		end
	end)

	-- Record the timestamp when the player presses shift + rmb
	-- This marks the start of the shot power charge
	mouse.Button2Down:Connect(function()
		if uisSvc:IsKeyDown(Enum.KeyCode.LeftShift) then
			Time = tick()
		end
	end)

	-- When the player releases rmb (after a shift + rmb charge), calculate the elapsed time
	-- and pass it as the shot factor to ExecuteShotAsync, then clear the timer
	mouse.Button2Up:Connect(function()
		if Time then
			self:ExecuteShotAsync(math.clamp(tick() - Time, 0, 4))
			Time = nil
		end
	end)

	-- Bind a per frame update (priority 1) to keep the arrow tip and sphere adornments
	-- snapped to their respective guide parts every render frame
	-- This runs outside the aim update loop so the cosmetics stay smooth even between aim ticks
	runSvc:BindToRenderStep("AimLinesAdornmentsAdjust", 1, function()
		-- place the arrowhead at the far tip of the object ball direction line, rotated upright
		objarr.CFrame = objline.CFrame
			:ToWorldSpace(CFrame.new(objline.Size.X / -2 - 0.125, 0, 0))
			:ToWorldSpace(CFrame.Angles(0, 0, rad(90)))
		objarr.Color = objline.Color -- Keep the arrow color in sync with the object line

		-- Snap adornment0 to the ghost balls position (marks the contact point)
		adornment0.CFrame = ghost.CFrame

		-- Snap adornment1 to the far end of the cue ball deflection line (marks the deflection endpoint)
		adornment1.CFrame = cbline.CFrame:ToWorldSpace(CFrame.new(cbline.Size.X / 2, 0, 0))
	end)
end


--  KnitStartshift + rmb

-- Called by Knit after all controllers and services have initialized
-- Used here only for a startup confirmation log
function aimShot.KnitStart(self: AimShotController)
	print("AimShotController Started")
end

-- Bruh


return aimShot