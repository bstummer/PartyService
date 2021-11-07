This section introduces basic functions of the module.

<hr>

Firstly, get the module [here](https://www.roblox.com/library/6864341290) and insert it into your game (preferably ServerStorage).

PartyService only works on the server. Create a script and require it:
```lua
local PartyService = require(game.ServerStorage.PartyService)
```

<br>

After that, we'll listen to players joining the game. `PartyService.PlayerLoaded` fires when a player was loaded after entering the server.
```lua
PartyService.PlayerLoaded:Connect(function(player)
	
end)
```

<br>

If the player isn't in a party already, we will create one with them being the leader.
```lua
PartyService.PlayerLoaded:Connect(function(player)
	local party = PartyService:GetPartyFromPlayer(player)
	if not party then
		party = PartyService:CreateParty(player)
	end
end)
```

<br>

Now let's create a matchmaking queue. This is a classic example:
```lua
local queue = PartyService:GetQueue({
	Name = "Main",
	TeamAmount = 2,
    TeamSize = 4,
	MatchCallback = function(players, teams)
		local teleportOptions = Instance.new("TeleportOptions")
		teleportOptions.ShouldReserveServer = true
		teleportOptions:SetTeleportData({
			Teams = teams
		})
		
		local result = PartyService:TeleportAsync(6853732367, players, teleportOptions)
		print("Teleporting",players,"to reserved server with Id",result.PrivateServerId)
	end,
	GetPriority = function(player)
		return player:GetAttribute("Priority")
	end
})
```
Matches will have 2 teams consisting of 4 players each. When there's a match, the players will get teleported to a reserved server.

<br>

After pasting the code before the `PlayerLoaded` event, we can now add the player to the queue.
```lua
local queue = ...

PartyService.PlayerLoaded:Connect(function(player)
	queue:AddAsync(player)
end)
```

<br>

`PartyService.Messaging` is a module which handles all your MessagingService calls. It includes features like packet switching which allows you to send messages with unlimited size.
```lua
local messaging = PartyService.Messaging

messaging:SubscribeAsync("Test", function(data, sent)
	print(data, sent)
end)

messaging:Publish("Test", "Test message")

messaging:Publish("Test", string.rep("a", 10238)) --this is 10kB large

task.wait(1)

messaging:Unsubscribe("Test")
```

<br>

!!! info
	[Here](https://hypixel.fandom.com/wiki/Party_System) is an example of what you could create with PartyService.