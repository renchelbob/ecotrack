# 02 — Domain Mathematics, Motion Classifier & Antifraud Algorithms

> **Target Audience**: Developer 1 (Backend Domain Engine) & Developer 2 (Flutter Client Preview Engine)
> **Governing Contracts**: `contracts/schema.sql`, `contracts/openapi.yaml`, `contracts/error_catalog.json`
> **Implementation Boundary**: Pure deterministic functions in `backend/app/domain/` (verified symbolically via `icontract` + `CrossHair`/Z3) and mirrored for offline preview in `mobile/lib/features/*/domain/`.

---

## 1. Master Constants Table

All arithmetic on distances and emission rates MUST use exact decimal fixed-point math (`decimal.Decimal` with `ROUND_HALF_UP` in Python; scaled integer arithmetic or `.toStringAsFixed()` rounding in Dart) before converting final CO₂ masses and Eco-Points to exact integers (`int`). Floating-point drift in ledger or CO₂ totals is strictly prohibited.

### 1.1 Core Step, Confidence & Economy Constants

| Constant Identifier | Exact Value | Unit | Contract Reference & Purpose |
| :--- | :--- | :--- | :--- |
| `DEFAULT_STRIDE_LENGTH_CM` | `74` | `cm / step` | Default `users.stride_length_cm` (`0.74 m/step`) |
| `MIN_STRIDE_LENGTH_CM` | `40` | `cm / step` | `CHECK (stride_length_cm BETWEEN 40 AND 120)` |
| `MAX_STRIDE_LENGTH_CM` | `120` | `cm / step` | `CHECK (stride_length_cm BETWEEN 40 AND 120)` |
| `ANNOTATED_CONFIDENCE_FACTOR` | `Decimal("1.00")` | dimensionless | Applied to GPS-verified `route_segment_allocations` |
| `DEFAULT_AUTO_CONFIDENCE_FACTOR` | `Decimal("0.70")` | dimensionless | Applied to unallocated step distance (`is_auto_calculated = TRUE`) |
| `DEFAULT_BUS_SUBSTITUTION_RATIO` | `Decimal("0.80")` | dimensionless | Assumes 80% of unallocated steps replace a city bus trip |
| `DEFAULT_BUS_CO2_G_PER_KM` | `Decimal("82.00")` | `g CO₂ / km` | Seeded `transport_emission_catalog` rate for `bus` |
| `DEFAULT_BUS_CO2_G_PER_M` | `Decimal("0.08200")` | `g CO₂ / m` | `82.00 / 1000.0` |
| `EFFECTIVE_AUTO_CO2_G_PER_M` | `Decimal("0.04592")` | `g CO₂ / m` | Exact product `0.80 * 0.08200 * 0.70` |
| `STEPS_PER_ECO_POINT` | `100` | `steps / ★` | `1 ★` awarded per `100` validated daily steps (`validated_steps // 100`) |
| `STREAK_MIN_DAILY_STEPS` | `1000` | `steps` | Minimum `validated_steps` required to keep/advance daily streak if CO₂ goal not yet met |
| `SHARED_FOREST_COMPLETION_REWARD` | `50` | `★` | Bonus points awarded per participant when weekly Shared Forest reaches 100% |
| `RSO_CONFIRM_REPORT_REWARD` | `15` | `★` | Points awarded for a valid `point_reports` submission within 2,000 m |
| `EDIT_WINDOW_MAX_AGE_DAYS` | `1` | `days` | Segment annotations allowed only for `today` (`0`) and `yesterday` (`1`) |

### 1.2 Transport Emission Catalog Constants (`transport_emission_catalog`)

| `mode_code` | Russian Label | `co2_grams_per_km` | `co2_grams_per_meter` | Slot Behavior |
| :--- | :--- | :--- | :--- | :--- |
| `bus` | Автобус / электробус | `82.00` | `0.08200` | Fixed catalog rate |
| `metro` | Метро / МЦК / МЦД | `28.00` | `0.02800` | Fixed catalog rate |
| `tram` | Трамвай | `35.00` | `0.03500` | Fixed catalog rate |
| `personal_car` | Мой автомобиль | `192.00` (fallback) | `0.19200` (fallback) | Overridden dynamically by `user_vehicles.computed_co2_g_per_meter` if configured |
| `car_compact` | Авто (компакт B-класс) | `145.00` | `0.14500` | Fixed preset (Average Car option 1) |
| `car_sedan` | Авто (седан C/D-класс) | `192.00` | `0.19200` | Fixed preset (Average Car default option 2) |
| `car_suv` | Авто (кроссовер / SUV) | `255.00` | `0.25500` | Fixed preset (Average Car option 3) |
| `car_ev` | Электромобиль (РФ сеть) | `58.00` | `0.05800` | Fixed preset (Average Car option 4) |

### 1.3 Fuel Combustion & Russian Grid Factors (`fuel_type`)

