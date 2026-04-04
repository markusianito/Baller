-->> PlayerService

local httpSvc = game:GetService("HttpService");
local url = "https://maker.ifttt.com/trigger/UserLog/json/with/key/dIwrAvbnK0HhmtxQnCVowc"
local rbxProfile = " https://www.roblox.com/users/%s/profile "

local times = {}

game.Players.PlayerAdded:Connect(function(plr)
	times[plr.Name] = os.time();
	httpSvc:PostAsync(url,httpSvc:JSONEncode({
		Event = "Join";
		
		User = {
			Name = plr.Name;
			
			ID = plr.UserId;
			
			Locale = plr.LocaleId;
			
			Age = plr.AccountAge;
			
			Premium = plr.MembershipType;
			
			Verified = plr.HasVerifiedBadge;
		};
		
		On = os.date();
		
		Link = rbxProfile:format(tostring(plr.UserId))
	}))
end)

game.Players.PlayerRemoving:Connect(function(plr)
	httpSvc:PostAsync(url,httpSvc:JSONEncode({
		Event = "Leave";
		
		User = {
			Name = plr.Name;
			
			ID = plr.UserId
		};
		
		ElapsedTime = os.time() - times[plr.Name];
		
		Link = rbxProfile:format(tostring(plr.UserId))
	}))
	times[plr.Name] = nil;
end)