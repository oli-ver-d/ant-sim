extends TestCase

const DT := 1.0 / 60.0

func _field(half_life: float, diffusion: float, every: int = 4) -> PheromoneField:
	var f := PheromoneField.new(Vector2i(40, 40), 4, every, DT)
	var def := PheromoneChannelDef.new()
	def.half_life = half_life
	def.diffusion = diffusion
	def.cap = 100.0
	def.reinforce = 0.0
	f.add_channel(&"a", def)
	return f

func test_evaporation_half_life() -> void:
	var f := _field(1.0, 0.0)
	f.deposit(0, Vector2(80, 80), 8.0)
	for t in 60:  # one second
		f.update()
	check(absf(f.sample(0, Vector2(80, 80)) - 4.0) < 0.01, "value halves after one half-life, got %f" % f.sample(0, Vector2(80, 80)))

func test_lazy_evaporation_renormalises() -> void:
	var f := _field(0.1, 0.0)
	f.deposit(0, Vector2(80, 80), 50.0)
	for t in 60:  # 10 half-lives: scale drops below the renormalise threshold
		f.update()
	check(f.scale[0] >= PheromoneField.RENORMALISE_BELOW, "scale was renormalised")
	check(absf(f.sample(0, Vector2(80, 80)) - 50.0 / 1024.0) < 0.001, "value correct across renormalisation")

func test_deposit_respects_cap() -> void:
	var f := _field(10.0, 0.0)
	for n in 50:
		f.deposit(0, Vector2(10, 10), 150.0)
	check(absf(f.sample(0, Vector2(10, 10)) - 100.0) < 0.001, "capped at 100")

func test_diffusion_spreads_and_conserves_interior_mass() -> void:
	var f := _field(1e9, 1.0, 1)
	f.deposit(0, Vector2(80, 80), 9.0)
	var before := f.total(0)
	for t in 30:
		f.update()
	check(f.sample(0, Vector2(84, 80)) > 0.0, "neighbour received pheromone")
	check(f.sample(0, Vector2(80, 80)) < 9.0, "centre decreased")
	check(absf(f.total(0) - before) < 0.01 * before, "mass conserved away from edges")

func test_wipe_circle() -> void:
	var f := _field(1e9, 0.0)
	f.deposit(0, Vector2(20, 20), 1.0)
	f.deposit(0, Vector2(140, 140), 1.0)
	f.wipe_circle(Vector2(20, 20), 12.0)
	check_eq(f.sample(0, Vector2(20, 20)), 0.0, "inside wiped")
	check(f.sample(0, Vector2(140, 140)) > 0.0, "outside untouched")

func test_channels_are_independent() -> void:
	var f := _field(1e9, 0.0)
	var def := PheromoneChannelDef.new()
	var b := f.add_channel(&"b", def)
	f.deposit(b, Vector2(40, 40), 1.0)
	check_eq(f.sample(0, Vector2(40, 40)), 0.0, "channel a untouched")
	check(f.sample(b, Vector2(40, 40)) > 0.0, "channel b set")

func test_deposit_takes_max_plus_reinforce() -> void:
	var f := PheromoneField.new(Vector2i(10, 10), 4, 1, DT)
	var def := PheromoneChannelDef.new()
	def.reinforce = 0.5
	f.add_channel(&"a", def)
	f.deposit(0, Vector2(4, 4), 2.0)
	f.deposit(0, Vector2(4, 4), 1.0)  # weaker: max keeps 3.0, reinforce adds 0.5
	check(absf(f.sample(0, Vector2(4, 4)) - 3.5) < 0.001, "got %f" % f.sample(0, Vector2(4, 4)))