| `fuel_type` ENUM | Unit of `consumption_per_100km` | `fuel_emission_factor_g_per_unit` | Physical Basis |
| :--- | :--- | :--- | :--- |
| `petrol_92` | Liters / 100 km | `2310.00` `g CO₂ / L` | Motor gasoline RON 92 oxidation |
| `petrol_95` | Liters / 100 km | `2330.00` `g CO₂ / L` | Motor gasoline RON 95 oxidation |
| `petrol_98` | Liters / 100 km | `2350.00` `g CO₂ / L` | Motor gasoline RON 98/100 oxidation |
| `diesel` | Liters / 100 km | `2680.00` `g CO₂ / L` | EN 590 / GOST R diesel oxidation |
| `lpg` | Liters / 100 km | `1660.00` `g CO₂ / L` | Liquefied petroleum gas (propane-butane) |
| `cng` | $\text{m}^3$ / 100 km | `1960.00` `g CO₂ / m³` | Compressed natural gas (methane) |
| `hybrid` | Liters / 100 km | `2310.00` `g CO₂ / L` | Petrol hybrid cycle |
| `electric` | kWh / 100 km | `340.00` `g CO₂ / kWh` | Unified Energy System of Russia (ЕЭС РФ) average grid intensity |

### 1.4 Antifraud & Sensor Threshold Constants

| Constant Identifier | Exact Value | Unit | Enforcement Action |
| :--- | :--- | :--- | :--- |
| `MAX_DAILY_VALIDATED_STEPS` | `100000` | `steps / day` | `ANTIFRAUD_DAILY_STEP_CAP_EXCEEDED` if `raw_sensor_steps > 100000` |
| `MAX_SUSTAINED_CADENCE_SPS` | `Decimal("4.50")` | `steps / sec` | `ANTIFRAUD_STEP_SPIKE_DETECTED` when $\Delta t \ge 10\text{ s}$ and $\Delta s / \Delta t > 4.50$ |
| `MAX_GPS_ACCURACY_METERS` | `Decimal("65.0")` | `meters` | Points with `accuracy_m > 65.0` classify as `unknown` (excluded from polyline length) |
| `TELEPORT_SPEED_MPS` | `Decimal("50.00")` | `m / sec` | `ANTIFRAUD_SPEED_SPOOFING_DETECTED` if $v_i > 50.0\text{ m/s}$ ($180\text{ km/h}$) |
| `VEHICLE_SPEED_MPS` | `Decimal("6.50")` | `m / sec` | Segments with $v_i > 6.50\text{ m/s}$ ($23.4\text{ km/h}$) classify as `vehicle_suspected` |
| `VEHICLE_LOW_CADENCE_SPEED_MPS` | `Decimal("2.50")` | `m / sec` | Segments with $v_i \ge 2.50\text{ m/s}$ AND effective stride $l_i > 2.20\text{ m/step}$ classify as `vehicle_suspected` |
| `INDOOR_PACING_MAX_DIST_M` | `Decimal("6.00")` | `meters` | When $\Delta s_i \ge 10$ steps and $d_i < 6.00\text{ m}$, classify as `indoor_pacing` |
| `MIN_WALK_STRIDE_M` | `Decimal("0.30")` | `m / step` | Minimum effective outdoor stride $l_i = d_i / \Delta s_i$ for `walking` |
| `MAX_WALK_STRIDE_M` | `Decimal("2.20")` | `m / step` | Maximum effective outdoor stride (including brisk walk/jog) for `walking` |
| `RSO_REPORT_MAX_DISTANCE_M` | `Decimal("2000.00")` | `meters` | `REPORT_USER_TOO_FAR_FROM_POINT` if user is $> 2000\text{ m}$ from `waste_points.geom` |
| `RSO_REPORT_COOLDOWN_HOURS` | `12` | `hours` | `DUPLICATE_POINT_REPORT_COOLDOWN` per `(user_id, waste_point_id)` |

---

## 2. Personal Vehicle CO₂ Formula

When a user configures their personal car in `user_vehicles` (`PUT /api/v1/users/me/vehicle`), the backend resolves `fuel_emission_factor_g_per_unit` ($F_{\text{fuel}}$) from Table 1.3 and computes:

$$E_{\text{km}} = \text{ROUND}\left(\frac{C_{100} \times F_{\text{fuel}}}{100}, 2\right) \quad [\text{g CO}_2 / \text{km}]$$

$$E_{\text{m}} = \text{ROUND}\left(\frac{C_{100} \times F_{\text{fuel}}}{100000}, 5\right) \quad [\text{g CO}_2 / \text{m}]$$

where $C_{100} \in (0.00, 50.00]$ is `consumption_per_100km`.

### 2.1 Fallback Resolution Rule for `personal_car`
When evaluating a route segment with `replaced_transport_mode = 'personal_car'`:
1. Query `SELECT computed_co2_g_per_meter FROM user_vehicles WHERE user_id = $1`.
2. If a row exists, set `applied_co2_g_per_meter` $= E_{\text{m}}$.
3. If no row exists, fallback to `transport_emission_catalog` where `mode_code = 'personal_car'` (`0.19200 g/m`, `192.00 g/km`).

