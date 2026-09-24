#pragma once

#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <cstdint>
#include <vector>

namespace godot {

// Native version of the per-ant hot path (see sim/native_ants.gd, which
// drives it, and README "Native ant kernel"). Generic: it knows the core
// behaviours explore, follow_trail, carry_home and linger, and the steering
// primitives every behaviour uses, never a species.
//
// The kernel owns no ant data. Each tick the Simulation hands it its packed
// arrays (bind_ants/bind_layer) and the kernel keeps raw pointers into their
// buffers, reading and writing them in place for the rest of the tick. That
// works because the Simulation makes sure those arrays own their buffers
// (nothing else shares them) and never reallocates them during a tick;
// check_ants/check_layer confirm it at the end of each tick (they return a
// bit mask of the arrays whose buffer moved, 0 if none).
//
// Results are bit for bit those of the GDScript behaviours: the same float32
// and double rounding at every step, the same libm functions, and every
// random number drawn from the Simulation's own RandomNumberGenerator in the
// same order.
class AntKernel : public RefCounted {
	GDCLASS(AntKernel, RefCounted)

public:
	// Native behaviour kinds (0 = the state runs in GDScript).
	enum Kind {
		KIND_GDSCRIPT = 0,
		KIND_EXPLORE = 1,
		KIND_FOLLOW_TRAIL = 2,
		KIND_CARRY_HOME = 3,
		KIND_LINGER = 4,
	};

	// Slots of the per-(caste, state) params array (see set_state_params).
	enum Slot {
		SLOT_KIND,
		SLOT_FOLLOW,
		SLOT_LAY,
		SLOT_AVOID,
		SLOT_TIMEOUT,
		SLOT_HOME_BIAS,
		SLOT_HOME_CONE,
		SLOT_RADIUS,
		SLOT_SPEED_FACTOR,
		SLOT_DURATION,
		SLOT_COUNT,
	};

private:
	struct Ants {
		const uint8_t *alive = nullptr;
		Vector2 *pos = nullptr;
		float *heading = nullptr;
		const float *speed = nullptr;
		const uint8_t *colony_id = nullptr;
		const uint8_t *caste_id = nullptr;
		const uint8_t *state = nullptr;
		const int32_t *carried = nullptr;
		float *timer = nullptr;
		float *source_age = nullptr;
		float *since_obstacle = nullptr;
		const float *scratch_f0 = nullptr;
		float *anim_phase = nullptr;
		const uint8_t *layer = nullptr;
		const int32_t *transit_until = nullptr;
		const double *carry_mass = nullptr;
		int64_t capacity = 0;
	};

	struct Layer {
		bool bound = false;
		// World (obstacle grid).
		const uint8_t *obstacles = nullptr;
		const uint8_t *near_blocked = nullptr;
		const uint8_t *clutter = nullptr;
		int64_t width = 0;
		int64_t height = 0;
		double inv_cell = 0.0;
		// PheromoneField.
		float *values = nullptr;
		uint8_t *row_active = nullptr;
		const float *scale = nullptr;
		const float *reinforce = nullptr;
		const float *cap = nullptr;
		int64_t p_width = 0;
		int64_t p_height = 0;
		int64_t cell_count = 0;
		double p_inv_cell = 0.0;
		int64_t cell_size = 1;
	};

	struct Colony {
		bool set = false;
		double sensor_distance = 0.0;
		double sensor_cos = 0.0;
		double sensor_sin = 0.0;
		double sensor_angle = 0.0;
		double sense_threshold = 0.0;
		double wander_strength = 0.0;
		double avoid_lookahead = 0.0;
		double deposit_base = 0.0;
		double deposit_decay = 0.0;
		double carry_mass_slowdown = 0.0;
		double clutter_slowdown = 0.0;
		double obstacle_memory = 0.0;
		int64_t food_check_interval = 1;
		std::vector<float> turn_rate;
		std::vector<float> phase_per_unit;
		int64_t num_states = 0;
		// SLOT_COUNT doubles per (caste, state), at (caste * num_states + state) * SLOT_COUNT.
		std::vector<double> params;
		// Nest geometry (NestType.has_entrance(), entrance_position(), radius, sense_radius).
		bool nest_native = false;
		bool has_entrance = false;
		Vector2 entrance;
		double radius = 0.0;
		double sense_radius = 0.0;
		// Food sources this colony forages from that were not used up at the
		// start of the tick: x, y, r for each, where FoodSource.sense_bound() is r.
		std::vector<double> food;
	};

	Ants ants;
	std::vector<Layer> layers;
	std::vector<Colony> colonies;
	Ref<RandomNumberGenerator> rng;
	double dt = 0.0;
	bool profiling = false;
	std::vector<int64_t> layer_usec;
	std::vector<int64_t> layer_ant_ticks;

	Colony &colony_slot(int64_t p_colony);

