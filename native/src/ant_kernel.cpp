#include "ant_kernel.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <limits>

using namespace godot;

// --- Engine/GDScript maths, reproduced exactly -----------------------------------
// GDScript floats are doubles and Vector2 holds float32s. Each helper below
// is the engine's own code (Godot 4.7 core/math) for the precision GDScript
// uses it at, so native results match the GDScript behaviours bit for bit.

namespace {

constexpr double PI_D = 3.1415926535897932384626433833;
constexpr double TAU_D = 6.2831853071795864769252867666;
constexpr double EPSILON_D = 0.00001; // the engine's CMP_EPSILON
constexpr double INF_D = std::numeric_limits<double>::infinity();

inline bool is_equal_approx(double p_left, double p_right) {
	if (p_left == p_right) {
		return true;
	}
	double tolerance = EPSILON_D * std::abs(p_left);
	if (tolerance < EPSILON_D) {
		tolerance = EPSILON_D;
	}
	return std::abs(p_left - p_right) < tolerance;
}

// wrapf(value, min, max)
inline double wrapf(double p_value, double p_min, double p_max) {
	double range = p_max - p_min;
	if (std::abs(range) < EPSILON_D) {
		return p_min;
	}
	double result = p_value - (range * std::floor((p_value - p_min) / range));
	if (is_equal_approx(result, p_max)) {
		return p_min;
	}
	return result;
}

inline double wrap_angle(double p_value) {
	return wrapf(p_value, -PI_D, PI_D);
}

// angle_difference(from, to)
inline double angle_difference(double p_from, double p_to) {
	double difference = std::fmod(p_to - p_from, TAU_D);
	return std::fmod(2.0 * difference, TAU_D) - difference;
}

// clampf / minf / maxf (the engine's CLAMP, MIN and MAX macros).
inline double clampf(double p_x, double p_min, double p_max) {
	return p_x < p_min ? p_min : (p_x > p_max ? p_max : p_x);
}
inline double minf(double p_a, double p_b) {
	return p_a < p_b ? p_a : p_b;
}
inline double maxf(double p_a, double p_b) {
	return p_a > p_b ? p_a : p_b;
}

// Vector2 in float32, as the engine does it.
struct V2 {
	float x;
	float y;
};

inline V2 v2(const Vector2 &p_v) {
	return V2{ p_v.x, p_v.y };
}
inline Vector2 vec(const V2 &p_v) {
	return Vector2(p_v.x, p_v.y);
}
// Vector2(double, double)
inline V2 v2d(double p_x, double p_y) {
	return V2{ (float)p_x, (float)p_y };
}
inline V2 add(const V2 &p_a, const V2 &p_b) {
	return V2{ p_a.x + p_b.x, p_a.y + p_b.y };
}
inline V2 sub(const V2 &p_a, const V2 &p_b) {
	return V2{ p_a.x - p_b.x, p_a.y - p_b.y };
}
// Vector2 * float (the float is narrowed to real_t first).
inline V2 mul(const V2 &p_a, double p_s) {
	float s = (float)p_s;
	return V2{ p_a.x * s, p_a.y * s };
}
// Vector2.from_angle(angle)
inline V2 from_angle(double p_angle) {
	float a = (float)p_angle;
	return V2{ std::cos(a), std::sin(a) };
}
// Vector2.angle()
inline double angle(const V2 &p_v) {
	return std::atan2(p_v.y, p_v.x);
}
// Vector2.length()
inline double length(const V2 &p_v) {
	return std::sqrt(p_v.x * p_v.x + p_v.y * p_v.y);
}
// Vector2.distance_to()
inline double distance_to(const V2 &p_a, const V2 &p_b) {
	return std::sqrt((p_a.x - p_b.x) * (p_a.x - p_b.x) + (p_a.y - p_b.y) * (p_a.y - p_b.y));
}
// Vector2.distance_squared_to()
inline double distance_squared_to(const V2 &p_a, const V2 &p_b) {
	return (p_a.x - p_b.x) * (p_a.x - p_b.x) + (p_a.y - p_b.y) * (p_a.y - p_b.y);
}
// Vector2.rotated(angle)
inline V2 rotated(const V2 &p_v, double p_by) {
	float by = (float)p_by;
	float sine = std::sin(by);
	float cosi = std::cos(by);
	return V2{ p_v.x * cosi - p_v.y * sine, p_v.x * sine + p_v.y * cosi };
}

// Steering.turn_toward()
inline double turn_toward(const V2 &p_at, double p_heading, const V2 &p_goal) {
	double diff = angle_difference(p_heading, angle(sub(p_goal, p_at)));
	return clampf(diff * 2.0, -1.0, 1.0);
}

// Steering.home_turn()
inline double home_turn(const V2 &p_at, double p_heading, const V2 &p_home, double p_pheromone_turn, double p_bias,
		double p_cone) {
	double toward = turn_toward(p_at, p_heading, p_home);
	if (p_cone > 0.0 && std::abs(angle_difference(p_heading, angle(sub(p_home, p_at)))) > p_cone) {
		return toward;
	}
	return clampf(p_pheromone_turn + p_bias * toward, -1.0, 1.0);
}

// Steering.AVOID_PROBE_ANGLE, AVOID_WIDE_ANGLE
constexpr double AVOID_PROBE_ANGLE = 0.7;
constexpr double AVOID_WIDE_ANGLE = 1.4;

inline int64_t now_usec() {
	return std::chrono::duration_cast<std::chrono::microseconds>(
			std::chrono::steady_clock::now().time_since_epoch())
			.count();
}

} // namespace

// --- World and pheromone lookups -------------------------------------------------