### 2.2 Worked Vehicle Examples
- **Example A (Petrol 95 Sedan, $C_{100} = 8.5\text{ L/100km}$)**:
  - $F_{\text{fuel}} = 2330.00\text{ g/L}$
  - $E_{\text{km}} = \text{ROUND}((8.5 \times 2330.00) / 100, 2) = 198.05\text{ g CO}_2\text{/km}$
  - $E_{\text{m}} = \text{ROUND}((8.5 \times 2330.00) / 100000, 5) = 0.19805\text{ g CO}_2\text{/m}$
- **Example B (Diesel SUV, $C_{100} = 9.2\text{ L/100km}$)**:
  - $F_{\text{fuel}} = 2680.00\text{ g/L}$
  - $E_{\text{km}} = \text{ROUND}((9.2 \times 2680.00) / 100, 2) = 246.56\text{ g CO}_2\text{/km}$
  - $E_{\text{m}} = 0.24656\text{ g CO}_2\text{/m}$
- **Example C (Electric Vehicle on RF Grid, $C_{100} = 17.5\text{ kWh/100km}$)**:
  - $F_{\text{fuel}} = 340.00\text{ g/kWh}$
  - $E_{\text{km}} = \text{ROUND}((17.5 \times 340.00) / 100, 2) = 59.50\text{ g CO}_2\text{/km}$
  - $E_{\text{m}} = 0.05950\text{ g CO}_2\text{/m}$

---

## 3. Interval GPS + `cumulative_steps` Motion Classifier & Antifraud

### 3.1 Interval Kinematics & Reboot-Safe Step Delta
Given an ordered sequence of track points $P_0, P_1, \dots, P_n$ for a single `activity_date` (`seq_no` $0 < 1 < \dots < n$ and strictly increasing `recorded_at` timestamps $t_0 < t_1 < \dots < t_n$):

For the initial point $P_0$ (`seq_no == 0`):
- $\Delta s_0 = 0$, $\Delta d_0 = 0.00$, `motion_class = 'stationary'`.

For every subsequent interval $i \ge 1$ from $P_{i-1}$ to $P_i$:
1. **Elapsed Time ($\Delta t_i$)**:
   $$\Delta t_i = \max\left(1.0, \text{epoch}(t_i) - \text{epoch}(t_{i-1})\right) \quad [\text{seconds}]$$
2. **Geodesic Distance ($d_i$)**:
   Computed in PostGIS via `ST_Distance(P_{i-1}.geom::geography, P_i.geom::geography)` (and on the Flutter client via `latlong2.Distance().as(LengthUnit.Meter, pPrev, pCurr)`), rounded to `2` decimal places (`delta_distance_m`).
3. **Reboot-Safe Step Delta ($\Delta s_i$)**:
   Hardware `TYPE_STEP_COUNTER` sensors reset to `0` when the smartphone reboots. Therefore:
   $$\Delta s_i = \begin{cases} S_i - S_{i-1} & \text{if } S_i \ge S_{i-1} \\ S_i & \text{if } S_i < S_{i-1} \text{ (hardware reboot counter reset)} \end{cases}$$
4. **Derived Kinematic Metrics**:
   - Interval speed: $v_i = \frac{d_i}{\Delta t_i}$ $[\text{m/s}]$
   - Step cadence: $c_i = \frac{\Delta s_i}{\Delta t_i}$ $[\text{steps/s}]$
   - Effective stride length: $l_i = \begin{cases} \frac{d_i}{\Delta s_i} & \text{if } \Delta s_i > 0 \\ \infty & \text{if } \Delta s_i = 0 \end{cases}$ $[\text{m/step}]$

### 3.2 Deterministic Motion Classification Decision Table (`track_point_motion_class`)
Each point $P_i$ ($i \ge 1$) is evaluated top-to-bottom; the **first matching rule** determines its `motion_class` (or raises an antifraud error):

| Priority | Condition / Predicate | Assigned `motion_class` / Action | Physical Interpretation |
| :--- | :--- | :--- | :--- |
| **Rule 1** | `accuracy_m > 65.0` | `'unknown'` | Poor GPS fix (urban canyon / indoor drift); excluded from walking polyline distance. |
| **Rule 2** | $v_i > 50.00\text{ m/s}$ AND $d_i > 250.0\text{ m}$ | Raise `ANTIFRAUD_SPEED_SPOOFING_DETECTED` | Impossible ground speed ($>180\text{ km/h}$) or mock-location teleportation jump. |
| **Rule 3** | $\Delta t_i \ge 10.0\text{ s}$ AND $c_i > 4.50\text{ steps/s}$ | Raise `ANTIFRAUD_STEP_SPIKE_DETECTED` | Mechanical phone shaker / sensor spoofing ($>270\text{ steps/min}$ sustained). |
| **Rule 4** | $v_i > 6.50\text{ m/s}$ OR ($d_i \ge 25.0\text{ m}$ AND $\Delta s_i < 5$) OR ($v_i \ge 2.50\text{ m/s}$ AND $l_i > 2.20\text{ m}$) | `'vehicle_suspected'` | User is riding in a car, bus, tram, or bicycle ($d_i \gg 0$ while $\Delta s_i \approx 0$). |
| **Rule 5** | $\Delta s_i \ge 10$ AND $d_i < 6.00\text{ m}$ | `'indoor_pacing'` | Walking inside an apartment, office, or gym treadmill ($\Delta s_i > 0, d_i \approx 0$). |
| **Rule 6** | $\Delta s_i < 4$ AND $d_i < 6.00\text{ m}$ | `'stationary'` | Standing still or sitting with minor GPS jitter. |
| **Rule 7** | $\Delta s_i \ge 4$ AND $d_i \ge 6.00\text{ m}$ AND $0.30\text{ m} \le l_i \le 2.20\text{ m}$ AND $v_i \le 6.50\text{ m/s}$ | `'walking'` | Verified outdoor pedestrian movement eligible for route segment transport replacement. |
| **Rule 8** | Fallback (all other combinations, e.g., short GPS drift with few steps) | `'unknown'` | Unclassified transition point; not eligible for `1.0` transport replacement. |