	// Helpers mirroring GDScript/engine code (see ant_kernel.cpp).
	bool world_blocked(const Layer &p_l, const Vector2 &p_at) const;
	double avoid_turn(const Layer &p_l, const Vector2 &p_at, double p_heading, double p_lookahead) const;
	double sense_turn_impl(int64_t p_c, const Vector2 &p_at, double p_heading, const Colony &p_colony, const Layer &p_l) const;
	double sense_away_impl(int64_t p_c, const Vector2 &p_at, double p_heading, const Colony &p_colony, const Layer &p_l) const;
	void move_impl(int64_t p_i, double p_desired_turn, double p_move_speed, double p_dt);
	void move_to_impl(int64_t p_i, const Vector2 &p_goal, double p_move_speed, double p_dt);
	void lay_impl(int64_t p_i, int64_t p_c);
	double nest_turn(int64_t p_i, const Colony &p_colony, const double *p_params, const Layer &p_l) const;
	bool food_near(const Colony &p_colony, const Vector2 &p_at) const;
	int64_t best_neighbour(const Layer &p_l, const int32_t *p_dist, int64_t p_cell) const;
	Vector2 cell_center(const Layer &p_l, int64_t p_cell) const;
	bool tick_ant(int64_t p_i, int64_t p_tick_count);

protected:
	static void _bind_methods();

public:
	void set_rng(const Ref<RandomNumberGenerator> &p_rng);
	void set_dt(double p_dt);
	void bind_ants(const PackedByteArray &p_alive, const PackedVector2Array &p_pos, const PackedFloat32Array &p_heading,
			const PackedFloat32Array &p_speed, const PackedByteArray &p_colony_id, const PackedByteArray &p_caste_id,
			const PackedByteArray &p_state, const PackedInt32Array &p_carried, const PackedFloat32Array &p_timer,
			const PackedFloat32Array &p_source_age, const PackedFloat32Array &p_since_obstacle,
			const PackedFloat32Array &p_scratch_f0, const PackedFloat32Array &p_anim_phase, const PackedByteArray &p_layer,
			const PackedInt32Array &p_transit_until, const PackedFloat64Array &p_carry_mass);
	int64_t check_ants(const PackedByteArray &p_alive, const PackedVector2Array &p_pos, const PackedFloat32Array &p_heading,
			const PackedFloat32Array &p_speed, const PackedByteArray &p_colony_id, const PackedByteArray &p_caste_id,
			const PackedByteArray &p_state, const PackedInt32Array &p_carried, const PackedFloat32Array &p_timer,
			const PackedFloat32Array &p_source_age, const PackedFloat32Array &p_since_obstacle,
			const PackedFloat32Array &p_scratch_f0, const PackedFloat32Array &p_anim_phase, const PackedByteArray &p_layer,
			const PackedInt32Array &p_transit_until, const PackedFloat64Array &p_carry_mass) const;
	void bind_layer(int64_t p_layer, const PackedByteArray &p_obstacles, const PackedByteArray &p_near_blocked,
			const PackedByteArray &p_clutter, int64_t p_width, int64_t p_height, double p_inv_cell,
			const PackedFloat32Array &p_values, const PackedByteArray &p_row_active, const PackedFloat32Array &p_scale,
			const PackedFloat32Array &p_reinforce, const PackedFloat32Array &p_cap, int64_t p_cell_size, int64_t p_p_width, int64_t p_p_height,
			double p_p_inv_cell);
	int64_t check_layer(int64_t p_layer, const PackedByteArray &p_obstacles, const PackedByteArray &p_near_blocked,
			const PackedByteArray &p_clutter, const PackedFloat32Array &p_values, const PackedByteArray &p_row_active,
			const PackedFloat32Array &p_scale) const;
	void set_colony(int64_t p_colony, const PackedFloat64Array &p_values, const PackedFloat32Array &p_turn_rate,
			const PackedFloat32Array &p_phase_per_unit, int64_t p_num_states);
	void set_state_params(int64_t p_colony, const PackedFloat64Array &p_params);
	void set_nest(int64_t p_colony, bool p_native, bool p_has_entrance, const Vector2 &p_entrance, double p_radius,
			double p_sense_radius);

	int64_t run(int64_t p_from, int64_t p_end, int64_t p_tick_count);

	void move(int64_t p_i, double p_desired_turn, double p_move_speed, double p_dt);
	void move_to(int64_t p_i, const Vector2 &p_goal, double p_move_speed, double p_dt);
	double sense_turn(int64_t p_c, const Vector2 &p_at, double p_heading, int64_t p_colony, int64_t p_layer) const;
	double sense_away(int64_t p_c, const Vector2 &p_at, double p_heading, int64_t p_colony, int64_t p_layer) const;
	Vector2 nav_aim(const PackedInt32Array &p_dist, int64_t p_layer, const Vector2 &p_at, const Vector2 &p_goal,
			double p_direct_within) const;
	void set_food(int64_t p_colony, const PackedFloat64Array &p_circles);
	PackedInt32Array carriers_near(const Vector2 &p_at, double p_reach, int64_t p_colony, int64_t p_high_water) const;
	void lay(int64_t p_i, int64_t p_c);

	// Grid helpers (static, no Simulation needed).
	static PackedInt32Array mask_edges(const PackedByteArray &p_mask, int64_t p_nx, int64_t p_ny, int64_t p_value);
	static int64_t nearest_point(const PackedVector2Array &p_points, const Vector2 &p_at);

	void set_profiling(bool p_on);
	PackedInt64Array take_profile();
};

} // namespace godot

VARIANT_ENUM_CAST(AntKernel::Kind);
VARIANT_ENUM_CAST(AntKernel::Slot);