// World.is_blocked() (World.cell_at() inlined).
bool AntKernel::world_blocked(const Layer &p_l, const Vector2 &p_at) const {
	if (p_at.x < 0.0f || p_at.y < 0.0f) {
		return true;
	}
	int64_t cx = (int64_t)((double)p_at.x * p_l.inv_cell);
	int64_t cy = (int64_t)((double)p_at.y * p_l.inv_cell);
	if (cx >= p_l.width || cy >= p_l.height) {
		return true;
	}
	return p_l.obstacles[cy * p_l.width + cx] != 0;
}

// Steering.avoid_turn()
double AntKernel::avoid_turn(const Layer &p_l, const Vector2 &p_at, double p_heading, double p_lookahead) const {
	V2 at = v2(p_at);
	bool ahead = world_blocked(p_l, vec(add(at, mul(from_angle(p_heading), p_lookahead))));
	bool left = world_blocked(p_l, vec(add(at, mul(from_angle(p_heading - AVOID_PROBE_ANGLE), p_lookahead))));
	bool right = world_blocked(p_l, vec(add(at, mul(from_angle(p_heading + AVOID_PROBE_ANGLE), p_lookahead))));
	if (!ahead && !left && !right) {
		return 0.0;
	}
	if (!ahead && left && right) {
		return 0.0;
	}
	if (left && !right) {
		return 1.0;
	}
	if (right && !left) {
		return -1.0;
	}
	bool wide_left = world_blocked(p_l, vec(add(at, mul(from_angle(p_heading - AVOID_WIDE_ANGLE), p_lookahead))));
	bool wide_right = world_blocked(p_l, vec(add(at, mul(from_angle(p_heading + AVOID_WIDE_ANGLE), p_lookahead))));
	if (wide_right && !wide_left) {
		return -1.0;
	}
	return 1.0;
}

// Steering.sense_turn()
double AntKernel::sense_turn_impl(int64_t p_c, const Vector2 &p_at, double p_heading, const Colony &p_colony,
		const Layer &p_l) const {
	const float *values = p_l.values;
	int64_t off = p_c * p_l.cell_count;
	double inv = p_l.p_inv_cell;
	int64_t w = p_l.p_width;
	int64_t h = p_l.p_height;
	double fx = std::cos(p_heading) * p_colony.sensor_distance;
	double fy = std::sin(p_heading) * p_colony.sensor_distance;
	double ca = p_colony.sensor_cos;
	double sa = p_colony.sensor_sin;
	double ax = p_at.x;
	double ay = p_at.y;

	double centre = 0.0;
	double x = ax + fx;
	double y = ay + fy;
	if (x >= 0.0 && y >= 0.0 && (int64_t)(x * inv) < w && (int64_t)(y * inv) < h) {
		centre = values[off + (int64_t)(y * inv) * w + (int64_t)(x * inv)];
	}
	double left = 0.0;
	x = ax + fx * ca + fy * sa;
	y = ay - fx * sa + fy * ca;
	if (x >= 0.0 && y >= 0.0 && (int64_t)(x * inv) < w && (int64_t)(y * inv) < h) {
		left = values[off + (int64_t)(y * inv) * w + (int64_t)(x * inv)];
	}
	double right = 0.0;
	x = ax + fx * ca - fy * sa;
	y = ay + fx * sa + fy * ca;
	if (x >= 0.0 && y >= 0.0 && (int64_t)(x * inv) < w && (int64_t)(y * inv) < h) {
		right = values[off + (int64_t)(y * inv) * w + (int64_t)(x * inv)];
	}

	if (centre >= left && centre >= right) {
		return 0.0;
	}
	if (maxf(left, right) * (double)p_l.scale[p_c] < p_colony.sense_threshold) {
		return 0.0;
	}
	return left > right ? -1.0 : 1.0;
}

// Steering.sense_away() (with Steering._sample_open()).
double AntKernel::sense_away_impl(int64_t p_c, const Vector2 &p_at, double p_heading, const Colony &p_colony,
		const Layer &p_l) const {
	auto sample_open = [&](const V2 &p) -> double {
		if (world_blocked(p_l, vec(p))) {
			return INF_D;
		}
		// PheromoneField.sample_raw()
		int64_t cx = (int64_t)((double)p.x * p_l.p_inv_cell);
		int64_t cy = (int64_t)((double)p.y * p_l.p_inv_cell);
		if (p.x < 0.0f || p.y < 0.0f || cx >= p_l.p_width || cy >= p_l.p_height) {
			return 0.0;
		}
		return p_l.values[p_c * p_l.cell_count + cy * p_l.p_width + cx];
	};
	V2 at = v2(p_at);
	V2 fwd = mul(v2d(std::cos(p_heading), std::sin(p_heading)), p_colony.sensor_distance);
	double centre = sample_open(add(at, fwd));
	double left = sample_open(add(at, rotated(fwd, -p_colony.sensor_angle)));
	double right = sample_open(add(at, rotated(fwd, p_colony.sensor_angle)));
	if (centre <= left && centre <= right) {
		return 0.0;
	}
	double strongest = 0.0;
	for (double v : { centre, left, right }) {
		if (v < INF_D) {
			strongest = maxf(strongest, v);
		}
	}
	if (strongest * (double)p_l.scale[p_c] < p_colony.sense_threshold) {
		return 0.0;
	}
	return left < right ? -1.0 : 1.0;
}

// --- Movement --------------------------------------------------------------------