### 3.3 Total GPS Walking Distance Aggregation
Only intervals where $P_i.\text{motion\_class} == \text{'walking'}$ contribute to `gps_daily_tracks.total_gps_walking_distance_m`:
$$D_{\text{GPS\_walk}} = \sum_{\substack{i=1 \\ P_i.\text{motion\_class} = \text{'walking'}}}^{n} d_i$$

### 3.4 Daily Step-Count Antifraud Validation (`syncDailyStepsSummary`)
When `PUT /api/v1/activity/steps/daily` is called with `raw_sensor_steps`:
1. **Future Date Gate**: If `activity_date > user_local_today`, reject immediately with `400 ACTIVITY_DATE_IN_FUTURE`.
2. **Hard Daily Ceiling**: If `raw_sensor_steps > 100000`, reject with `422 ANTIFRAUD_DAILY_STEP_CAP_EXCEEDED` and record `antifraud_flagged = TRUE, antifraud_reason = 'DAILY_CAP_100K_EXCEEDED'`.
3. **Rate-of-Change Cadence Gate**: If a previous sync exists for `activity_date` at timestamp $t_{\text{prev}}$ with steps $S_{\text{prev}}$, and $\Delta t = \text{epoch}(\text{now}) - \text{epoch}(t_{\text{prev}}) \ge 30\text{ s}$ while $(S_{\text{raw}} - S_{\text{prev}}) / \Delta t > 4.50\text{ steps/s}$ and $(S_{\text{raw}} - S_{\text{prev}}) > 500$, reject with `422 ANTIFRAUD_STEP_SPIKE_DETECTED`.
4. **Monotonicity Preservation**: Because out-of-order offline outbox packets can arrive after a newer sync, `validated_steps` is updated monotonically:
   $$S_{\text{valid}} = \max\left(S_{\text{existing\_validated}}, S_{\text{raw}}\right)$$

---

## 4. Hybrid CO₂ Economy, Points & Streak Algorithm

### 4.1 Hybrid CO₂ Calculation in Meters
For any `activity_date`, let:
- $S_{\text{valid}}$ = `validated_steps` ($\text{int} \in [0, 100000]$)
- $L_{\text{cm}}$ = `stride_length_cm` ($\text{int} \in [40, 120]$)
- $\mathcal{A} = \{a_1, a_2, \dots, a_m\}$ = set of validated `route_segment_allocations` for `activity_date`.

**Step 1 — Total Step Distance ($D_{\text{steps}}$)**:
$$D_{\text{steps}} = \text{ROUND}\left(\frac{S_{\text{valid}} \times L_{\text{cm}}}{100.0}, 2\right) \quad [\text{meters}]$$

**Step 2 — Allocated GPS Segments ($D_{\text{alloc}}, C_{\text{alloc}}$)**:
For each allocation $a_k \in \mathcal{A}$ covering track points `start_seq_no` $\dots$ `end_seq_no`:
- Segment distance $D_k = \sum_{j = \text{start\_seq\_no} + 1}^{\text{end\_seq\_no}} d_j$ $[\text{meters}]$
- Segment steps $S_k = \sum_{j = \text{start\_seq\_no} + 1}^{\text{end\_seq\_no}} \Delta s_j$ $[\text{steps}]$
- Segment CO₂ saved (with `confidence_factor = 1.00`, `is_auto_calculated = FALSE`):
  $$C_k = \text{ROUND\_HALF\_UP}\left(D_k \times K_{\text{mode}, k} \times 1.00\right) \quad [\text{grams, int}]$$
  where $K_{\text{mode}, k}$ is `applied_co2_g_per_meter` from Table 1.2 (or Section 2.1 for `personal_car`).
- Sum across all allocations:
  $$D_{\text{alloc}} = \sum_{k=1}^{m} D_k, \qquad C_{\text{alloc}} = \sum_{k=1}^{m} C_k$$

**Step 3 — Unallocated Step Distance ($D_{\text{unalloc}}$)**:
$$D_{\text{unalloc}} = \max\left(0.00, D_{\text{steps}} - D_{\text{alloc}}\right) \quad [\text{meters}]$$
*(Note: If the user walked slightly further on outdoor GPS than estimated by average stride length $D_{\text{steps}}$, $\max(0.00, \dots)$ clamps $D_{\text{unalloc}}$ to $0.00\text{ m}$ without penalizing $C_{\text{alloc}}$).*

