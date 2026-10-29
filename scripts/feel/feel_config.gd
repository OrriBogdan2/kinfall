class_name FeelConfig
extends Resource
## Every tunable for the Supervive-style controller, in one data file.
## Units: meters, seconds. Supervive runs on Unreal (1 unit = 1 cm), so wiki
## values are divided by 100.
## Tags: [wiki] = published value, [guide] = from in-game settings guides,
## [est] = starting estimate, tune by eye against gameplay footage.

enum DashInput { WASD_FALLBACK_TO_CURSOR, CURSOR, WASD }

@export_group("Ground")
@export var move_speed := 4.65            ## [wiki] 465 base movespeed (all hunters checked share it)
@export var ground_accel := 70.0          ## [est] ~0.07s to top speed, MOBA-snappy
@export var ground_decel := 90.0          ## [est] near-instant stop
@export var ground_overspeed_decel := 30.0 ## [est] how fast dash/pad momentum bleeds off on ground
@export var sneak_multiplier := 0.6       ## [est] Ctrl sneak
@export var turn_rate := 25.0             ## [est] visual turn smoothing (higher = snappier)
@export var face_aim_hold := 0.45         ## [est] seconds to keep facing cursor after an attack

@export_group("Air")
@export var gravity := 30.0               ## [est] heavy, snappy arcs
@export var jump_velocity := 9.0          ## [est] ~1.35m apex in ~0.3s
@export var max_fall_speed := 40.0
@export var air_accel := 22.0             ## [est]
@export var air_decel := 3.0              ## [est] low: momentum carries in the air
@export var air_overspeed_drag := 3.0     ## [est]
@export var coyote_time := 0.1
@export var jump_buffer := 0.12

@export_group("Glide")
@export var glide_engage_delay := 0.15    ## [est] hold Space this long after leaving ground to open glider
@export var glide_speed := 6.2            ## [est] cruising speed, a bit faster than running
@export var glide_accel := 10.0           ## [est]
@export var glide_decel := 2.0            ## [est] glider drifts when you let go of WASD
@export var glide_overspeed_drag := 1.2   ## [wiki: momentum is preserved] [est] value
@export var glide_gravity := 14.0         ## [est]
@export var glide_fall_speed := 2.2       ## [est] terminal sink rate

@export_group("Glider heat")
@export var heat_max := 100.0
@export var heat_rate := 16.0             ## [est] ~6s of continuous glide to overheat
@export var heat_damaged_multiplier := 2.0 ## [wiki: heat builds faster when hit] [est] value
@export var heat_lift_multiplier := 1.5   ## [guide: feathering during lift saves heat] [est]
@export var heat_dissipate_ground := 50.0 ## [est]
@export var heat_dissipate_air := 15.0    ## [est]
@export var heat_recover_threshold := 40.0 ## [est] overheat clears below this
@export var overheat_dps := 40.0          ## [wiki: continuous damage] [est] value
@export var spike_stun := 0.7             ## [wiki] 0.7s stun when spiked over ground
@export var spike_velocity := 25.0        ## [est] plummet speed

@export_group("Abyss")
@export var abyss_lift_accel := 45.0      ## [wiki: rapid upward impulse] [est] value
@export var abyss_lift_max_speed := 16.0  ## [est]
@export var abyss_brake_distance := 2.5   ## [wiki: decelerates near ground level] [est]
@export var abyss_brake_decel := 60.0     ## [est]
@export var abyss_brake_gain := 2.0       ## [est] target rise speed per meter left
@export var abyss_death_depth := 25.0     ## [est] fall this far below ground level = dead

@export_group("Dash (Shift)")
@export var dash_input := DashInput.WASD_FALLBACK_TO_CURSOR ## [guide] pro default
@export var dash_hold_for_ex := false     ## [footage] some kits: tap = short dash, hold = longer dash + longer cooldown
@export var dash_hold_threshold := 0.12   ## [est] seconds held during the dash to upgrade it
@export var mini_dash_distance := 3.5     ## [est]
@export var mini_dash_duration := 0.16    ## [est]
@export var mini_dash_cooldown := 7.0     ## [wiki] Jin dodge roll
@export var ex_dash_distance := 6.0       ## [wiki: "dashes further"] [est] value
@export var ex_dash_duration := 0.22      ## [est]
@export var ex_dash_cooldown := 12.5      ## [wiki] Jin ex-dash
@export var dash_exit_carry_ground := 0.35 ## [est] fraction of dash speed kept on exit
@export var dash_exit_carry_air := 0.75   ## [wiki: dash into glide keeps momentum] [est]

@export_group("Mantle")
@export var mantle_reach_up := 3.0        ## [wiki: falling players mantle back onto islands] [est]
@export var mantle_probe_distance := 0.8
@export var mantle_duration := 0.25
@export var mantle_max_upward_speed := 2.0 ## only mantle near apex or while falling

@export_group("Jump pad")
@export var jump_pad_dash_carry := 1.15   ## [wiki: dashing into a pad keeps momentum + small boost] [est]

@export_group("Aim")
@export var aim_plane_height := 0.0       ## aim is resolved on a plane at your feet
@export var aim_laser_length := 8.5       ## [wiki] Shiv base attack range 850