// Steering.move()
void AntKernel::move_impl(int64_t p_i, double p_desired_turn, double p_move_speed, double p_dt) {
	const Colony &colony = colonies[ants.colony_id[p_i]];
	int64_t c = ants.caste_id[p_i];
	const Layer &world = layers[ants.layer[p_i]];
	Vector2 at = ants.pos[p_i];
	double h = ants.heading[p_i];
	double max_turn = colony.turn_rate[c];

	double turn = p_desired_turn * max_turn + rng->randf_range(-1.0, 1.0) * colony.wander_strength;
	double avoid = 0.0;
	int64_t cell = (int64_t)((double)at.y * world.inv_cell) * world.width + (int64_t)((double)at.x * world.inv_cell);
	bool near = world.near_blocked[cell] != 0;
	if (near) {
		avoid = avoid_turn(world, at, h, colony.avoid_lookahead);
		if (avoid != 0.0) {
			turn = avoid * max_turn;
		}
	}
	turn = clampf(turn, -max_turn, max_turn);
	h = wrap_angle(h + turn * p_dt);

	double step_len = p_move_speed * p_dt;
	if (world.clutter[cell] != 0) {
		step_len *= colony.clutter_slowdown;
	}
	Vector2 next((float)((double)at.x + std::cos(h) * step_len), (float)((double)at.y + std::sin(h) * step_len));
	bool blocked = false;
	if (near) {
		blocked = world_blocked(world, next);
	}
	if (avoid != 0.0 || blocked) {
		ants.since_obstacle[p_i] = 0.0f;
	}
	if (blocked) {
		h = wrap_angle(h + (avoid != 0.0 ? avoid : 1.0) * max_turn * p_dt);
		step_len = 0.0;
	} else {
		ants.pos[p_i] = next;
	}
	ants.heading[p_i] = (float)h;
	ants.anim_phase[p_i] = (float)((double)ants.anim_phase[p_i] + step_len * (double)colony.phase_per_unit[c]);
}

// Steering.move_to()
void AntKernel::move_to_impl(int64_t p_i, const Vector2 &p_goal, double p_move_speed, double p_dt) {
	const Colony &colony = colonies[ants.colony_id[p_i]];
	int64_t c = ants.caste_id[p_i];
	const Layer &world = layers[ants.layer[p_i]];
	V2 at = v2(ants.pos[p_i]);
	V2 to = sub(v2(p_goal), at);
	double dist = length(to);
	double h = ants.heading[p_i];
	double max_turn = (double)colony.turn_rate[c] * 1.5;
	double wander = rng->randf_range(-1.0, 1.0) * colony.wander_strength * 0.25;
	double step_len = 0.0;
	if (dist > 0.05) {
		double diff = angle_difference(h, angle(to));
		h = wrap_angle(h + clampf(diff * 5.0 + wander, -max_turn, max_turn) * p_dt);
		double facing = std::cos(angle_difference(h, angle(to)));
		step_len = minf(p_move_speed * p_dt * clampf(0.25 + 0.75 * facing, 0.2, 1.0), dist);
	}
	V2 fwd = v2d(std::cos(h), std::sin(h));
	V2 next = add(at, mul(fwd, step_len));
	if (step_len > 0.0 && world_blocked(world, vec(next))) {
		V2 slide_x{ next.x, at.y };
		V2 slide_y{ at.x, next.y };
		if (std::abs((double)fwd.x) >= std::abs((double)fwd.y) && !world_blocked(world, vec(slide_x))) {
			next = slide_x;
		} else if (!world_blocked(world, vec(slide_y))) {
			next = slide_y;
		} else if (!world_blocked(world, vec(slide_x))) {
			next = slide_x;
		} else {
			next = at;
			ants.since_obstacle[p_i] = 0.0f;
		}
		step_len = distance_to(at, next);
	}
	ants.pos[p_i] = vec(next);
	ants.heading[p_i] = (float)h;
	ants.anim_phase[p_i] = (float)((double)ants.anim_phase[p_i] + step_len * (double)colony.phase_per_unit[c]);
}

// Simulation.lay()
void AntKernel::lay_impl(int64_t p_i, int64_t p_c) {
	const Colony &colony = colonies[ants.colony_id[p_i]];
	double amount = colony.deposit_base * std::exp(-(double)ants.source_age[p_i] * colony.deposit_decay);
	Layer &field = layers[ants.layer[p_i]];
	Vector2 at = ants.pos[p_i];
	int64_t row = (int64_t)((double)at.y * field.p_inv_cell);
	int64_t idx = p_c * field.cell_count + row * field.p_width + (int64_t)((double)at.x * field.p_inv_cell);
	field.row_active[p_c * field.p_height + row] = 1;
	double s = field.scale[p_c];
	double a = amount / s;
	field.values[idx] = (float)minf(maxf(field.values[idx], a) + a * (double)field.reinforce[p_c], (double)field.cap[p_c] / s);
}

// --- Whole behaviour ticks -----------------------------------------------------------

// The turn follow_trail and carry_home make on their way home: straight for
// the entrance once it is in sight, otherwise the trail plus path integration.
double AntKernel::nest_turn(int64_t p_i, const Colony &p_colony, const double *p_params, const Layer &p_l) const {
	V2 at = v2(ants.pos[p_i]);
	V2 entrance = v2(p_colony.entrance);
	double heading = ants.heading[p_i];
	double turn = 0.0;
	if (p_colony.has_entrance && distance_squared_to(at, entrance) < p_colony.sense_radius * p_colony.sense_radius) {
		turn = turn_toward(at, heading, entrance);
	} else {
		int64_t follow = (int64_t)p_params[SLOT_FOLLOW];
		if (follow >= 0) {
			turn = sense_turn_impl(follow, ants.pos[p_i], heading, p_colony, p_l);
		}
		if (p_colony.has_entrance && (double)ants.since_obstacle[p_i] >= p_colony.obstacle_memory) {
			turn = home_turn(at, heading, entrance, turn, p_params[SLOT_HOME_BIAS], p_params[SLOT_HOME_CONE]);
		}
	}
	return turn;
}