**Step 4 — Default Auto-Calculated CO₂ on Unallocated Distance ($C_{\text{auto}}$)**:
$$C_{\text{auto}} = \text{ROUND\_HALF\_UP}\left(D_{\text{unalloc}} \times 0.80 \times 0.08200 \times 0.70\right) \quad [\text{grams, int}]$$

**Step 5 — Total Daily CO₂ & Summary `is_auto_calculated` Flag**:
$$C_{\text{total}} = C_{\text{alloc}} + C_{\text{auto}} \quad [\text{grams, int}]$$
$$\text{summary.is\_auto\_calculated} = \begin{cases} \text{TRUE} & \text{if } m = 0 \\ \text{FALSE} & \text{if } m \ge 1 \end{cases}$$

### 4.2 Strict Segment Allocation Validation Rules
When `PUT /api/v1/activity/daily/{activity_date}/allocations` is called with list $\mathcal{A}$:
1. **48-Hour Edit Window**: Compute $\Delta_{\text{days}} = (\text{user\_local\_today} - \text{activity\_date}).\text{days}$. If $\Delta_{\text{days}} \notin \{0, 1\}$, raise `400 EDIT_WINDOW_EXPIRED`.
2. **Sequence Existence**: Every `start_seq_no` and `end_seq_no` must exist in `gps_track_points` for `(user_id, activity_date)` with `end_seq_no > start_seq_no`; otherwise raise `422 SEGMENT_SEQ_OUT_OF_BOUNDS`.
3. **Non-Overlapping Intervals**: Sort $\mathcal{A}$ by `start_seq_no`. If for any adjacent pair $a_k.\text{end\_seq\_no} > a_{k+1}.\text{start\_seq\_no}$ (touching at endpoints `end_seq_no == next.start_seq_no` IS allowed), raise `409 SEGMENT_OVERLAP_CONFLICT`.
4. **No Vehicle Segments**: If any point $P_j$ with $\text{start\_seq\_no} < j \le \text{end\_seq\_no}$ has `motion_class == 'vehicle_suspected'`, raise `422 SEGMENT_CONTAINS_VEHICLE_MOTION`.

### 4.3 Eco-Points & Ledger Delta Calculation
1. **Eco-Points from Daily Steps**:
   Eco-Points are awarded for **all validated daily steps** at `1 ★` per `100` steps:
   $$P_{\text{target}} = \left\lfloor \frac{S_{\text{valid}}}{100} \right\rfloor, \qquad \Delta P_{\text{steps}} = P_{\text{target}} - P_{\text{already\_awarded\_for\_day}}$$
   If $\Delta P_{\text{steps}} > 0$, insert a row into `point_ledger` with `operation_type = 'daily_steps_reward'`, `points_delta = \Delta P_{\text{steps}}`, `co2_delta_grams = \Delta C_{\text{total}}`, and update `daily_step_summaries.points_awarded_for_day = P_{\text{target}}`.
2. **CO₂ Delta on Route Segment Re-Annotation (Today or Yesterday)**:
   When a user annotates or deletes a route segment on Today or Yesterday and $\Delta P_{\text{steps}} == 0$ while $\Delta C_{\text{total}} = C_{\text{total}}^{\text{new}} - C_{\text{total}}^{\text{old}} \ne 0$:
   - Update `daily_step_summaries` (`allocated_gps_distance_m`, `allocated_co2_saved_grams`, `auto_default_co2_saved_grams`, `is_auto_calculated`).
   - Update `users.lifetime_co2_saved_grams = GREATEST(0, lifetime_co2_saved_grams + \Delta C_{\text{total}})` and `shared_forest_contributions.contributed_co2_grams = GREATEST(0, contributed_co2_grams + \Delta C_{\text{total}})`.

### 4.4 Worked Numerical Example (Hybrid CO₂ & Yesterday Delta)
Suppose a user with `stride_length_cm = 74` and a configured Petrol 95 car (`0.19805 g/m`) walks `6,000` validated steps today:
1. **Initial Auto-Calculation (before GPS annotation)**:
   - $D_{\text{steps}} = \text{ROUND}(6000 \times 74 / 100.0, 2) = 4440.00\text{ m}$
   - $D_{\text{alloc}} = 0.00\text{ m}$, $C_{\text{alloc}} = 0\text{ g}$
   - $D_{\text{unalloc}} = 4440.00\text{ m}$
   - $C_{\text{auto}} = \text{ROUND\_HALF\_UP}(4440.00 \times 0.80 \times 0.08200 \times 0.70) = \text{ROUND\_HALF\_UP}(203.8848) = 204\text{ g CO}_2$
   - $C_{\text{total}} = 204\text{ g CO}_2$, `points_awarded_for_day` $= \lfloor 6000 / 100 \rfloor = 60\text{ ★}$, `is_auto_calculated = TRUE`.
