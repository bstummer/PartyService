This section contains general information about PartyService.

<hr>

- Matching is not 100% done and will be heavily improved in the future.

- All party members are in the same server, parties don't exist in multiple servers.

- Parties always have a leader. If the leader gets removed, a random player will become leader.

- [AddAsync](https://vaschex.github.io/PartyService/api#addasync) and [RemoveAsync](https://vaschex.github.io/PartyService/api#removeasync) are built for multiple players. It is possible to use a single player, but try to use multiple in order to save requests.

- Network calls are automatically retried, so you don't have to use [pcall](https://www.lua.org/pil/8.4.html) unless you want to add additional error handling.

- One player in the queue takes up `10 + Length of UserId` bytes, a group takes up `11 + Length of the UserIds + Amount of players`.

Information on PartyService limits:

- Priorities range from 1 to 99
- 9999 entities per priority (so *theoretically* 989,901 entities per queue)

Information on [MSS limits](https://developer.roblox.com/en-us/articles/memory-store#limits):

- For each player in the game, you get 100 `AvailableRequests` per minute
  (capped at 1000 players/100,000 requests)
- While your `SpentRequests` in the last 60 seconds + your
  `AvailableRequests` are lower than the limit, it will regenerate
  `math.ceil(limit / 60)` requests per second