// One tick of ant i in a native state. Returns false, having changed
// nothing, if this tick needs the GDScript behaviour (it will change state,
// or needs something only GDScript knows, e.g. food sources).
bool AntKernel::tick_ant(int64_t p_i, int64_t p_tick_count) {
	const Colony &colony = colonies[ants.colony_id[p_i]];
	const double *p = &colony.params[(ants.caste_id[p_i] * colony.num_states + ants.state[p_i]) * SLOT_COUNT];
	int kind = (int)p[SLOT_KIND];
	// What GDScript's `timer[i] += dt` leaves in the float32 array.
	double timer = (float)((double)ants.timer[p_i] + dt);
	V2 at = v2(ants.pos[p_i]);
	auto at_nest = [&]() -> bool {
		return colony.has_entrance && distance_squared_to(at, v2(colony.entrance)) <= colony.radius * colony.radius;
	};

	bool food_check = false;
	switch (kind) {
		case KIND_EXPLORE: {
			// The food check tick: find_sensed_food() can only find something
			// within a food source's sense_bound(), so elsewhere the tick is
			// ours (the check then only notes passing the nest).
			food_check = (p_tick_count + p_i) % colony.food_check_interval == 0;
			if (food_check && (!colony.nest_native || food_near(colony, vec(at)))) {
				return false;
			}
			double give_up = ants.scratch_f0[p_i];
			if (give_up > 0.0 && timer > give_up) {
				return false;
			}
		} break;
		case KIND_FOLLOW_TRAIL: {
			if (!colony.nest_native || at_nest() || timer > p[SLOT_TIMEOUT]) {
				return false;
			}
		} break;
		case KIND_CARRY_HOME: {
			if (!colony.nest_native || at_nest()) {
				return false;
			}
		} break;
		case KIND_LINGER: {
			if (!colony.nest_native || (p[SLOT_DURATION] > 0.0 && timer > p[SLOT_DURATION])) {
				return false;
			}
		} break;
		default:
			return false;
	}

	ants.timer[p_i] = (float)timer;
	ants.source_age[p_i] = (float)((double)ants.source_age[p_i] + dt);
	ants.since_obstacle[p_i] = (float)((double)ants.since_obstacle[p_i] + dt);
	const Layer &l = layers[ants.layer[p_i]];
	double speed = ants.speed[p_i];

	switch (kind) {
		case KIND_EXPLORE: {
			if (food_check && at_nest()) {
				ants.source_age[p_i] = 0.0f;
			}
			double turn = 0.0;
			int64_t follow = (int64_t)p[SLOT_FOLLOW];
			if (follow >= 0) {
				turn = sense_turn_impl(follow, vec(at), ants.heading[p_i], colony, l);
			}
			int64_t avoid = (int64_t)p[SLOT_AVOID];
			if (turn == 0.0 && avoid >= 0) {
				turn = sense_away_impl(avoid, vec(at), ants.heading[p_i], colony, l);
			}
			move_impl(p_i, turn, speed, dt);
		} break;
		case KIND_FOLLOW_TRAIL: {
			move_impl(p_i, nest_turn(p_i, colony, p, l), speed, dt);
		} break;
		case KIND_CARRY_HOME: {
			double turn = nest_turn(p_i, colony, p, l);
			double mass = ants.carried[p_i] >= 0 ? ants.carry_mass[p_i] : 0.0;
			move_impl(p_i, turn, speed / (1.0 + mass * colony.carry_mass_slowdown), dt);
		} break;
		case KIND_LINGER: {
			double turn = 0.0;
			if (colony.has_entrance) {
				V2 home = v2(colony.entrance);
				double r = p[SLOT_RADIUS];
				double d2 = distance_squared_to(at, home);
				if (d2 > r * r) {
					turn = turn_toward(at, ants.heading[p_i], home);
				}
				if (at_nest()) {
					ants.source_age[p_i] = 0.0f;
				}
			}
			move_impl(p_i, turn, speed * p[SLOT_SPEED_FACTOR], dt);
			return true;
		}
	}
	int64_t lay_channel = (int64_t)p[SLOT_LAY];
	if (lay_channel >= 0) {
		lay_impl(p_i, lay_channel);
	}
	return true;
}

// Updates ants from p_from up to p_end in order, as Simulation.step_ants
// would, until one needs GDScript. Returns its index (or p_end).
int64_t AntKernel::run(int64_t p_from, int64_t p_end, int64_t p_tick_count) {
	if (ants.alive == nullptr) {
		return p_from;
	}
	for (int64_t i = p_from; i < p_end; i++) {
		if (ants.alive[i] == 0) {
			continue;
		}
		if (ants.transit_until[i] != 0) {
			return i;
		}
		int64_t ci = ants.colony_id[i];
		if (ci >= (int64_t)colonies.size() || !colonies[ci].set || ants.layer[i] >= layers.size() || !layers[ants.layer[i]].bound) {
			return i;
		}
		const Colony &colony = colonies[ci];
		if (colony.params[(ants.caste_id[i] * colony.num_states + ants.state[i]) * SLOT_COUNT + SLOT_KIND] == KIND_GDSCRIPT) {
			return i;
		}
		if (profiling) {
			int64_t li = ants.layer[i];
			int64_t t0 = now_usec();
			if (!tick_ant(i, p_tick_count)) {
				return i;
			}
			layer_usec[li] += now_usec() - t0;
			layer_ant_ticks[li] += 1;
		} else if (!tick_ant(i, p_tick_count)) {
			return i;
		}
	}
	return p_end;
}

