**General notices:**

- Functions with `Async` in their name will yield.
- The lowercase `player` type is equal to `Player | int64`. This means it can be a player instance or its UserId.
- `{Value}` stands for `{[number]:Value}`, so an array that contains one or multiple of `Value`.
- Parameters marked with `?` are optional.

## PartyService
### Properties
#### Parties
```lua
{[PartyId]:Party} Parties
```
A container of all the parties existing in the server.
----
#### Queues
```lua
{[Name]:Queue} Queues
```
A container of all the queues created on the server.
----
#### Settings
Settings that determine how PartyService operates.
##### DefaultRank
```lua
string DefaultRank
```
The default rank of parties that players get added to when not specifying a rank.
##### RanksAddedByDefault
```lua
{string} RanksAddedByDefault
```
Ranks that will be added by default when creating parties.
##### TeleportDataValidTime
```lua
number TeleportDataValidTime
```
Determines how long the TeleportData is valid.
##### PlayerLostTime
```lua
number PlayerLostTime
```
After this time, players will be considered lost in the teleport process and removed from the party. This time starts when the first player of a party arrives in the game.
##### PollingCooldown
```lua
number PollingCooldown
```
How often PartyService will make a request to the queues in order to check if there are matches. If this is `nil`, it will be automatically updated in the future according to MemoryStoreService limits.
##### SplitUpGroups
```lua
boolean SplitUpGroups
```
Groups in the queue will always stay in the same match. However they could be split up into different teams if they don't fit.
##### QueueExpiration
```lua
int64 QueueExpiration
```
When there haven't been any changes to the queue after this time, it will be cleared.

----
#### Messaging
A module which handles all your MessagingService calls. It includes features like packet switching which allows you to send messages with unlimited size. This module is supposed to become even smarter in the future.
##### SubscribeAsync
```rust
void SubscribeAsync(string topic, function callback(any message, number sent) -> ())
```
Begin listening to the given topic. The callback is invoked with received messages and the time when the message was sent.
##### Unsubscribe
```lua
void Unsubscribe(string topic)
```
Stop listening to the given topic.
##### Publish
```lua
void Publish(string topic, any message)
```
Sends the provided message to all subscribers to the topic.
----
### Events
#### PlayerLoaded
```lua
RBXScriptSignal PlayerLoaded(Player player, any teleportData)
```
Fires when a player was loaded after entering the server. This event is guaranteed to fire, so you can use it instead of `PlayerAdded` in order to prevent errors when doing party-related actions with the player.
----
#### PartyAdded
```lua
RBXScriptSignal PartyAdded(Party party)
```
Fires when a party was created.
----
#### PartyRemoving
```lua
RBXScriptSignal PartyRemoving(Party party)
```
Fires right before a party gets destroyed.
----
### Methods
#### CreateParty
```lua
Party CreateParty(player leader, {player} | {[Rank]:{player}} members?)
```
Creates a new party object.
----
#### IsInParty
```lua
boolean, Party? IsInParty(player player, Party party?)
```
Checks if the given player is in a party, if the 2nd argument is provided it only checks that party.
----
#### GetPartyFromPlayer
```lua
Party, Rank GetPartyFromPlayer(player player)
```
Returns the party and rank of the given player.
----
#### GetQueue
```lua
Queue GetQueue(config)
```
Creates a new queue object or returns an existing one with the provided name.
`config` contains the following:
```rust
{
	string Name,
    int TeamAmount?,
	int TeamSize,
	function MatchCallback({Player} players, any teams) -> (),
	function GetPriority(Player player) -> (number?)?
}
```
The `MatchCallback` function gets invoked with an array of the players that are in this server and a table with the team composition. It could look like this:
```lua
{
	{2376312, 1238712, 2318918, 9852347}, <- team of four players
	{1293812, 21748923, 1263712, 9812371}
}
```

Classic example:
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

