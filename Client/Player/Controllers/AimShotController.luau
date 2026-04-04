-->> AimShotController.luau
--> Controls aim and shot actions for the pool system, client side
--|> Marcos


-- Type definition for the AimShotController Knit controller.
-- Declares all public methods and their signatures for type-checking purposes.
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


-- ████████████████████████████████████████
--  SERVICES
-- ████████████████████████████████████████

local uisSvc  = game:GetService("UserInputService") -- Handles mouse/keyboard input detection
local runSvc  = game:GetService("RunService")        -- Used to bind per-frame logic (RenderStep)
local shared  = game:GetService("ReplicatedStorage") -- Shared storage where packages live


-- ████████████████████████████████████████
--  PACKAGES / LIBRARIES
-- ████████████████████████████████████████

local lib     = shared:WaitForChild("Packages")
local knit    = require(lib:WaitForChild("Knit"):WaitForChild("KnitClient")) -- Knit framework (client-side)
local promise = require(lib:WaitForChild("Promise"))                          -- Promise library for async control flow
local net     = require(lib:WaitForChild("Net"))                              -- Networking utility for remote calls


-- ████████████████████████████████████████
--  PLAYER / INPUT
-- ████████████████████████████████████████

local mouse: Mouse = game.Players.LocalPlayer:GetMouse() -- Local player's mouse object, used for aim direction and input events


-- ████████████████████████████████████████
--  MATH SHORTCUTS
-- ████████████████████████████████████████
-- Caching frequently used math functions as locals for performance,
-- since Lua global lookups are slower than local ones.

local min = 0.001          -- Minimum threshold value (used to avoid zero-length vectors)
local v3  = Vector3        -- Shorthand alias for the Vector3 type
local rad = math.rad       -- Converts degrees to radians
local sin, cos = math.sin, math.cos -- Trig functions used for circular positioning of the cue


-- ████████████████████████████████████████
--  GUIDE VISUAL SETTINGS
-- ████████████████████████████████████████

local transparency2 = 3/4 -- Semi-transparent value used when guide parts are visible during aiming


-- ████████████████████████████████████████
--  WORKSPACE REFERENCES - BALLS
-- ████████████████████████████████████████

local balls             = workspace:WaitForChild("Balls")               -- Folder containing all ball parts in the scene
local ballname: string  = balls:GetAttribute("CueBall")                -- Attribute storing the name of the current cue ball
local cball: Part                                                        -- Reference to the actual cue ball Part (resolved at runtime)


-- ████████████████████████████████████████
--  WORKSPACE REFERENCES - GUIDE PARTS
-- ████████████████████████████████████████
-- These are all visual guide elements that appear during aiming.
-- They live under workspace.Guide and are manipulated each frame.

local cue: Part       = workspace:WaitForChild("Guide"):WaitForChild("Cue")              -- The pool cue stick visual
local stline: Part    = workspace.Guide:WaitForChild("CBallTraceLine")                   -- Line drawn between the cue ball and the ghost ball
local ghost: Part     = workspace.Guide:WaitForChild("GhostBall")                        -- Ghost ball showing where the cue ball will make contact
local objline: Part   = workspace.Guide:WaitForChild("CurrentBallAngleLine")             -- Line showing the direction the object ball will travel after impact
local cbline: Part    = workspace.Guide:WaitForChild("CBallAngleLine")                   -- Line showing the cue ball's deflection direction after impact
local objarr: MeshPart = workspace.Guide:WaitForChild("Arrowtip")                        -- Arrowhead mesh attached to the object ball direction line
local adornment0: Part = workspace.Guide:WaitForChild("sphadd0")                         -- Sphere adornment placed at the ghost ball position
local adornment1: Part = workspace.Guide:WaitForChild("sphadd1")                         -- Sphere adornment placed at the end of the cue ball deflection line


-- ████████████████████████████████████████
--  NETWORKING
-- ████████████████████████████████████████

-- RemoteFunction used to ask the server whether this client is allowed to shoot.
-- The server validates that the requesting player is the one currently assigned to take the shot,
-- preventing unauthorized or cheated shot executions.
local reqshot: RemoteFunction = net:RemoteFunction("RequireShot")