// --- Setup ---------------------------------------------------------------------------

AntKernel::Colony &AntKernel::colony_slot(int64_t p_colony) {
	if ((int64_t)colonies.size() <= p_colony) {
		colonies.resize(p_colony + 1);
	}
	return colonies[p_colony];
}

void AntKernel::set_rng(const Ref<RandomNumberGenerator> &p_rng) {
	rng = p_rng;
}

void AntKernel::set_dt(double p_dt) {
	dt = p_dt;
}

template <typename T, typename A>
static T *raw(const A &p_array) {
	return const_cast<T *>(reinterpret_cast<const T *>(p_array.ptr()));
}

void AntKernel::bind_ants(const PackedByteArray &p_alive, const PackedVector2Array &p_pos, const PackedFloat32Array &p_heading,
		const PackedFloat32Array &p_speed, const PackedByteArray &p_colony_id, const PackedByteArray &p_caste_id,
		const PackedByteArray &p_state, const PackedInt32Array &p_carried, const PackedFloat32Array &p_timer,
		const PackedFloat32Array &p_source_age, const PackedFloat32Array &p_since_obstacle,
		const PackedFloat32Array &p_scratch_f0, const PackedFloat32Array &p_anim_phase, const PackedByteArray &p_layer,
		const PackedInt32Array &p_transit_until, const PackedFloat64Array &p_carry_mass) {
	ants.alive = raw<uint8_t>(p_alive);
	ants.pos = raw<Vector2>(p_pos);
	ants.heading = raw<float>(p_heading);
	ants.speed = raw<float>(p_speed);
	ants.colony_id = raw<uint8_t>(p_colony_id);
	ants.caste_id = raw<uint8_t>(p_caste_id);
	ants.state = raw<uint8_t>(p_state);
	ants.carried = raw<int32_t>(p_carried);
	ants.timer = raw<float>(p_timer);
	ants.source_age = raw<float>(p_source_age);
	ants.since_obstacle = raw<float>(p_since_obstacle);
	ants.scratch_f0 = raw<float>(p_scratch_f0);
	ants.anim_phase = raw<float>(p_anim_phase);
	ants.layer = raw<uint8_t>(p_layer);
	ants.transit_until = raw<int32_t>(p_transit_until);
	ants.carry_mass = raw<double>(p_carry_mass);
	ants.capacity = p_alive.size();
}

int64_t AntKernel::check_ants(const PackedByteArray &p_alive, const PackedVector2Array &p_pos, const PackedFloat32Array &p_heading,
		const PackedFloat32Array &p_speed, const PackedByteArray &p_colony_id, const PackedByteArray &p_caste_id,
		const PackedByteArray &p_state, const PackedInt32Array &p_carried, const PackedFloat32Array &p_timer,
		const PackedFloat32Array &p_source_age, const PackedFloat32Array &p_since_obstacle,
		const PackedFloat32Array &p_scratch_f0, const PackedFloat32Array &p_anim_phase, const PackedByteArray &p_layer,
		const PackedInt32Array &p_transit_until, const PackedFloat64Array &p_carry_mass) const {
	const void *bound[] = { ants.alive, ants.pos, ants.heading, ants.speed, ants.colony_id, ants.caste_id, ants.state,
		ants.carried, ants.timer, ants.source_age, ants.since_obstacle, ants.scratch_f0, ants.anim_phase, ants.layer,
		ants.transit_until, ants.carry_mass };
	const void *now[] = { p_alive.ptr(), p_pos.ptr(), p_heading.ptr(), p_speed.ptr(), p_colony_id.ptr(), p_caste_id.ptr(),
		p_state.ptr(), p_carried.ptr(), p_timer.ptr(), p_source_age.ptr(), p_since_obstacle.ptr(), p_scratch_f0.ptr(),
		p_anim_phase.ptr(), p_layer.ptr(), p_transit_until.ptr(), p_carry_mass.ptr() };
	int64_t mask = 0;
	for (int k = 0; k < 16; k++) {
		if (bound[k] != now[k]) {
			mask |= int64_t(1) << k;
		}
	}
	return mask;
}

void AntKernel::bind_layer(int64_t p_layer, const PackedByteArray &p_obstacles, const PackedByteArray &p_near_blocked,
		const PackedByteArray &p_clutter, int64_t p_width, int64_t p_height, double p_inv_cell,
		const PackedFloat32Array &p_values, const PackedByteArray &p_row_active, const PackedFloat32Array &p_scale,
		const PackedFloat32Array &p_reinforce, const PackedFloat32Array &p_cap, int64_t p_cell_size, int64_t p_p_width, int64_t p_p_height,
		double p_p_inv_cell) {
	if ((int64_t)layers.size() <= p_layer) {
		layers.resize(p_layer + 1);
		layer_usec.resize(p_layer + 1);
		layer_ant_ticks.resize(p_layer + 1);
	}
	Layer &l = layers[p_layer];
	l.obstacles = raw<uint8_t>(p_obstacles);
	l.near_blocked = raw<uint8_t>(p_near_blocked);
	l.clutter = raw<uint8_t>(p_clutter);
	l.width = p_width;
	l.height = p_height;
	l.inv_cell = p_inv_cell;
	l.values = raw<float>(p_values);
	l.row_active = raw<uint8_t>(p_row_active);
	l.scale = raw<float>(p_scale);
	l.reinforce = raw<float>(p_reinforce);
	l.cap = raw<float>(p_cap);
	l.p_width = p_p_width;
	l.p_height = p_p_height;
	l.cell_count = p_p_width * p_p_height;
	l.p_inv_cell = p_p_inv_cell;
	l.cell_size = p_cell_size;
	l.bound = l.near_blocked != nullptr && (l.values != nullptr || l.cell_count == 0);
}

