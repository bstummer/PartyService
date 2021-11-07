# PartyService

PartyService is a stand-alone module which handles all your matchmaking and many other things.

<hr>

Its main features are:

- Feature-rich party system
- Global matchmaking queues including:
    - Priorities
- handles all your MessagingService calls
- handles all your teleportation

PartyService lets you write your own interface and doesn't impose any annoying features. It has a clear and smart API.
This module is built for large games with many players and keeps [MemoryStoreService](https://developer.roblox.com/en-us/articles/memory-store) requests to a minimum.

<br>

Features coming soon:

- Matching based on skill and other heavy improvements
- Tracking of available requests, deal more thriftily with requests when close to limit
- With PartyService's available tools it would be easy to make things like global lobbies/rooms and server lists
- Self-adapting polling cooldown

This module is still in beta and therefore has bugs. MemoryStoreService has bugs as well.