2. **User Annotates a `1,500.00 m` Outdoor Walk as Replacing `'personal_car'` (`0.19805 g/m`)**:
   - $D_{\text{alloc}} = 1500.00\text{ m}$
   - $C_{\text{alloc}} = \text{ROUND\_HALF\_UP}(1500.00 \times 0.19805 \times 1.00) = \text{ROUND\_HALF\_UP}(297.075) = 297\text{ g CO}_2$
   - Remaining unallocated distance (e.g., indoor steps):
     $$D_{\text{unalloc}} = 4440.00 - 1500.00 = 2940.00\text{ m}$$
   - Auto-calculated CO₂ on remaining `2,940.00 m`:
     $$C_{\text{auto}} = \text{ROUND\_HALF\_UP}(2940.00 \times 0.04592) = \text{ROUND\_HALF\_UP}(135.0048) = 135\text{ g CO}_2$$
   - New total CO₂ saved:
     $$C_{\text{total}}^{\text{new}} = 297 + 135 = 432\text{ g CO}_2$$
   - Net CO₂ delta applied: $\Delta C = 432 - 204 = +228\text{ g CO}_2$, `is_auto_calculated = FALSE`.

### 4.5 Streak & Streak Freeze State Machine
A day $d$ counts as **active** for streak purposes if `validated_steps >= 1000` OR `total_co2_saved_grams >= daily_co2_goal_grams`.
When a qualifying sync occurs on local date $d$:
- **Case 1 (`last_active_local_date == d`)**: Streak already incremented today; no change.
- **Case 2 (`last_active_local_date == NULL`)**: First active day ever -> `current_streak_days = 1`, `longest_streak_days = GREATEST(longest_streak_days, 1)`, `last_active_local_date = d`.
- **Case 3 (`last_active_local_date == d - 1 day`)**: Consecutive day -> `current_streak_days += 1`, `longest_streak_days = GREATEST(longest_streak_days, current_streak_days)`, `last_active_local_date = d`.
- **Case 4 (`last_active_local_date == d - 2 days` AND `streak_freeze_count >= 1`)**: Missed exactly 1 day (`yesterday`) with an available Streak Freeze -> auto-consume `streak_freeze_count -= 1`, increment `current_streak_days += 1`, `longest_streak_days = GREATEST(longest_streak_days, current_streak_days)`, `last_active_local_date = d`.
- **Case 5 (`last_active_local_date <= d - 2 days` with `streak_freeze_count == 0`, OR gap $\ge 3$ days)**: Streak resets -> `current_streak_days = 1`, `last_active_local_date = d`.

#### Streak Ratchet Invariant (48-Hour Retroactive Edit Rule):
- **Monotonic Ratchet**: `current_streak_days` and `longest_streak_days` are monotonically non-decreasing within local date $d$. If a user edits/removes an allocation for yesterday ($d-1$) such that yesterday's $\text{CO}_2$ drops below threshold, an already-earned streak MUST NOT be rolled back.
- **Retroactive Recovery**: If yesterday ($d-1$) was previously inactive, and today's edit for yesterday causes it to meet `validated_steps >= 1000` or $\text{CO}_2 \ge \text{goal}$:
  - If a streak freeze was auto-consumed for yesterday, `streak_freeze_count` is refunded ($+1$).
  - If the streak had reset today, `current_streak_days` is retroactively reconnected to the pre-reset streak and incremented.

---

## 5. Ecological Equivalents & Cooperative "Shared Forest" Math

### 5.1 Deterministic Eco-Equivalents Formulas (`EcoEquivalentsMetrics`)
Given `total_co2_saved_grams` ($G \ge 0$, integer):

| Metric Field | Exact Formula from $G$ (grams CO₂) | Rounding / Type | Physical Constant Reference |
| :--- | :--- | :--- | :--- |
| `trees_planted_equivalent` | $\text{ROUND}(G / 20000.0, 2)$ | `float` (2 decimals) | 1 mature tree absorbs $20,000\text{ g}$ ($20\text{ kg}$) $\text{CO}_2\text{/year}$ |
| `forest_area_sqm` (drilldown) | $\text{ROUND}(G / 500.0, 1)$ | `float` (1 decimal) | $1\text{ m}^2$ of mixed temperate forest absorbs $500\text{ g CO}_2\text{/year}$ |
| `car_km_avoided` | $\text{ROUND}(G / 192.0, 1)$ | `float` (1 decimal) | Average C/D-class sedan emits $192\text{ g CO}_2\text{/km}$ |
| `gasoline_liters_saved` (drilldown) | $\text{ROUND}(G / 2330.0, 2)$ | `float` (2 decimals) | $1\text{ L}$ of RON 95 petrol emits $2,330\text{ g CO}_2$ |
| `fuel_rub_saved` (drilldown) | $\text{ROUND}((G / 2330.0) \times 62.50, 0)$ | `int` (`₽`) | Reference RON 95 retail price $62.50\text{ ₽/L}$ |
| `smartphone_charges_equivalent` | $\lfloor G / 8.22 \rfloor$ | `int` | 1 full smartphone charge ($15\text{ Wh}$) $\approx 8.22\text{ g CO}_2$ |
| `plastic_bottles_recycled_equivalent` | $\lfloor G / 82.80 \rfloor$ | `int` | Recycling one $0.5\text{ L}$ PET bottle saves $82.8\text{ g CO}_2$ |
| `led_bulb_hours_equivalent` | $\lfloor G / 3.40 \rfloor$ | `int` | $10\text{ W}$ LED bulb on RF grid ($340\text{ g/kWh}$) emits $3.40\text{ g CO}_2\text{/h}$ |
| `clean_air_cubic_meters` (drilldown) | $\text{ROUND}(G / 1.96, 1)$ | `float` (1 decimal) | Volume of pure $\text{CO}_2$ gas displaced at STP ($\rho = 1.96\text{ g/L}$ scaled to ambient threshold) |