int64_t AntKernel::check_layer(int64_t p_layer, const PackedByteArray &p_obstacles, const PackedByteArray &p_near_blocked,
		const PackedByteArray &p_clutter, const PackedFloat32Array &p_values, const PackedByteArray &p_row_active,
		const PackedFloat32Array &p_scale) const {
	if (p_layer >= (int64_t)layers.size()) {
		return -1;
	}
	const Layer &l = layers[p_layer];
	const void *bound[] = { l.obstacles, l.near_blocked, l.clutter, l.values, l.row_active, l.scale };
	const void *now[] = { p_obstacles.ptr(), p_near_blocked.ptr(), p_clutter.ptr(), p_values.ptr(), p_row_active.ptr(),
		p_scale.ptr() };
	int64_t mask = 0;
	for (int k = 0; k < 6; k++) {
		if (bound[k] != now[k]) {
			mask |= int64_t(1) << k;
		}
	}
	return mask;
}

void AntKernel::set_colony(int64_t p_colony, const PackedFloat64Array &p_values, const PackedFloat32Array &p_turn_rate,
		const PackedFloat32Array &p_phase_per_unit, int64_t p_num_states) {
	ERR_FAIL_COND(p_values.size() < 13);
	Colony &c = colony_slot(p_colony);
	c.sensor_distance = p_values[0];
	c.sensor_cos = p_values[1];
	c.sensor_sin = p_values[2];
	c.sensor_angle = p_values[3];
	c.sense_threshold = p_values[4];
	c.wander_strength = p_values[5];
	c.avoid_lookahead = p_values[6];
	c.deposit_base = p_values[7];
	c.deposit_decay = p_values[8];
	c.carry_mass_slowdown = p_values[9];
	c.clutter_slowdown = p_values[10];
	c.obstacle_memory = p_values[11];
	c.food_check_interval = (int64_t)p_values[12];
	c.turn_rate.assign(p_turn_rate.ptr(), p_turn_rate.ptr() + p_turn_rate.size());
	c.phase_per_unit.assign(p_phase_per_unit.ptr(), p_phase_per_unit.ptr() + p_phase_per_unit.size());
	c.num_states = p_num_states;
	c.params.assign(c.turn_rate.size() * p_num_states * SLOT_COUNT, 0.0);
	c.set = false;
}

void AntKernel::set_state_params(int64_t p_colony, const PackedFloat64Array &p_params) {
	Colony &c = colony_slot(p_colony);
	ERR_FAIL_COND(p_params.size() != (int64_t)c.params.size());
	c.params.assign(p_params.ptr(), p_params.ptr() + p_params.size());
	c.set = true;
}

void AntKernel::set_nest(int64_t p_colony, bool p_native, bool p_has_entrance, const Vector2 &p_entrance, double p_radius,
		double p_sense_radius) {
	Colony &c = colony_slot(p_colony);
	c.nest_native = p_native;
	c.has_entrance = p_has_entrance;
	c.entrance = p_entrance;
	c.radius = p_radius;
	c.sense_radius = p_sense_radius;
}

void AntKernel::set_food(int64_t p_colony, const PackedFloat64Array &p_circles) {
	Colony &c = colony_slot(p_colony);
	c.food.assign(p_circles.ptr(), p_circles.ptr() + p_circles.size());
}

// True if `p_at` is within some food source's sense_bound() (so the
// colony's food check might find it).
bool AntKernel::food_near(const Colony &p_colony, const Vector2 &p_at) const {
	const std::vector<double> &food = p_colony.food;
	for (size_t k = 0; k + 2 < food.size(); k += 3) {
		double dx = (double)p_at.x - food[k];
		double dy = (double)p_at.y - food[k + 1];
		if (dx * dx + dy * dy <= food[k + 2] * food[k + 2]) {
			return true;
		}
	}
	return false;
}

// --- Navigation fields (NavGrid) -------------------------------------------------------

// NavGrid neighbour offsets, orthogonal first.
static const int64_t NAV_DX[8] = { 1, -1, 0, 0, 1, 1, -1, -1 };
static const int64_t NAV_DY[8] = { 0, 0, 1, -1, 1, -1, 1, -1 };
static const int32_t NAV_UNREACHED = 1 << 30;
static const int64_t NAV_STRAIGHT = 5;

// NavGrid._best_neighbour()
int64_t AntKernel::best_neighbour(const Layer &p_l, const int32_t *p_dist, int64_t p_cell) const {
	int64_t w = p_l.width;
	int64_t h = p_l.height;
	const uint8_t *obs = p_l.obstacles;
	int64_t cx = p_cell % w;
	int64_t cy = p_cell / w;
	int64_t best = -1;
	int64_t best_d = NAV_UNREACHED;
	for (int k = 0; k < 8; k++) {
		int64_t nx = cx + NAV_DX[k];
		int64_t ny = cy + NAV_DY[k];
		if (nx < 0 || ny < 0 || nx >= w || ny >= h) {
			continue;
		}
		int64_t n = ny * w + nx;
		if (obs[n] != 0) {
			continue;
		}
		if (k >= 4 && (obs[cy * w + nx] != 0 || obs[ny * w + cx] != 0)) {
			continue;
		}
		if (p_dist[n] < best_d) {
			best_d = p_dist[n];
			best = n;
		}
	}
	return best;
}

// World.cell_center()
Vector2 AntKernel::cell_center(const Layer &p_l, int64_t p_cell) const {
	return Vector2((float)(((double)(p_cell % p_l.width) + 0.5) * (double)p_l.cell_size),
			(float)(((double)(p_cell / p_l.width) + 0.5) * (double)p_l.cell_size));
}

