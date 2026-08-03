## Base class for State.
##
## Extend it with your own lifecycle funcs (enter, update, physics_update, exit).
##
## Use transition(to: String) to trigger state switches.
@icon('state_icon.svg')
class_name State
extends FSM

@export_storage var _finite_state_machine: FiniteStateMachine
@export_storage var id: String
@export_storage var NodeOwner : Character

func enter():
	pass

@warning_ignore('unused_parameter')
func update(delta: float):
	pass

@warning_ignore('unused_parameter')
func physics_update(delta: float):
	pass

func exit():
	pass

## Transition to the target State [br]
## For Example: [br]
## transition("RUN") [br]
## transition("IN_AIR/JUMP") [br]
func transition(to_id: String):
	if _finite_state_machine:
		_finite_state_machine.transition(to_id)