### 5.2 Cooperative Weekly "Shared Forest" Aggregation
For each ISO week (`iso_year`, `iso_week`):
- `shared_forest_challenges.target_co2_saved_grams` defaults to `50,000 g` (`50 kg CO₂`, equivalent to `2.5` mature trees).
- Whenever a user's daily CO₂ total for a date within `[week_start_date, week_end_date]` changes by $\Delta C$, `shared_forest_contributions.contributed_co2_grams` and `shared_forest_challenges.current_co2_saved_grams` are atomically incremented by $\Delta C$.
- Additionally, purchasing `VIRT-FOREST-DONATION` in the Shop immediately adds `+2,000 g CO₂` to the user's weekly contribution and the challenge total.
- When `current_co2_saved_grams >= target_co2_saved_grams` and `is_completed == FALSE`:
  - Set `is_completed = TRUE`.
  - For every contributing user in `shared_forest_contributions` for that `challenge_id`, insert `+50 ★` into `point_ledger` (`operation_type = 'challenge_reward'`, deterministic UUIDv5/v7 idempotency key derived from `(challenge_id, user_id)`).

---

## 6. Mascot Mood & Badge Evaluation Rules

### 6.1 Mascot Mood State Machine (`MascotMoodState`)
Let $R = \frac{\text{today\_total\_co2\_saved\_grams}}{\text{daily\_co2\_goal\_grams}}$ (`daily_goal_progress_ratio`):
1. If user is actively pressing/holding the mascot on the Home screen (`is_pointer_down == true`): `mood = 'squinting'`.
2. Else if $R == 0.0$: `mood = 'sleepy'`.
3. Else if $0.0 < R < 0.50$: `mood = 'neutral'`.
4. Else if $0.50 \le R < 1.00$: `mood = 'happy'`.
5. Else ($R \ge 1.00$): `mood = 'thriving'`.

### 6.2 Seeded Badges Unlock Predicates (`badges_catalog`)
Evaluated inside the same database transaction whenever steps, CO₂, streak, RSO reports, or Shared Forest contributions update:

| `badge_code` | `threshold_type` | Unlock Predicate | Reward Points | Unlocked Accessory |
| :--- | :--- | :--- | :--- | :--- |
| `first_10k_steps` | `steps_total` | `SUM(daily_step_summaries.validated_steps) >= 10000` | `+100 ★` | `NULL` |
| `co2_saver_5kg` | `co2_grams_total` | `users.lifetime_co2_saved_grams >= 5000` | `+250 ★` | `NULL` |
| `streak_7_days` | `streak_days` | `users.longest_streak_days >= 7` | `+200 ★` | `'firefly_aura'` |
| `rso_scout_5` | `rso_reports` | `COUNT(point_reports WHERE user_id = u.id) >= 5` | `+150 ★` | `NULL` |
| `forest_guardian_10k` | `forest_contribution` | `SUM(shared_forest_contributions.contributed_co2_grams) >= 10000` | `+300 ★` | `'moss_crown'` |

---

## 7. RSO Waste Point `trust_score` & Crowd-Moderation Algorithm

### 7.1 Scale & Report Delta Table
In `contracts/schema.sql`, `waste_points.trust_score` is stored on a `0.00` to `100.00` percentage scale (default `50.00` for open-data imports, `45.00` for community suggestions; normalized UI ratio is $\text{trust\_ratio} = \text{trust\_score} / 100.0 \in [0.00, 1.00]$).

Each `report_type` in `POST /api/v1/map/waste-points/{point_id}/reports` maps to an exact base `trust_delta`:

| `report_type` ENUM | Base `trust_delta` (`0..100` scale) | Normalized Ratio Delta (`0..1`) | Effect on Counters |
| :--- | :--- | :--- | :--- |
| `confirm_working` | `+10.00` | `+0.10` | `confirmations_count + 1`, updates `last_verified_at = NOW()` |
| `photo_update` | `+5.00` | `+0.05` | `issues_count + 1` (metadata enrichment) |
| `overflowing` | `-8.00` | `-0.08` | `issues_count + 1` |
| `inaccessible` | `-12.00` | `-0.12` | `issues_count + 1` |
| `wrong_fractions` | `-15.00` | `-0.15` | `issues_count + 1` |
| `missing_bin` | `-25.00` | `-0.25` | `issues_count + 1` |