-- ████████████████████████████████████████
--  RAYCAST CONFIGURATION
-- ████████████████████████████████████████

-- RaycastParams configured to only detect balls and the table surface.
-- Used by the spherecast that determines where the cue ball will travel and what it will hit.
local RayProps = RaycastParams.new()
RayProps.FilterDescendantsInstances = {balls, workspace:WaitForChild("Table")}
RayProps.FilterType    = Enum.RaycastFilterType.Include
RayProps.IgnoreWater   = true
RayProps.CollisionGroup = "Balls"


-- ████████████████████████████████████████
--  AIM STATE - RUNTIME VARIABLES
-- ████████████████████████████████████████

local cballPosition, cballCframe = v3.zero, CFrame.new() -- Cached cue ball position and cue CFrame, updated each aim tick
local rayLength = -100   -- Length of the aim ray in studs (negative = forward along the cue's local X axis)
local ray                -- Stores the result of the latest spherecast/raycast during aiming
local finalcross         -- The lateral Vector3 position used to determine the cue ball's post-impact deflection direction

-- Tracks how long the player held right-click (Shift + RMB), used to calculate shot power.
-- Set on Button2Down and consumed on Button2Up.
local Time

-- The CFrame representing the direction in which the cue ball will be launched when the shot is executed.
-- Derived from the cue's orientation relative to the cue ball each aim update.
local shotCF = CFrame.new()


-- ████████████████████████████████████████
--  CONTROLLER CREATION
-- ████████████████████████████████████████

-- Create the Knit controller instance with its name.
-- Additional state flags are attached directly to the controller table:
--   opened  - acts as a mutex; prevents overlapping shot executions
--   approve - flag set once the server confirms the shot is authorized
--   watcher - reserved for future use (e.g., a signal or connection handle)
local aimShot = knit.CreateController({Name = "AimShotController"})
aimShot.opened  = true
aimShot.approve = false
aimShot.watcher = nil


-- ████████████████████████████████████████
--  HELPER: FindFirstLateralPos
-- ████████████████████████████████████████

-- When the cue ball hits an object ball, it deflects to one side.
-- To visualize this deflection, two candidate positions are computed on the lateral
-- sides of the ghost ball (perpendicular to the shot direction).
-- This function returns whichever of the two candidate positions is closest
-- to the cue ball, that side is where the cue ball will actually deflect toward.
-- Parameters:
--   v1, v2 - the two lateral candidate Vector3 world positions
-- Returns:
--   The Vector3 closest to the cue ball's current position
@native function aimShot.FindFirstLateralPos(self: AimShotController, v1: Vector3, v2: Vector3): Vector3
	local dist1 = (cball.Position - v1).Magnitude
	local dist2 = (cball.Position - v2).Magnitude

	local min = math.min(dist1, dist2)

	-- Return whichever lateral position is nearer to the cue ball
	return (min == dist1 and v1) or (min == dist2 and v2)
end


-- ████████████████████████████████████████
--  HELPER: AssignGuideObjectsVisible
-- ████████████████████████████████████████

-- Controls the transparency of the secondary guide parts:
-- the object ball direction line (objline), the cue ball deflection line (cbline),
-- and both sphere adornments (adornment0, adornment1).
-- Passing true makes them semi-transparent (visible); false makes them fully transparent (hidden)
-- Note: the boolean parameter is coerced into a number via Lua's ternary operator.
function aimShot.AssignGuideObjectsVisible(self: AimShotController, t: boolean)
	t = t and transparency2 or 1 -- true = 0.75 (semi-visible), false = 1.0 (fully invisible)
	cbline.Transparency     = t
	objline.Transparency    = t - 0.25
	adornment0.Transparency = t - 0.25
	adornment1.Transparency = t - 0.25
end


-- ████████████████████████████████████████
--  HELPER: AssignGuideVisible
-- ████████████████████████████████████████

-- Controls the transparency of the primary aim guide parts:
-- the ghost ball and the cue ball trace line (stline).
-- Same boolean to number coercion as AssignGuideObjectsVisible.
function aimShot.AssignGuideVisible(self: AimShotController, t: boolean)
	t = t and transparency2 or 1 -- true = 0.75 (semi-visible), false = 1.0 (fully invisible)
	ghost.Transparency  = t
	stline.Transparency = t
end


-- ████████████████████████████████████████
--  AimUpdateAsync
-- ████████████████████████████████████████

-- Core aiming logic, called every time the player moves the mouse while holding the aim input.
-- Takes the worldspace X and Z coordinates of the mouse hit position and updates
-- all guide visuals (cue position/rotation, ghost ball, trace lines, deflection lines).
-- Returns a Promise that resolves once the update loop completes.
--
-- Parameters:
--   radX - world X position of the mouse cursor on the table surface
--   radZ - same but with Z
function aimShot.AimUpdateAsync(self: AimShotController, radX: number, radZ: number): promise
	return promise.new(function(resolve, reject, _)

		-- If the cue ball no longer exists (e.g. was potted), attempt to retrieve
		-- the fallback ball assigned by the server via the CueBall attribute.
		-- The length check (== 6) validates that the attribute holds a proper ball name.
		if not balls:FindFirstChild(ballname) then
			local other = balls:GetAttribute("CueBall")
			if #other == 6 then
				cball    = balls[other]
				ballname = cball.Name
			end
		end

		-- Freeze the cue ball in place while the player is aiming,
		-- preventing any residual physics from drifting it during the turn.
		cball.AssemblyLinearVelocity  = v3.zero
		cball.AssemblyAngularVelocity = v3.zero

		-- Reveal all guide visuals now that aiming is active.
		self:AssignGuideObjectsVisible(true)
		self:AssignGuideVisible(true)

		-- Build a CFrame at the mouse position (at cue ball height) looking toward the cue ball.
		-- Extract only the Y rotation from it, this gives us the horizontal aim angle.
		local lookCF = CFrame.lookAt(v3.new(radX, cball.Position.Y, radZ), cball.Position)
		local _, y   = lookCF:ToOrientation()

		-- Apply the extracted Y rotation to the cue, subtracting 90° so the cue
		-- points toward the cue ball rather than perpendicular to it.
		cue.Orientation = v3.new(0, math.deg(y) - 90, 0)

		-- Reposition the cue 5 studs away from the cue ball along the current aim direction.
		-- sin/cos of the adjusted orientation angle gives us the correct offset in world space.
		cue.Position = v3.new(
			cball.Position.X + 5 * sin(rad(cue.Orientation.Y + 90)),
			cball.Position.Y,
			cball.Position.Z + 5 * cos(rad(cue.Orientation.Y + 90))
		)

		-- Build shotCF: the CFrame representing the exact direction the cue ball will travel.
		-- It looks FROM the cue ball TOWARD the cue, so the lookvector points into the shot.
		shotCF = CFrame.lookAt(cball.Position, cue.Position)

		-- Cache the cue ball's current position and the cue's CFrame for use in the raycast below.
		cballPosition, cballCframe = cball.Position, cue.CFrame

		-- Perform a spherecast along the shot direction to find the first object the cue ball would hit.
		-- The sphere radius matches the cue ball's radius for accurate collision prediction.
		-- The ray travels 100 studs forward along the cue's local negative X axis (into the shot).
		ray = workspace:Spherecast(
			cballPosition, cball.Size.X / 2,
			cballCframe:ToWorldSpace(CFrame.new(rayLength, 0, 0)).Position - cballPosition,
			RayProps
		)

		-- if the spherecast returns nil (can happen when the cue ball is very close
		-- to a target ball, leaving no room for the sphere to travel), retry with a regular Raycast.
		if not ray then
			ray = workspace:Raycast(
				cballPosition,
				cballCframe:ToWorldSpace(CFrame.new(rayLength, 0, 0)).Position - cballPosition,
				RayProps
			)
		end

		-- Run the visual update 10 times per call to smooth out any jitter in guide part movement.
		for _ = 1, 10 do

			-- Place the ghost ball at the point where the cue ball would make contact.
			-- shotCF:ToWorldSpace shifts along its Z axis by the ray's hit distance.
			ghost.CFrame = shotCF:ToWorldSpace(CFrame.new(0, 0, ray.Distance))

			-- Resize and reposition the trace line so it always spans the space
			-- between the cue ball and the ghost ball, centered between them.
			stline.Size     = v3.new((cballPosition - ghost.Position).Magnitude, stline.Size.Y, stline.Size.Z)
			stline.CFrame   = CFrame.lookAt(stline.Position, cballPosition):ToWorldSpace(CFrame.Angles(0, rad(90), 0))
			stline.Position = ghost.Position:Lerp(cballPosition, 1/2)

			-- Check whether the ray hit an actual ball Part (as opposed to a cushion/wall).
			local obj: Part? = ray.Instance:IsA("Part") and ray.Instance or nil

			if obj then
				-- Tint the object ball direction line to match the color of the ball that was hit.
				objline.Color = obj.Color

				-- Calculate the alignment between the cue ball's path and the object ball's center.
				-- A more centered hit means the cue ball transfers more energy and deflects less;
				-- a glancing hit means the cue ball retains more speed and deflects more.
				-- This alignment value drives the length of both direction lines.
				local normal    = shotCF:ToWorldSpace(CFrame.new(0, 0, (obj.Position - cball.Position).Magnitude - (cball.Size.X * 30)))
				local align     = CFrame.lookAt(normal.Position, obj.Position)
				local alignalt  = CFrame.lookAt(normal.Position, ghost.Position):Inverse()

				local actualAlign = align * alignalt

				-- Clamp the computed alignment ratio to a [1, 5] range for sane line lengths.
				local unit = math.clamp((1 / actualAlign.Position.Magnitude) * 2, 1, 5)

				-- Resize the object ball line (longer = glancing hit, object deflects less).
				objline.Size = v3.new(unit, objline.Size.Y, objline.Size.Z)

				-- Resize the cue ball deflection line (longer = more deflection after impact).
				cbline.Size = v3.new(
					(actualAlign.Position.Magnitude * 2) + 1,
					cbline.Size.Y, cbline.Size.Z
				)

				-- Orient the object ball direction line so it points away from the ghost ball
				-- (the direction the object ball will roll after being struck).
				-- Offset it forward by half its length so it starts at the object ball's surface.
				objline.CFrame = CFrame.lookAt(obj.Position, ghost.Position)
					:ToWorldSpace(CFrame.new(0, 0, objline.Size.X / 2))
					:ToWorldSpace(CFrame.Angles(0, rad(90), 0))

				-- Determine the cue ball's post impact deflection direction using the cross product
				-- of the object line's right vector against the world Y axis.
				-- This gives two candidate lateral positions; FindFirstLateralPos picks the correct one.
				local factor     = -(objline.CFrame.RightVector)
				local leftcross  = factor:Cross(v3.yAxis)  + ghost.Position
				local rightcross = factor:Cross(-v3.yAxis) + ghost.Position

				finalcross = self:FindFirstLateralPos(leftcross, rightcross)

				-- Orient and position the cue ball deflection line toward the chosen lateral position,
				-- centered along its own length.
				local looktocross = CFrame.lookAt(ghost.Position, finalcross)
					:ToWorldSpace(CFrame.new(0, 0, cbline.Size.X / 2))
					:ToWorldSpace(CFrame.Angles(0, rad(90), 0))
				cbline.CFrame = looktocross

			else
				-- The ray hit a cushion/wall rather than a ball.
				-- Keep all guide parts visible but don't draw the object/deflection lines.
				self:AssignGuideObjectsVisible(true)
				self:AssignGuideVisible(true)
			end
		end

		resolve()
	end)
end


-- ████████████████████████████████████████
--  ExecuteShotAsync
-- ████████████████████████████████████████

-- Executes the actual shot when the player releases Shift + RMB.
-- Uses "factor" (time held, clamped to [0, 4] seconds) to scale the shot force,
-- and "spin" is reserved for future side-spin/english mechanics.
-- The "opened" flag acts as a simple mutex to prevent duplicate shots being fired
-- while one is still being processed.
--
-- Parameters:
--   factor - scalar derived from how long the player held the shot input; controls shot power
--   spin   - (reserved) intended for future spin/english application
function aimShot.ExecuteShotAsync(self: AimShotController, factor, spin): promise
	if self.opened then
		self.opened = false -- Lock: prevent another shot from being fired until this one completes

		return promise.new(function(resolve, reject, _)

			-- Ask the server if this player is authorized to shoot right now.
			-- The server checks that the requesting client matches the player assigned for this turn,
			-- preventing any unauthorized shot execution.
			self.approve = reqshot:InvokeServer(cball.Name)
			repeat task.wait() until self.approve -- Yield until server authorization is confirmed

			local lookVector = shotCF.LookVector

			-- Scale the shot force by factor (hold duration) along the XZ plane.
			-- The negative multiplier reverses the look direction so the ball travels
			-- away from the cue (i.e., into the table) rather than toward it.
			local direction = lookVector * v3.new(factor * -50, 0, factor * -50)

			-- Hide all guide visuals immediately after the shot is fired.
			self:AssignGuideObjectsVisible(true)
			self:AssignGuideVisible(true)

			-- Apply the computed velocity to the cue ball to physically launch it.
			-- Spin offset would be added here in a future update.
			cball.AssemblyLinearVelocity = direction

			-- Release the lock and clear the approval flag, ready for the next shot.
			self.opened  = true
			self.approve = nil

			resolve()
		end)
	end
end


-- ████████████████████████████████████████
--  KnitInit - Input Binding
-- ████████████████████████████████████████

-- Called by Knit during initialization (before KnitStart).
-- Sets up all input event connections and the per-frame RenderStep binding.
function aimShot.KnitInit(self: AimShotController)

	-- Mouse.Move fires every time the cursor moves.
	-- If the player is holding the primary mouse button (LMB) and the cue ball is stationary,
	-- trigger an aim update using the mouse's current world position on the table.
	mouse.Move:Connect(function()
		if uisSvc:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
			cball = balls:FindFirstChild(balls:GetAttribute("CueBall"))
			if cball then
				-- Only allow aiming while the cue ball is essentially at rest
				-- (angular velocity magnitude below the 0.03 threshold).
				if (cball.AssemblyAngularVelocity:Abs().Magnitude <= 0.03) then
					local radX = mouse.Hit.Position.X
					local radZ = mouse.Hit.Position.Z
					self:AimUpdateAsync(radX, radZ)
				end
			end
		end
	end)

	-- Record the timestamp when the player presses Shift + RMB.
	-- This marks the start of the shot power charge.
	mouse.Button2Down:Connect(function()
		if uisSvc:IsKeyDown(Enum.KeyCode.LeftShift) then
			Time = tick()
		end
	end)

	-- When the player releases RMB (after a Shift + RMB charge), calculate the elapsed time
	-- and pass it as the shot factor to ExecuteShotAsync, then clear the timer.
	mouse.Button2Up:Connect(function()
		if Time then
			self:ExecuteShotAsync(math.clamp(tick() - Time, 0, 4))
			Time = nil
		end
	end)

	-- Bind a per frame update (priority 1) to keep the arrow tip and sphere adornments
	-- snapped to their respective guide parts every render frame.
	-- This runs outside the aim update loop so the cosmetics stay smooth even between aim ticks.
	runSvc:BindToRenderStep("AimLinesAdornmentsAdjust", 1, function()
		-- Place the arrowhead at the far tip of the object ball direction line, rotated upright.
		objarr.CFrame = objline.CFrame
			:ToWorldSpace(CFrame.new(objline.Size.X / -2 - 0.125, 0, 0))
			:ToWorldSpace(CFrame.Angles(0, 0, rad(90)))
		objarr.Color = objline.Color -- Keep the arrow color in sync with the object line

		-- Snap adornment0 to the ghost ball's position (marks the contact point).
		adornment0.CFrame = ghost.CFrame

		-- Snap adornment1 to the far end of the cue ball deflection line (marks the deflection endpoint).
		adornment1.CFrame = cbline.CFrame:ToWorldSpace(CFrame.new(cbline.Size.X / 2, 0, 0))
	end)
end


-- ████████████████████████████████████████
--  KnitStart
-- ████████████████████████████████████████

-- Called by Knit after all controllers and services have initialized.
-- Used here only for a startup confirmation log.
function aimShot.KnitStart(self: AimShotController)
	print("AimShotController Started")
end


return aimShot