# PartyService

PartyService is a stand-alone module for Roblox that handles matchmaking and various other related systems. This module does not impose specific interfaces or annoying features, allowing you to write your own interface while relying on its clear and smart API. It is specifically built for large games with many players and is optimized to keep MemoryStoreService requests to a minimum.

Current Version: **0.3.0-beta**

<br>

## Features

- Feature-rich party system: Manage players, ranks, and parties seamlessly.
- Global matchmaking queues: Includes support for player priorities.
- MessagingService wrapper: Handles all your `MessagingService` calls, including a packet switching feature that allows you to send messages of unlimited size.
- Teleportation handling: Manages all your teleportation needs and ensures that parties persist after teleports.
- Automatic retries: Network calls are automatically retried, eliminating the need for `pcall` unless you require additional error handling.

### Upcoming Features
- Matching based on skill.
- Tracking of available requests to deal more thriftily with requests when close to the limit.
- Self-adapting polling cooldown.
- Tools to easily create global lobbies, rooms, and server lists.

<br>

## Installation

1. Get the module from the Roblox library [here](https://www.roblox.com/library/6864341290).
2. Insert the module into your game. It is recommended to place it in `ServerStorage`.
3. Require the module in a server script, as PartyService only works on the server:

```lua
local PartyService = require(game.ServerStorage.PartyService)
```

<br>

## Quick Start

### Listening to Player Loads
`PartyService.PlayerLoaded` fires when a player is loaded after entering the server. This event is guaranteed to fire, making it a safe alternative to `PlayerAdded` to prevent errors during party-related actions.

```lua
PartyService.PlayerLoaded:Connect(function(player)
	-- Player has loaded
end)
```

### Creating a Party
You can check if a player is in a party and create one for them, assigning them as the leader:

```lua
PartyService.PlayerLoaded:Connect(function(player)
	local party = PartyService:GetPartyFromPlayer(player)
	if not party then
		party = PartyService:CreateParty(player)
	end
end)
```


### Creating a Matchmaking Queue
Here is a classic example of setting up a queue that matches 2 teams of 4 players each, and then teleports them to a reserved server:

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

-- Adding a player to the queue:
PartyService.PlayerLoaded:Connect(function(player)
	queue:AddAsync(player)
end)
```

<br>

## Important Information & Limitations
- Server Scope: All party members exist in the same server; parties do not span across multiple servers.
- Party Leadership: Parties always have a leader. If the current leader is removed, a random player in the party will be assigned as the new leader.
- Beta Status: This module is still in beta and may contain bugs. Furthermore, matchmaking is not 100% complete and will receive heavy improvements in the future.
- Queue Optimization: Functions like AddAsync and RemoveAsync are built to accept multiple players. Whenever possible, use multiple players at once to save on requests.
- MemoryStore Limits: A player in the queue takes up 10 + Length of UserId bytes, while a group takes 11 + Length of the UserIds + Amount of players.

<br>

## API Documentation
For the full documentation and API reference, visit: https://bstummer.github.io/PartyService/