// Where Travel steers an ant at `p_at` going to `p_goal` along a NavGrid
// field (its `dist` array) on layer `p_layer`: two cells down the field
// (NavGrid.downhill()), or straight at the goal once the field says it is
// within `p_direct_within` (NavGrid.distance()) or can't go further down.
Vector2 AntKernel::nav_aim(const PackedInt32Array &p_dist, int64_t p_layer, const Vector2 &p_at, const Vector2 &p_goal,
		double p_direct_within) const {
	ERR_FAIL_INDEX_V(p_layer, (int64_t)layers.size(), p_goal);
	const Layer &l = layers[p_layer];
	const int32_t *dist = p_dist.ptr();
	// World.cell_at()
	int64_t cell = -1;
	if (p_at.x >= 0.0f && p_at.y >= 0.0f) {
		int64_t cx = (int64_t)((double)p_at.x * l.inv_cell);
		int64_t cy = (int64_t)((double)p_at.y * l.inv_cell);
		if (cx < l.width && cy < l.height) {
			cell = cy * l.width + cx;
		}
	}
	double distance = INF_D;
	if (cell >= 0 && dist[cell] < NAV_UNREACHED) {
		distance = (double)((int64_t)dist[cell] * l.cell_size) / (double)NAV_STRAIGHT;
	}
	if (!(distance > p_direct_within) || cell < 0) {
		return p_goal;
	}
	Vector2 aim = p_at;
	int64_t here = dist[cell];
	if (here >= NAV_UNREACHED) {
		int64_t near = best_neighbour(l, dist, cell);
		if (near >= 0) {
			aim = cell_center(l, near);
		}
	} else if (here != 0) {
		int64_t step1 = best_neighbour(l, dist, cell);
		if (step1 >= 0 && dist[step1] < here) {
			int64_t step2 = best_neighbour(l, dist, step1);
			aim = (step2 < 0 || dist[step2] >= dist[step1]) ? cell_center(l, step1) : cell_center(l, step2);
		}
	}
	return aim == p_at ? p_goal : aim;
}

// --- Primitives for GDScript behaviours ---------------------------------------------

void AntKernel::move(int64_t p_i, double p_desired_turn, double p_move_speed, double p_dt) {
	move_impl(p_i, p_desired_turn, p_move_speed, p_dt);
}

void AntKernel::move_to(int64_t p_i, const Vector2 &p_goal, double p_move_speed, double p_dt) {
	move_to_impl(p_i, p_goal, p_move_speed, p_dt);
}

double AntKernel::sense_turn(int64_t p_c, const Vector2 &p_at, double p_heading, int64_t p_colony, int64_t p_layer) const {
	return sense_turn_impl(p_c, p_at, p_heading, colonies[p_colony], layers[p_layer]);
}

double AntKernel::sense_away(int64_t p_c, const Vector2 &p_at, double p_heading, int64_t p_colony, int64_t p_layer) const {
	return sense_away_impl(p_c, p_at, p_heading, colonies[p_colony], layers[p_layer]);
}

void AntKernel::lay(int64_t p_i, int64_t p_c) {
	lay_impl(p_i, p_c);
}

// Ants of colony `p_colony` (below `p_high_water`) carrying something whose
// distance_squared_to(`p_at`) is below p_reach², in index order.
PackedInt32Array AntKernel::carriers_near(const Vector2 &p_at, double p_reach, int64_t p_colony, int64_t p_high_water) const {
	PackedInt32Array out;
	if (ants.alive == nullptr) {
		return out;
	}
	V2 at = v2(p_at);
	double r2 = p_reach * p_reach;
	int64_t n = std::min(p_high_water, ants.capacity);
	for (int64_t c = 0; c < n; c++) {
		if (ants.alive[c] != 0 && ants.carried[c] >= 0 && ants.colony_id[c] == p_colony &&
				distance_squared_to(v2(ants.pos[c]), at) < r2) {
			out.push_back((int32_t)c);
		}
	}
	return out;
}

// --- Grid helpers ----------------------------------------------------------------------

// Cells of `p_mask` (p_nx by p_ny, row-major) equal to `p_value` that have a
// 4-neighbour which isn't (the grid's border counts as not), in row-major
// order: the edge of a shape.
PackedInt32Array AntKernel::mask_edges(const PackedByteArray &p_mask, int64_t p_nx, int64_t p_ny, int64_t p_value) {
	PackedInt32Array out;
	ERR_FAIL_COND_V(p_mask.size() < p_nx * p_ny, out);
	const uint8_t *m = p_mask.ptr();
	auto in = [&](int64_t cx, int64_t cy) -> bool {
		return cx >= 0 && cy >= 0 && cx < p_nx && cy < p_ny && m[cy * p_nx + cx] == p_value;
	};
	std::vector<int32_t> cells;
	for (int64_t cy = 0; cy < p_ny; cy++) {
		for (int64_t cx = 0; cx < p_nx; cx++) {
			if (m[cy * p_nx + cx] == p_value && !(in(cx - 1, cy) && in(cx + 1, cy) && in(cx, cy - 1) && in(cx, cy + 1))) {
				cells.push_back((int32_t)(cy * p_nx + cx));
			}
		}
	}
	out.resize(cells.size());
	if (!cells.empty()) {
		std::copy(cells.begin(), cells.end(), out.ptrw());
	}
	return out;
}