----
#### IsInQueueAsync
```lua
boolean, string? IsInQueueAsync(player player, string queueName?)
```
Checks if the given player is in a queue, if the 2nd argument is provided it checks only that queue.
----
#### TeleportAsync
```lua
TeleportAsyncResult TeleportAsync(int64 placeId, Player | Party | {Player | Party} players, TeleportOptions teleportOptions?)
```
This is a wrapper around `TeleportService:TeleportAsync` which manages TeleportData. It ensures that parties persist after teleports.

<br>

## Party
### Properties
#### ClassName
```lua
string ClassName
```
A string representing what class this object belongs to.
----
#### Created
```lua
int Created
```
Unix time in seconds at which the party was created.
----
#### Leader
```lua
int64 Leader
```
A property representing the party leader's UserId.
----
#### Members
```lua
{int64} Members
```
An array of the party members. If added in `PartyService.Settings.RanksAddedByDefault`, more ranks like this will exist in the party.
----
#### PartyId
```lua
int PartyId
```
This is a randomly generated 8 digit Id. It is not guaranteed that it is unique, however the chance is 0.0000000111% to get a duplicate.
----
### Methods
#### AddPlayer
```lua
void AddPlayer(player player, string rank?)
```
Adds a player to the party, if given to the specified rank.
----
#### RemovePlayer
```lua
void RemovePlayer(player player)
```
Removes the player from the party.
----
#### AddRank
```lua
void AddRank(string rankName, {player} players?)
```
You can add a rank yourself by doing `Party.Rank = {}`. This function should rather be used when you want to add players to it at the same time.
----
#### RemoveRank
```lua
void RemoveRank(string rankName)
```
Removes a rank. Members of the rank will be added to `PartyService.Settings.DefaultRank`.
----
#### ChangePlayerRank
```lua
void ChangePlayerRank(player player, string newRank)
```
Change the player's rank in the party.
----
#### GetPlayers
```lua
{player} GetPlayers(string returnType?)
```
Get all players in the party. At the moment, the only option for `returnType` is `"UserId"`. By default, it will return player instances.
----
#### GetPlayersWithRank
```lua
{Player} GetPlayersWithRank(string rank)
```
Returns all players with the given rank. If you want UserIds, you can just index the party with the rank.
----
#### GetRankOfPlayer
```lua
string GetRankOfPlayer(player player)
```
Returns the rank of the player.
----
#### Destroy
```lua
void Destroy()
```
This is the correct way to dispose of parties.
<br>

## Queue

The queue in Roblox's backend is designed like this:
```
The first two numbers of the key are the priority, the other 4 are the number of entity in this priority

["010001"] = 37292193
   ^  ^ number of entity in the priority
priority (this isn't the same priority you provide)

{
["550001"] = 24762332
["550002"] = 1387132614
["990001"] = {321761, 213871, 213817127} <- group of 3 players
["990002"] = 935144631 <- this would be the 4th entity and 6th player in the queue
["990003"] = 12376612
}

["410784"] = 59826321
	-> priority 41, entity number 784 in priority, player with UserId 59826321
```
### Properties
#### ClassName
```lua
string ClassName
```
A string representing what class this object belongs to.
----
#### Config
```lua
{[string]:any} Config
```
The settings object you passed at [PartyService:GetQueue](https://vaschex.github.io/PartyService/api/#getqueue "GetQueue").
----
### Events
#### PlayerAdded
```lua
RBXScriptSignal PlayerAdded({Player} players)
```
Fires when players in this server have been added to the queue.
----
#### PlayerRemoved
```lua
RBXScriptSignal PlayerRemoved({Player} players)
```
Fires when players in this server have been removed from the queue.
----
### Methods
#### AddAsync
```lua
void AddAsync(Player | {Player | {Player}} players)
```
Add players to the queue. `players` can be a single player or an array containing players and groups.
----
#### RemoveAsync
```lua
void RemoveAsync(player | {player} players)
```
Remove players from the queue.
----
#### Destroy
```lua
void Destroy(boolean wipeQueue?)
```
This is the correct way to dispose of queues. Passing `true` will yield the function and clear the queue in Roblox's backend.