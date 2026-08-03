extends Node
## ═══════════════════════════════════════════
##   МЕНЕДЖЕР ХОДОВ (turn-based)
## ═══════════════════════════════════════════
## Project -> AutoLoad -> "TurnManager".
## Порядок: сначала игрок, затем все враги по очереди.
##
## ОПТИМИЗАЦИЯ: враги вне "активной зоны" (радиус в клетках от игрока
## и/или вне экрана) ходят МГНОВЕННО (без анимаций и пауз) или
## вовсе пропускают ход, пока стоят в Idle — см. background_ai.

signal round_started(number: int)
signal turn_started(actor: Node)
signal turn_ended(actor: Node)
signal game_over

## Пауза между ходами разных врагов (только для АКТИВНЫХ — читаемость)
const AI_TURN_DELAY := 0.2

## ═══════════ ФОНОВЫЕ ИИ ═══════════

enum BackgroundAI {
	FULL,     ## все враги ходят как обычно (старое поведение, медленно)
	INSTANT,  ## далёкие враги ходят мгновенно: без твинов и таймеров
	SKIP,     ## далёкие враги в Idle ПРОПУСКАЮТ ход; Aggro/Search/Alert — мгновенно
}

## Режим обработки врагов вне активной зоны
@export var background_ai : BackgroundAI = BackgroundAI.SKIP
## Радиус активной зоны в КЛЕТКАХ (Chebyshev от игрока). <= 0 — выключить проверку.
@export var active_radius_cells : int = 20
## Врага, видимого камерой, всегда считать активным (даже за радиусом)
@export var treat_on_screen_as_active : bool = true
## Запас за краями экрана для проверки видимости (пиксели)
@export var screen_margin : float = 64.0

var round_number := 0
var current_actor : Node = null

var _running := false
var _synced := false

func _ready() -> void:
	_start.call_deferred()

func _start() -> void:
	if _running: return
	_running = true
	_game_loop()

func _game_loop() -> void:
	# даём миру и акторам инициализироваться
	await get_tree().process_frame
	await get_tree().process_frame

	while _running:
		var player := get_tree().get_first_node_in_group("player")
		if player == null or not is_instance_valid(player):
			await get_tree().create_timer(0.5).timeout
			continue

		if not _synced:
			_sync_actors()
			_synced = true

		if not player.is_alive():
			_running = false
			game_over.emit()
			break

		round_number += 1
		round_started.emit(round_number)

		# ── 1. Ход игрока ──
		if player.has_method("take_turn"):
			await _run_turn(player)

		# ── 2. Ходы ИИ ──
		for e in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(e): continue
			if not e.has_method("take_turn") or not e.is_alive(): continue

			var active := _is_actor_active(e, player)

			if not active:
				match background_ai:
					BackgroundAI.SKIP:
						if _can_skip(e):
							continue   # стоит в Idle вне зоны — ход не считаем вовсе
						_set_instant(e, true)   # Aggro/Search/Alert — мгновенно
					BackgroundAI.INSTANT:
						_set_instant(e, true)
					_:
						_set_instant(e, false)
			else:
				_set_instant(e, false)

			await _run_turn(e)
			_set_instant(e, false)

			# Пауза — только для активных (видимых) врагов
			if active and AI_TURN_DELAY > 0.0:
				await get_tree().create_timer(AI_TURN_DELAY).timeout

		await get_tree().process_frame

func _run_turn(actor: Node) -> void:
	current_actor = actor
	turn_started.emit(actor)
	await actor.take_turn()
	turn_ended.emit(actor)
	current_actor = null

func is_player_turn() -> bool:
	return current_actor != null and current_actor.is_in_group("player")

## ═══════════ АКТИВНАЯ ЗОНА ═══════════

func _set_instant(actor: Node, v: bool) -> void:
	if "instant_turn" in actor:
		actor.instant_turn = v

## Можно ли полностью пропустить ход (режим SKIP): только Idle-враги.
func _can_skip(e: Node) -> bool:
	if e is Enemy:
		return (e as Enemy).state == Enemy.AIState.IDLE
	return false   # неизвестный тип — не рискуем, ходит мгновенно

## Актор активен: в радиусе от игрока ИЛИ виден на экране.
## Если обе проверки выключены — все активны (старое поведение).
func _is_actor_active(e: Node, player: Node) -> bool:
	var checks := 0
	if active_radius_cells > 0:
		checks += 1
		if "grid_pos" in e and "grid_pos" in player \
		and Character.chebyshev(e.grid_pos, player.grid_pos) <= active_radius_cells:
			return true
	if treat_on_screen_as_active and e is Node2D:
		checks += 1
		if _is_on_screen(e as Node2D):
			return true
	return checks == 0

func _is_on_screen(n: Node2D) -> bool:
	var vp := n.get_viewport()
	if vp == null:
		return true
	var rect := vp.get_visible_rect().grow(screen_margin)
	var screen_pos := n.get_global_transform_with_canvas().origin
	return rect.has_point(screen_pos)

## ═══════════ ЗАНЯТОСТЬ КЛЕТОК (вместо коллизий) ═══════════

func is_cell_occupied(cell: Vector2i, ignore: Node = null) -> bool:
	return actor_at(cell, ignore) != null

func actor_at(cell: Vector2i, ignore: Node = null) -> Node:
	for a in _actors():
		if a == ignore: continue
		if a.grid_pos == cell:
			return a
	return null

func _actors() -> Array:
	var out : Array = []
	var pl := get_tree().get_first_node_in_group("player")
	if pl and is_instance_valid(pl) and pl.is_alive():
		out.append(pl)
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.is_alive():
			out.append(e)
	return out

## Привязка всех акторов к сетке после генерации мира.
func _sync_actors() -> void:
	for a in _actors():
		if a.has_method("sync_to_grid"):
			a.sync_to_grid()
