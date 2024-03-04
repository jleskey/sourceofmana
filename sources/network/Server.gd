extends Node

var playerMap : Dictionary			= {}
var onlineList : OnlineList			= OnlineList.new()

class PlayerData:
	var agentRID : int				= NetworkCommons.RidSingleMode
	var rpcDeltas : Dictionary		= {}

#
func AddPlayerData(networkRpcID : int):
	if not networkRpcID in playerMap:
		playerMap[networkRpcID] = PlayerData.new()

func CallMethod(networkRpcID : int, methodName : String, actionDelta : int) -> bool:
	Util.Assert(networkRpcID in playerMap, "Could not find data related to this player: " + str(networkRpcID))
	if networkRpcID in playerMap:
		var oldTick : int = 0
		if methodName in playerMap[networkRpcID].rpcDeltas:
			oldTick = playerMap[networkRpcID].rpcDeltas[methodName]

		var currentTick : int = Time.get_ticks_msec()
		if oldTick + actionDelta <= currentTick:
			playerMap[networkRpcID].rpcDeltas[methodName] = currentTick
			return true

	return false

#
func ConnectPlayer(nickname : String, rpcID : int = NetworkCommons.RidSingleMode):
	if not GetAgent(rpcID) and not nickname in onlineList.GetPlayerNames():
		var agent : BaseAgent = WorldAgent.CreateAgent(Launcher.World.defaultSpawn, 0, nickname)
		playerMap[rpcID].agentRID = agent.get_rid().get_id()

		onlineList.UpdateJson()
		Util.PrintLog("Server", "Player connected: %s (%d)" % [nickname, rpcID])

	elif rpcID != NetworkCommons.RidSingleMode:
		Launcher.Network.peer.disconnect_peer(rpcID)

func DisconnectPlayer(rpcID : int = NetworkCommons.RidSingleMode):
	var player : BaseAgent = GetAgent(rpcID)
	if player:
		Util.PrintLog("Server", "Player disconnected: %s (%d)" % [player.get_name(), rpcID])
		WorldAgent.RemoveAgent(player)
		playerMap.erase(rpcID)
		onlineList.UpdateJson()

#
func SetClickPos(pos : Vector2, rpcID : int = NetworkCommons.RidSingleMode):
	var player : BaseAgent = GetAgent(rpcID)
	if player:
		player.SetRelativeMode(false, Vector2.ZERO)
		player.WalkToward(pos)

func SetMovePos(direction : Vector2, rpcID : int = NetworkCommons.RidSingleMode):
	var player : BaseAgent = GetAgent(rpcID)
	if player:
		player.SetRelativeMode(true, direction.normalized())

func ClearNavigation(rpcID : int = NetworkCommons.RidSingleMode):
	var player : BaseAgent = GetAgent(rpcID)
	if player:
		player.SetRelativeMode(false, Vector2.ZERO)

func TriggerWarp(rpcID : int = NetworkCommons.RidSingleMode):
	var player : BaseAgent = GetAgent(rpcID)
	if player:
		var warp : WarpObject = Launcher.World.CanWarp(player)
		if warp:
			var nextMap : WorldMap = Launcher.World.GetMap(warp.destinationMap)
			if nextMap:
				Launcher.World.Warp(player, nextMap, warp.destinationPos)

func TriggerSit(rpcID : int = NetworkCommons.RidSingleMode):
	var player : BaseAgent = GetAgent(rpcID)
	if player:
		player.SetState(ActorCommons.State.SIT)

func TriggerRespawn(rpcID : int = NetworkCommons.RidSingleMode):
	var player : BaseAgent = GetAgent(rpcID)
	if player is PlayerAgent:
		player.Respawn()

func TriggerEmote(emoteID : int, rpcID : int = NetworkCommons.RidSingleMode):
	NotifyInstance(GetAgent(rpcID), "EmotePlayer", [emoteID])

func TriggerChat(text : String, rpcID : int = NetworkCommons.RidSingleMode):
	NotifyInstance(GetAgent(rpcID), "ChatAgent", [text])

func TriggerInteract(triggeredAgentID : int, rpcID : int = NetworkCommons.RidSingleMode):
	var player : BaseAgent = GetAgent(rpcID)
	if player:
		var triggeredAgent : BaseAgent = WorldAgent.GetAgent(triggeredAgentID)
		if triggeredAgent:
			triggeredAgent.Interact(player)

func TriggerCast(targetID : int, skillName : String, rpcID : int = NetworkCommons.RidSingleMode):
	var player : BaseAgent = GetAgent(rpcID)
	if player and DB.SkillsDB.has(skillName):
		var target : BaseAgent = WorldAgent.GetAgent(targetID)
		Skill.Cast(player, target, DB.SkillsDB[skillName])

func TriggerMorph(rpcID : int = NetworkCommons.RidSingleMode):
	var player : BaseAgent = GetAgent(rpcID)
	if player:
		player.Morph(true)

func TriggerSelect(targetID : int, rpcID : int = NetworkCommons.RidSingleMode):
	var target : BaseAgent = WorldAgent.GetAgent(targetID)
	if target:
		Launcher.Network.UpdateActiveStats(targetID, target.stat.level, target.stat.experience, target.stat.health, target.stat.mana, target.stat.stamina, target.stat.weight, target.stat.entityShape, target.stat.spiritShape, target.stat.morphed, rpcID)

func AddPersonalStat(stat : ActorCommons.PersonalStat, rpcID : int = NetworkCommons.RidSingleMode):
	var player : BaseAgent = GetAgent(rpcID)
	if player and player.stat:
		player.stat.AddPersonalStat(stat)

#
func GetRid(player : PlayerAgent) -> int:
	var playerRid : int = player.get_rid().get_id()
	for dataID in playerMap:
		if playerMap[dataID].agentRID == playerRid:
			return dataID
	Util.Assert(false, "No playerdata associated to this user within the player map")
	return NetworkCommons.RidUnknown

func GetAgent(rpcID : int) -> BaseAgent:
	var agent : BaseAgent	= null
	if rpcID in playerMap:
		var playerData : PlayerData = playerMap.get(rpcID)
		Util.Assert(playerData != null, "No playerdata associated to this user within the player map")
		if playerData:
			agent = WorldAgent.GetAgent(playerData.agentRID)

	return agent

func NotifyInstance(agent : BaseAgent, callbackName : String, args : Array, inclusive : bool = true):
	if not agent or not agent.get_parent():
		Util.Assert(false, "Agent is misintantiated, could not notify instance players with " + callbackName)
		return

	var currentPlayerID = agent.get_rid().get_id()
	if currentPlayerID != null:
		for player in agent.get_parent().players:
			if player != null:
				var playerID = player.get_rid().get_id()
				var peerID = GetRid(player)
				if peerID != NetworkCommons.RidUnknown && (inclusive || playerID != currentPlayerID):
					Launcher.Network.callv(callbackName, [currentPlayerID] + args + [peerID])

#
func ConnectPeer(rpcID : int):
	Util.PrintInfo("Server", "Peer connected: %d" % rpcID)
	var clientPeer : PacketPeer = Launcher.Network.peer.get_peer(rpcID)
	if clientPeer and clientPeer is ENetPacketPeer:
		clientPeer.set_timeout(NetworkCommons.Timeout, NetworkCommons.TimeoutMin, NetworkCommons.TimeoutMax)

func DisconnectPeer(rpcID : int):
	Util.PrintInfo("Server", "Peer disconnected: %d" % rpcID)
	if rpcID in playerMap:
		if WorldAgent.GetAgent(playerMap[rpcID].agentRID):
			DisconnectPlayer(rpcID)
