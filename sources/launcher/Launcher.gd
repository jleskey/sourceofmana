extends Node

# High-prio services
var Root				= null
var Path				= null
var FileSystem			= null
var Util				= null
# Specific services
var Scene				= null
var GUI					= null
var Debug				= null
# Low-prio services
var Action				= null
var Audio				= null
var Camera				= null
var Conf				= null
var DB					= null
var Player				= null
var FSM					= null
var Map					= null
var Save				= null
var Settings			= null
var World				= null
var Network				= null

#
func LaunchMode(isClient : bool = false, isServer : bool = false):
	if not isClient and not isServer:
		return

	Network.NetMode(isClient, isServer)
	if isClient:	LaunchClient()
	if isServer:	LaunchServer()
	_post_launch()

	if Scene && not isClient:
		Scene.queue_free()
		Network.NetCreate()

func LaunchClient():
	# Load first low-prio services on which the order is important
	GUI				= Scene.get_node("CanvasLayer")

	if OS.is_debug_build():
		Debug		= FileSystem.LoadSource("debug/Debug.gd")

	# Load then low-prio services on which the order is not important
	Action			= FileSystem.LoadSource("action/Action.gd")
	Audio			= FileSystem.LoadSource("audio/Audio.gd")
	Camera			= FileSystem.LoadSource("camera/Camera.gd")
	FSM				= FileSystem.LoadSource("launcher/FSM.gd")
	Map				= FileSystem.LoadSource("map/Map.gd")
	Settings		= FileSystem.LoadSource("settings/Settings.gd")

func LaunchServer():
	World			= FileSystem.LoadSource("world/World.gd")

#
# Load all high-prio services, order should not be important
func _init():
	Path			= load("res://sources/system/Path.gd").new()
	FileSystem		= load("res://sources/system/FileSystem.gd").new()
	Util			= load("res://sources/util/Util.gd").new()

func _enter_tree():
	Root			= get_tree().get_root()
	Scene			= Root.get_node("Source")

	if not Root or not Path or not FileSystem or not Util or not Scene:
		printerr("Could not initialize source's base services")
		_quit()

func _ready():
	Conf			= FileSystem.LoadSource("conf/Conf.gd")
	DB				= FileSystem.LoadSource("db/DB.gd")
	Network			= FileSystem.LoadSource("network/Network.gd")
	add_child(Network)

	var launchClient : bool = Conf.GetBool("Default", "launchClient", Launcher.Conf.Type.PROJECT)
	var launchServer : bool = Conf.GetBool("Default", "launchServer", Launcher.Conf.Type.PROJECT)

	if "--hybrid" in OS.get_cmdline_args():
		launchClient = true
		launchServer = true
	elif "--client" in OS.get_cmdline_args():
		launchClient = true
		launchServer = false
	elif "--server" in OS.get_cmdline_args():
		launchClient = false
		launchServer = true

	LaunchMode(launchClient, launchServer)

# Call _post_launch functions for service depending on other services
func _post_launch():
	if GUI:			GUI._post_launch()
	if Debug:		Debug._post_launch()
	if Audio:		Audio._post_launch()
	if Conf:		Conf._post_launch()
	if DB:			DB._post_launch()
	if World:		World._post_launch()
	if FSM:			FSM._post_launch()
	if Settings:	Settings._post_launch()

func _process(delta : float):
	if Debug:		Debug._process(delta)
	if FSM:			FSM._process(delta)
	if World:		World._process(delta)

func _quit():
	Launcher.Network.NetDestroy()
	get_tree().quit()