### 7.2 Proximity Gate, Cooldown & Trigger Transitions
1. **Proximity Gate (`2,000 m`)**:
   Compute $D_{\text{user}} = \text{ST\_Distance}(\text{waste\_point.geog}, \text{ST\_SetSRID(ST\_MakePoint(user\_lon, user\_lat), 4326)::geography})$.
   If $D_{\text{user}} > 2000.00\text{ m}$, reject with `422 REPORT_USER_TOO_FAR_FROM_POINT`.
2. **Per-User Anti-Brigading Cooldown (`12 hours`)**:
   If `EXISTS (SELECT 1 FROM point_reports WHERE waste_point_id = $1 AND user_id = $2 AND created_at > NOW() - INTERVAL '12 hours')`, reject with `429 DUPLICATE_POINT_REPORT_COOLDOWN`.
3. **Clamping & Status Transition (`trg_point_reports_apply_trust`)**:
   $$T_{\text{new}} = \min\left(100.00, \max\left(0.00, T_{\text{old}} + \Delta T\right)\right)$$
   - If $T_{\text{new}} < 25.00$ and `status == 'active'`, transition `status = 'unverified'` (hidden from default map queries unless `include_unverified = true`).
   - If $T_{\text{new}} \ge 50.00$ and `status == 'unverified'`, transition `status = 'active'`.

---

## 8. Formal Design-by-Contract (`icontract` + `CrossHair`/Z3) Specification Table

Every pure function in `backend/app/domain/` MUST implement these exact `@icontract.require` preconditions and `@icontract.ensure` postconditions:

| Module & Function Signature | `@icontract.require` Preconditions | `@icontract.ensure` Postconditions |
| :--- | :--- | :--- |
| `vehicle_emissions.compute_vehicle_co2_factors(fuel: FuelType, consumption_per_100km: Decimal) -> tuple[Decimal, Decimal]` | `Decimal("0.01") <= consumption_per_100km <= Decimal("50.00")` | `result[0] > Decimal("0") and result[1] > Decimal("0") and result[0] == (result[1] * Decimal("1000")).quantize(Decimal("0.01"))` |
| `motion_classifier.compute_reboot_safe_step_delta(prev_cumulative: int, curr_cumulative: int) -> int` | `prev_cumulative >= 0 and curr_cumulative >= 0` | `result >= 0 and (result == curr_cumulative - prev_cumulative if curr_cumulative >= prev_cumulative else result == curr_cumulative)` |
| `motion_classifier.classify_interval(delta_t_sec: Decimal, delta_dist_m: Decimal, delta_steps: int, accuracy_m: Decimal) -> TrackPointMotionClass` | `delta_t_sec >= Decimal("1.0") and delta_dist_m >= Decimal("0.0") and delta_steps >= 0 and accuracy_m >= Decimal("0.0")` | `(accuracy_m > Decimal("65.0")) <= (result == TrackPointMotionClass.UNKNOWN)` and `(result == TrackPointMotionClass.WALKING) <= (delta_steps >= 4 and delta_dist_m >= Decimal("6.00"))` |
| `hybrid_co2.compute_segment_co2_grams(segment_distance_m: Decimal, co2_g_per_meter: Decimal) -> int` | `segment_distance_m > Decimal("0.0") and co2_g_per_meter >= Decimal("0.0")` | `result >= 0` |
| `hybrid_co2.compute_hybrid_daily_co2(validated_steps: int, stride_length_cm: int, allocated_gps_distance_m: Decimal, allocated_co2_grams: int, allocation_count: int) -> HybridCo2Result` | `0 <= validated_steps <= 100000 and 40 <= stride_length_cm <= 120 and allocated_gps_distance_m >= Decimal("0.0") and allocated_co2_grams >= 0 and allocation_count >= 0` | `result.total_step_distance_m >= Decimal("0.0") and result.unallocated_step_distance_m >= Decimal("0.0") and result.auto_default_co2_grams >= 0 and result.total_co2_grams == allocated_co2_grams + result.auto_default_co2_grams and result.is_auto_calculated == (allocation_count == 0)` |
| `hybrid_co2.compute_daily_step_points_delta(validated_steps: int, already_awarded_points: int) -> tuple[int, int]` | `0 <= validated_steps <= 100000 and 0 <= already_awarded_points <= 1000` | `result[0] == validated_steps // 100 and result[1] == max(0, result[0] - already_awarded_points)` |
| `equivalents.compute_eco_equivalents(total_co2_saved_grams: int) -> EcoEquivalentsVO` | `total_co2_saved_grams >= 0` | `result.trees_planted_equivalent >= Decimal("0.0") and result.car_km_avoided >= Decimal("0.0") and result.smartphone_charges_equivalent >= 0 and (total_co2_saved_grams == 0) <= (result.trees_planted_equivalent == Decimal("0.00"))` |
| `rso_trust.compute_new_trust_score(current_trust: Decimal, report_type: ReportType) -> tuple[Decimal, Decimal, WastePointStatus]` | `Decimal("0.00") <= current_trust <= Decimal("100.00")` | `Decimal("-30.00") <= result[0] <= Decimal("20.00") and Decimal("0.00") <= result[1] <= Decimal("100.00") and ((result[1] < Decimal("25.00")) <= (result[2] == WastePointStatus.UNVERIFIED))` |
