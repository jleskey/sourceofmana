extends Actor
class_name BaseAgent

#
signal agent_killed

#
var agent : NavigationAgent2D			= null
var entityRadius : int					= 0

var actionTimer : Timer					= null
var regenTimer : Timer					= null
var cooldownTimers : Dictionary[int, bool]	= {}

var hasCurrentGoal : bool				= false
var isRelativeMode : bool				= false
var lastPositions : Array[float]		= []

var currentDirection : Vector2			= Vector2.ZERO
var currentOrientation : Vector2		= Vector2.ZERO
var currentSkillID : int				= -1
var currentVelocity : Vector2i			= Vector2i.ZERO
var currentInput : Vector2				= Vector2.ZERO
var forceUpdate : bool					= false
var currentWalkSpeed : Vector2			= Vector2.ZERO

#
func SwitchInputMode(clearCurrentInput : bool):
	hasCurrentGoal = false

	if clearCurrentInput:
		currentInput = Vector2.ZERO
		currentDirection = Vector2.ZERO

func UpdateInput():
	if isRelativeMode:
		if currentDirection != Vector2.ZERO:
			var pos : Vector2i = currentDirection * ActorCommons.DisplacementVector + position
			if WorldNavigation.GetPathLengthSquared(self, pos) <= ActorCommons.MaxDisplacementSquareLength:
				WalkToward(pos)
				currentInput = currentDirection
		else:
			SwitchInputMode(true)

	if hasCurrentGoal:
		if agent and not agent.is_navigation_finished():
			var clampedDirection : Vector2 = Vector2(global_position.direction_to(agent.get_next_path_position()).normalized() * ActorCommons.InputApproximationUnit)
			currentInput = Vector2(clampedDirection) / ActorCommons.InputApproximationUnit

			lastPositions.push_back(agent.distance_to_target())
			if lastPositions.size() > ActorCommons.LastMeanValueMax:
				lastPositions.pop_front()
		else:
			SwitchInputMode(true)

	currentVelocity = currentInput * currentWalkSpeed


func SetVelocity():
	if currentVelocity == Vector2i.ZERO and velocity.is_zero_approx():
		return

	var nextVelocity : Vector2 = Vector2.ZERO
	if state == ActorCommons.State.WALK:
		nextVelocity = currentVelocity
		move_and_slide()

	if velocity != nextVelocity:
		var velocityDiff : Vector2 = (nextVelocity - velocity).abs()
		if (velocityDiff.x + velocityDiff.y) > 5 or velocity.is_zero_approx() or nextVelocity.is_zero_approx():
			velocity = nextVelocity
			forceUpdate = true

func SetCurrentState():
	if stat.health <= 0:
		SetState(ActorCommons.State.DEATH)
	elif currentSkillID != DB.UnknownHash:
		SetState(DB.SkillsDB[currentSkillID].state)
	elif currentVelocity == Vector2i.ZERO:
		SetState(ActorCommons.State.IDLE)
	else:
		SetState(ActorCommons.State.WALK)

func SetState(wantedState : ActorCommons.State) -> bool:
	var nextState : ActorCommons.State = ActorCommons.GetNextTransition(state, wantedState)
	forceUpdate = forceUpdate or nextState != state
	state = nextState
	return state == wantedState

func SetSkillCastID(skillID : int):
	forceUpdate = forceUpdate or currentSkillID in DB.SkillsDB
	currentSkillID = skillID

func AddSkill(cell : SkillCell, proba : float):
	if cell:
		progress.AddSkill(cell, proba)

func AddItem(item : BaseCell, proba : float):
	if item and inventory:
		while proba > 0.0:
			if proba >= 1.0 or randf_range(0.0, 1.0) <= proba:
				inventory.PushItem(item, 1)
				proba -= 1.0
			else:
				break

func SetRelativeMode(enable : bool, givenDirection : Vector2):
	if isRelativeMode != enable:
		isRelativeMode = enable
	if givenDirection == Vector2.ZERO:
		ResetNav()
		isRelativeMode = false
	currentDirection = givenDirection

func WalkToward(pos : Vector2):
	if pos == position:
		return

	if DB.SkillsDB.has(currentSkillID):
		Skill.Stopped(self)

	hasCurrentGoal = true
	lastPositions.clear()
	if agent:
		agent.target_position = pos

func LookAt(target : BaseAgent):
	if target:
		var newOrientation : Vector2 = Vector2(target.position - position).normalized()
		if not newOrientation.is_equal_approx(currentDirection):
			currentOrientation = newOrientation
			forceUpdate = true

func ResetNav():
	WalkToward(position)
	SwitchInputMode(true)

func UpdateChanged():
	forceUpdate = false
	if currentInput != Vector2.ZERO:
		currentOrientation = Vector2(currentVelocity).normalized()
	var functionName : String = "ForceUpdateEntity" if velocity.is_zero_approx() else "UpdateEntity"
	Network.NotifyNeighbours(self, functionName, [velocity, position, currentOrientation, state, currentSkillID])

#
func SetData():
	entityRadius = data._radius
	for skillID in data._skillSet:
		AddSkill(DB.SkillsDB[skillID], data._skillProba[skillID])

	# Navigation
	if !(data._behaviour & AICommons.Behaviour.IMMOBILE):
		if self is PlayerAgent:
			agent = FileSystem.LoadEntityComponent("navigations/PlayerAgent")
		else:
			agent = FileSystem.LoadEntityComponent("navigations/NPAgent")
		agent.set_radius(data._radius)
		agent.set_neighbor_distance(data._radius * 2.0)
		agent.set_avoidance_priority(clampf(data._radius / float(ActorCommons.MaxEntityRadiusSize), 0.0, 1.0))
		agent.velocity_computed.connect(self._velocity_computed)
		add_child.call_deferred(agent)
		RefreshWalkSpeed()

func RefreshWalkSpeed():
	if agent:
		agent.set_max_speed(stat.current.walkSpeed)
	currentWalkSpeed = Vector2(stat.current.walkSpeed, stat.current.walkSpeed)

#
func Damage(_caller : BaseAgent):
	pass

func Interact(_caller : BaseAgent):
	pass

func GetNextShapeID() -> int:
	return stat.shape if stat.IsMorph() else stat.spirit

func GetNextPortShapeID() -> int:
	return stat.spirit if stat.IsSailing() else DB.ShipHash

func Killed():
	agent_killed.emit(self)
	SetSkillCastID(DB.UnknownHash)

#
func _physics_process(_delta):
	# If avoidance is enabled, first set the last calculed velocity as we need
	# to run move_and_slide() in the physics thread only.
	if agent and agent.get_avoidance_enabled():
		SetVelocity()

	UpdateInput()
	# Then update input and defer the next velocity calculus.
	if agent and agent.get_avoidance_enabled():
		agent.set_velocity(currentVelocity)
	# If avoidance is not enabled, just process the callback directly.
	else:
		_velocity_computed(currentVelocity)
		SetVelocity()

	if forceUpdate:
		UpdateChanged()

func _velocity_computed(safeVelocity : Vector2i):
	currentVelocity = safeVelocity
	SetCurrentState()

func _ready():
	set_name.call_deferred(str(get_rid().get_id()))

	actionTimer = Timer.new()
	actionTimer.set_name("ActionTimer")
	actionTimer.set_one_shot(true)
	add_child.call_deferred(actionTimer)

func _init(_type : ActorCommons.Type = ActorCommons.Type.NPC, _data : EntityData = null, _nick : String = "", isManaged : bool = false):
	stat.entity_stats_updated.connect(RefreshWalkSpeed)
	super._init(_type, _data, _nick, isManaged)