// Index of the point nearest `p_at` (the first of equally near ones), or -1.
int64_t AntKernel::nearest_point(const PackedVector2Array &p_points, const Vector2 &p_at) {
	const Vector2 *pts = p_points.ptr();
	V2 at = v2(p_at);
	int64_t best = -1;
	double best_d = INF_D;
	for (int64_t k = 0; k < p_points.size(); k++) {
		double d = distance_squared_to(v2(pts[k]), at);
		if (d < best_d) {
			best_d = d;
			best = k;
		}
	}
	return best;
}

// --- Profiling -------------------------------------------------------------------------

void AntKernel::set_profiling(bool p_on) {
	profiling = p_on;
}

// Microseconds and ant updates per layer since the last call:
// [usec layer 0, usec layer 1, ..., ticks layer 0, ticks layer 1, ...].
PackedInt64Array AntKernel::take_profile() {
	PackedInt64Array out;
	for (int64_t v : layer_usec) {
		out.push_back(v);
	}
	for (int64_t v : layer_ant_ticks) {
		out.push_back(v);
	}
	std::fill(layer_usec.begin(), layer_usec.end(), 0);
	std::fill(layer_ant_ticks.begin(), layer_ant_ticks.end(), 0);
	return out;
}

void AntKernel::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_rng", "rng"), &AntKernel::set_rng);
	ClassDB::bind_method(D_METHOD("set_dt", "dt"), &AntKernel::set_dt);
	ClassDB::bind_method(D_METHOD("bind_ants", "alive", "pos", "heading", "speed", "colony_id", "caste_id", "state",
								 "carried", "timer", "source_age", "since_obstacle", "scratch_f0", "anim_phase", "layer",
								 "transit_until", "carry_mass"),
			&AntKernel::bind_ants);
	ClassDB::bind_method(D_METHOD("check_ants", "alive", "pos", "heading", "speed", "colony_id", "caste_id", "state",
								 "carried", "timer", "source_age", "since_obstacle", "scratch_f0", "anim_phase", "layer",
								 "transit_until", "carry_mass"),
			&AntKernel::check_ants);
	ClassDB::bind_method(D_METHOD("bind_layer", "layer", "obstacles", "near_blocked", "clutter", "width", "height",
								 "inv_cell", "values", "row_active", "scale", "reinforce", "cap", "cell_size", "p_width", "p_height",
								 "p_inv_cell"),
			&AntKernel::bind_layer);
	ClassDB::bind_method(D_METHOD("check_layer", "layer", "obstacles", "near_blocked", "clutter", "values", "row_active",
								 "scale"),
			&AntKernel::check_layer);
	ClassDB::bind_method(D_METHOD("set_colony", "colony", "values", "turn_rate", "phase_per_unit", "num_states"),
			&AntKernel::set_colony);
	ClassDB::bind_method(D_METHOD("set_state_params", "colony", "params"), &AntKernel::set_state_params);
	ClassDB::bind_method(D_METHOD("set_nest", "colony", "native", "has_entrance", "entrance", "radius", "sense_radius"),
			&AntKernel::set_nest);
	ClassDB::bind_method(D_METHOD("run", "from", "end", "tick_count"), &AntKernel::run);
	ClassDB::bind_method(D_METHOD("move", "i", "desired_turn", "move_speed", "dt"), &AntKernel::move);
	ClassDB::bind_method(D_METHOD("move_to", "i", "goal", "move_speed", "dt"), &AntKernel::move_to);
	ClassDB::bind_method(D_METHOD("sense_turn", "c", "at", "heading", "colony", "layer"), &AntKernel::sense_turn);
	ClassDB::bind_method(D_METHOD("sense_away", "c", "at", "heading", "colony", "layer"), &AntKernel::sense_away);
	ClassDB::bind_method(D_METHOD("lay", "i", "c"), &AntKernel::lay);
	ClassDB::bind_method(D_METHOD("nav_aim", "dist", "layer", "at", "goal", "direct_within"), &AntKernel::nav_aim);
	ClassDB::bind_method(D_METHOD("set_food", "colony", "circles"), &AntKernel::set_food);
	ClassDB::bind_method(D_METHOD("carriers_near", "at", "reach", "colony", "high_water"), &AntKernel::carriers_near);
	ClassDB::bind_static_method("AntKernel", D_METHOD("mask_edges", "mask", "nx", "ny", "value"), &AntKernel::mask_edges);
	ClassDB::bind_static_method("AntKernel", D_METHOD("nearest_point", "points", "at"), &AntKernel::nearest_point);
	ClassDB::bind_method(D_METHOD("set_profiling", "on"), &AntKernel::set_profiling);
	ClassDB::bind_method(D_METHOD("take_profile"), &AntKernel::take_profile);

	BIND_ENUM_CONSTANT(KIND_GDSCRIPT);
	BIND_ENUM_CONSTANT(KIND_EXPLORE);
	BIND_ENUM_CONSTANT(KIND_FOLLOW_TRAIL);
	BIND_ENUM_CONSTANT(KIND_CARRY_HOME);
	BIND_ENUM_CONSTANT(KIND_LINGER);
	BIND_ENUM_CONSTANT(SLOT_KIND);
	BIND_ENUM_CONSTANT(SLOT_FOLLOW);
	BIND_ENUM_CONSTANT(SLOT_LAY);
	BIND_ENUM_CONSTANT(SLOT_AVOID);
	BIND_ENUM_CONSTANT(SLOT_TIMEOUT);
	BIND_ENUM_CONSTANT(SLOT_HOME_BIAS);
	BIND_ENUM_CONSTANT(SLOT_HOME_CONE);
	BIND_ENUM_CONSTANT(SLOT_RADIUS);
	BIND_ENUM_CONSTANT(SLOT_SPEED_FACTOR);
	BIND_ENUM_CONSTANT(SLOT_DURATION);
	BIND_ENUM_CONSTANT(SLOT_COUNT);
}
