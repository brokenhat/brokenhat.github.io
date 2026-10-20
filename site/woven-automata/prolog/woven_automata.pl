% ============================================================
%  WOVEN AUTOMATA v2 — B&W Tapestry with Borders & Half-Passes
% ============================================================
%
%  Territory-based bobbins on a warp. Each bobbin owns a range
%  of threads (Left..Right) and fills them each pick. Rules
%  govern how territories grow, shrink, and shift — producing
%  organic, tree-like growth patterns in black and white.
%
%  When a territory hits a selvedge (warp edge), its directional
%  rules mirror — grow_left becomes grow_right, etc. — creating
%  a bounce effect.
%
%  Cell values:
%    0 = bare warp    (uncolored)
%    1 = black, full  (dense)
%    2 = white, full  (dense)
%    3 = black, half  (partial, warp peeks through)
%    4 = white, half  (partial, lighter texture)
%
%  Usage:
%    ?- demo.              % Quick test (80 threads)
%    ?- demo(120).         % Quick test with 120 threads
%    ?- find_good.         % Search + evolve (80 threads)
%    ?- find_good(200).    % Search + evolve with 200 threads
%    ?- find_crystalline.  % Geometric/regular patterns
%    ?- find_crystalline(60). % Crystalline with 60 threads
%    ?- find_life.         % Game of Life emergent dynamics
%    ?- find_life(150).    % Game of Life with 150 threads
%    ?- demo_uniform.      % Quick test with uniform rules
%    ?- demo_uniform(120). % Uniform rules, 120 threads
%    ?- find_uniform.      % Search for good uniform patterns
%    ?- find_uniform(150). % Uniform search, 150 threads
%
% ============================================================

:- use_module(library(lists)).
:- use_module(library(random)).
:- use_module(library(apply)).
:- use_module(library(pairs)).
:- discontiguous condition_met/8.

% --- Tunable parameters ---

:- dynamic warp_width/1, num_bobbins/1, num_picks/1, border_style/1, max_bobbins/1.
:- dynamic uniform_mode/0, uniform_rule/1.
:- dynamic ca_rule/1, weft_alternate/0, ca_rule_fixed/0.
warp_width(80).
num_bobbins(8).
num_picks(500).
border_style(slit).  % slit | interlock
max_bobbins(20).     % hard cap on total bobbins (active + dormant)

% ============================================================
%  DATA MODEL
% ============================================================

%% cell_value(+Color, +PassType, -Value)
cell_value(black, full, 1).
cell_value(white, full, 2).
cell_value(black, half, 3).
cell_value(white, half, 4).

% ============================================================
%  INITIALIZATION
% ============================================================

%% init_bobbins(-Bobbins)
%  Bobbin count varies randomly around the num_bobbins setting.
init_bobbins(Bobbins) :-
    num_bobbins(Base),
    Lo is max(3, Base - 3),
    Hi is Base + 3,
    random_between(Lo, Hi, NB),
    rand_start_style(Style),
    init_bobbins_style(Style, NB, Bobbins).

rand_start_style(Style) :-
    random_between(0, 4, R),
    nth0(R, [single_seed, twin_seeds, cluster, scattered, linear], Style).

init_bobbins_style(single_seed, NB, Bobbins) :-
    warp_width(W),
    Center is W // 2,
    random_between(3, 10, SeedW),
    L0 is max(1, Center - SeedW // 2),
    R0 is min(W, L0 + SeedW - 1),
    rand_color(C1), rand_pass(P1), rand_ruleset(Rules1),
    B1 = bobbin(1, L0, R0, C1, P1, Rules1),
    make_dormant_bobbins(2, NB, Bs),
    Bobbins = [B1 | Bs].

init_bobbins_style(twin_seeds, NB, Bobbins) :-
    warp_width(W),
    Center is W // 2,
    random_between(3, 8, W1),
    random_between(3, 8, W2),
    random_between(2, 6, Gap),
    L1 is max(1, Center - Gap // 2 - W1),
    R1 is L1 + W1 - 1,
    L2 is R1 + Gap + 1,
    R2 is min(W, L2 + W2 - 1),
    rand_color(C1), rand_pass(P1), rand_ruleset(Ru1),
    rand_color(C2), rand_pass(P2), rand_ruleset(Ru2),
    B1 = bobbin(1, L1, R1, C1, P1, Ru1),
    B2 = bobbin(2, L2, R2, C2, P2, Ru2),
    make_dormant_bobbins(3, NB, Rest),
    Bobbins = [B1, B2 | Rest].

init_bobbins_style(cluster, NB, Bobbins) :-
    warp_width(W),
    Center is W // 2,
    ClusterN is min(NB, 5),
    make_cluster_bobbins(1, ClusterN, Center, W, ClusterBs),
    CN1 is ClusterN + 1,
    make_dormant_bobbins(CN1, NB, Rest),
    append(ClusterBs, Rest, Bobbins).

init_bobbins_style(scattered, NB, Bobbins) :-
    warp_width(W),
    make_scattered_bobbins(1, NB, W, Bobbins).

init_bobbins_style(linear, NB, Bobbins) :-
    warp_width(W),
    make_linear_bobbins(1, NB, W, Bobbins).

make_dormant_bobbins(Start, Max, []) :- Start > Max, !.
make_dormant_bobbins(Start, Max, [B|Bs]) :-
    Start =< Max,
    rand_color(C), rand_pass(P), rand_ruleset(Rules),
    B = bobbin(Start, 0, 0, C, P, Rules),
    S1 is Start + 1,
    make_dormant_bobbins(S1, Max, Bs).

make_cluster_bobbins(Id, Count, _, _, []) :- Id > Count, !.
make_cluster_bobbins(Id, Count, Center, W, [B|Bs]) :-
    Id =< Count,
    random_between(3, 8, BW),
    Offset is (Id - 1) * 8 - (Count * 4),
    L is max(1, Center + Offset),
    R is min(W, L + BW - 1),
    rand_color(C), rand_pass(P), rand_ruleset(Rules),
    B = bobbin(Id, L, R, C, P, Rules),
    Id1 is Id + 1,
    make_cluster_bobbins(Id1, Count, Center, W, Bs).

make_scattered_bobbins(Id, Count, _, []) :- Id > Count, !.
make_scattered_bobbins(Id, Count, W, [B|Bs]) :-
    Id =< Count,
    random_between(3, 12, BW),
    MaxL is max(1, W - BW),
    random_between(1, MaxL, L),
    R is min(W, L + BW - 1),
    rand_color(C), rand_pass(P), rand_ruleset(Rules),
    B = bobbin(Id, L, R, C, P, Rules),
    Id1 is Id + 1,
    make_scattered_bobbins(Id1, Count, W, Bs).

make_linear_bobbins(Id, Count, _, []) :- Id > Count, !.
make_linear_bobbins(Id, Count, W, [B|Bs]) :-
    Id =< Count,
    Segment is W // Count,
    MinBW is max(2, Segment // 3),
    MaxBW is max(MinBW, Segment),
    random_between(MinBW, MaxBW, BW),
    L is (Id - 1) * Segment + 1,
    R is min(W, L + BW - 1),
    rand_color(C), rand_pass(P), rand_ruleset(Rules),
    B = bobbin(Id, L, R, C, P, Rules),
    Id1 is Id + 1,
    make_linear_bobbins(Id1, Count, W, Bs).

% --- Config save/restore ---
%  A config carries the loom settings (CA rule, weft alternation, shared
%  uniform rules) next to the bobbin specs, so whatever is printed as
%  instructions is exactly what gets woven — no leftover global state.

init_bobbins_from_config(config(Specs, Loom), Bobbins) :-
    set_loom(Loom),
    maplist(spec_to_bobbin, Specs, Bobbins).

spec_to_bobbin(spec(Id, L, R, C, P, Rules), bobbin(Id, L, R, C, P, Rules)).

bobbins_to_config(Bobbins, config(Specs, Loom)) :-
    current_loom(Loom),
    maplist(bobbin_to_spec, Bobbins, Specs).

current_loom(loom(CA, WA, UR)) :-
    (ca_rule(CA) -> true ; CA = none),
    (weft_alternate -> WA = yes ; WA = no),
    (uniform_rule(UR) -> true ; UR = none).

set_loom(loom(CA, WA, UR)) :- !,
    retractall(ca_rule(_)),
    (CA == none -> true ; assertz(ca_rule(CA))),
    retractall(weft_alternate),
    (WA == yes -> assertz(weft_alternate) ; true),
    retractall(uniform_rule(_)),
    (UR == none -> true ; assertz(uniform_rule(UR))).
set_loom(_).

bobbin_to_spec(bobbin(Id, L, R, C, P, Rules), spec(Id, L, R, C, P, Rules)).

% --- Random generators ---

rand_color(C) :-
    random_between(0, 1, R),
    (R =:= 0 -> C = black ; C = white).

rand_pass(P) :-
    random_between(0, 1, R),
    (R =:= 0 -> P = full ; P = half).

rand_ruleset(Rules) :-
    random_between(2, 5, N),
    length(Rules, N),
    maplist(rand_edge_rule, Rules).

rand_edge_rule(edge_rule(Cond, Action)) :-
    rand_condition(Cond),
    rand_action(Action).

rand_condition(Cond) :-
    random_between(0, 13, R),
    rand_condition_(R, Cond).

rand_condition_(0, always).
rand_condition_(1, neighbor_is(C)) :- rand_color(C).
rand_condition_(2, below_edge_is(C)) :- rand_color(C).
rand_condition_(3, at_warp_edge).
rand_condition_(4, territory_wider(N)) :- random_between(5, 20, N).
rand_condition_(5, territory_narrower(N)) :- random_between(2, 8, N).
rand_condition_(6, pick_mod(M, Rem)) :-
    random_between(2, 6, M), MaxR is M - 1, random_between(0, MaxR, Rem).
rand_condition_(7, always).
rand_condition_(8, neighbor_count(Op, N)) :-
    random_member(Op, [<, >, =]),
    random_between(0, 3, N).
rand_condition_(9, gap_nearby(Side, MinW)) :-
    random_member(Side, [left, right]),
    random_between(3, 10, MinW).
rand_condition_(10, alive_ratio(Op, Pct)) :-
    random_member(Op, [<, >]),
    random_between(20, 80, Pct).
rand_condition_(11, prev_edge_alive(Side)) :-
    random_member(Side, [left, right]).
rand_condition_(12, territory_density(Op, Pct)) :-
    random_member(Op, [<, >]),
    random_between(20, 80, Pct).
rand_condition_(13, neighbor_width(Op, N)) :-
    random_member(Op, [<, >]),
    random_between(3, 15, N).

rand_action(Action) :-
    random_between(0, 14, R),
    rand_action_(R, Action).

rand_action_(0, grow_left(N)) :- random_between(1, 3, N).
rand_action_(1, grow_right(N)) :- random_between(1, 3, N).
rand_action_(2, shrink_left(N)) :- random_between(1, 2, N).
rand_action_(3, shrink_right(N)) :- random_between(1, 2, N).
rand_action_(4, grow_both(N)) :- random_between(1, 2, N).
rand_action_(5, shrink_both(N)) :- random_between(1, 2, N).
rand_action_(6, shift_left(N)) :- random_between(1, 3, N).
rand_action_(7, shift_right(N)) :- random_between(1, 3, N).
rand_action_(8, flip_color).
rand_action_(9, toggle_pass).
rand_action_(10, grow_both(1)).
rand_action_(11, spawn_left(N)) :- random_between(3, 8, N).
rand_action_(12, spawn_right(N)) :- random_between(3, 8, N).
rand_action_(13, die).
rand_action_(14, die).

% ============================================================
%  GEOMETRIC RULE TEMPLATES
% ============================================================
%
%  Curated rule sets that produce regular, crystalline structures.
%  Each template is a complete ruleset for one bobbin.

%% geo_ruleset(-Rules)
%  Pick a random geometric template.
geo_ruleset(Rules) :-
    random_between(0, 9, R),
    geo_template(R, Rules).

%  Diamond: expand until wide, then contract, repeat
geo_template(0, Rules) :-
    random_between(8, 20, MaxW),
    random_between(2, 5, MinW),
    Rules = [edge_rule(territory_narrower(MinW), grow_both(1)),
             edge_rule(territory_wider(MaxW), shrink_both(1)),
             edge_rule(at_warp_edge, shrink_both(2))].

%  Zigzag: shift one direction, bounce off edges
geo_template(1, Rules) :-
    random_between(1, 2, N),
    Rules = [edge_rule(always, shift_right(N)),
             edge_rule(at_warp_edge, flip_color)].

%  Pulse: periodic grow/shrink with color flip
geo_template(2, Rules) :-
    random_between(3, 6, Period),
    P1 is Period // 2,
    Rules = [edge_rule(pick_mod(Period, 0), grow_both(2)),
             edge_rule(pick_mod(Period, P1), shrink_both(2)),
             edge_rule(pick_mod(Period, 0), flip_color)].

%  Sawtooth: grow one side, snap back periodically
geo_template(3, Rules) :-
    random_between(4, 8, Period),
    random_between(1, 2, GrowN),
    P1 is Period - 1,
    Snap is GrowN * Period,
    Rules = [edge_rule(always, grow_right(GrowN)),
             edge_rule(pick_mod(Period, P1), shrink_right(Snap)),
             edge_rule(pick_mod(Period, P1), toggle_pass)].

%  Breathing columns: small periodic width oscillation, no drift
geo_template(4, Rules) :-
    random_between(2, 4, Period),
    Rules = [edge_rule(pick_mod(Period, 0), grow_both(1)),
             edge_rule(pick_mod(Period, 1), shrink_both(1)),
             edge_rule(territory_wider(15), shrink_both(1)),
             edge_rule(territory_narrower(3), grow_both(1))].

%  Staircase: shift + periodic color change
geo_template(5, Rules) :-
    random_between(1, 2, ShiftN),
    random_between(3, 8, FlipPeriod),
    Rules = [edge_rule(always, shift_left(ShiftN)),
             edge_rule(pick_mod(FlipPeriod, 0), flip_color),
             edge_rule(pick_mod(FlipPeriod, 0), toggle_pass),
             edge_rule(at_warp_edge, flip_color)].

%  Mirror diamond: grow both + periodic pass toggle
geo_template(6, Rules) :-
    random_between(6, 15, MaxW),
    random_between(2, 4, MinW),
    random_between(2, 5, PassPeriod),
    Rules = [edge_rule(territory_narrower(MinW), grow_both(2)),
             edge_rule(territory_wider(MaxW), shrink_both(2)),
             edge_rule(pick_mod(PassPeriod, 0), toggle_pass),
             edge_rule(at_warp_edge, shrink_both(1))].

%  Lattice: fixed width, periodic color/pass changes
geo_template(7, Rules) :-
    random_between(2, 6, CP),
    random_between(3, 8, PP),
    Rules = [edge_rule(pick_mod(CP, 0), flip_color),
             edge_rule(pick_mod(PP, 0), toggle_pass),
             edge_rule(territory_wider(12), shrink_both(1)),
             edge_rule(territory_narrower(4), grow_both(1))].

%  Branching: grow until wide, then spawn children
geo_template(8, Rules) :-
    random_between(10, 18, SpawnW),
    random_between(3, 6, ChildW),
    Rules = [edge_rule(always, grow_both(1)),
             edge_rule(territory_wider(SpawnW), spawn_right(ChildW)),
             edge_rule(territory_wider(SpawnW), shrink_both(3)),
             edge_rule(at_warp_edge, flip_color)].

%  Periodic spawner: spawn at regular intervals
geo_template(9, Rules) :-
    random_between(15, 40, Period),
    random_between(3, 6, ChildW),
    Rules = [edge_rule(pick_mod(Period, 0), spawn_right(ChildW)),
             edge_rule(pick_mod(Period, 0), spawn_left(ChildW)),
             edge_rule(territory_wider(10), shrink_both(1)),
             edge_rule(territory_narrower(3), grow_both(1)),
             edge_rule(pick_mod(Period, 0), flip_color)].

%% init_bobbins_geometric(+NB, -Bobbins)
%  Create bobbins with geometric rules, evenly spaced.
init_bobbins_geometric(NB, Bobbins) :-
    warp_width(W),
    make_geo_bobbins(1, NB, W, Bobbins).

make_geo_bobbins(Id, Count, _, []) :- Id > Count, !.
make_geo_bobbins(Id, Count, W, [B|Bs]) :-
    Id =< Count,
    Segment is W // Count,
    BW is max(3, Segment - 2),
    L is (Id - 1) * Segment + 1,
    R is min(W, L + BW - 1),
    % Alternate black/white
    (Id mod 2 =:= 1 -> C = black ; C = white),
    % Alternate full/half
    (Id mod 3 =:= 0 -> P = half ; P = full),
    geo_ruleset(Rules),
    B = bobbin(Id, L, R, C, P, Rules),
    Id1 is Id + 1,
    make_geo_bobbins(Id1, Count, W, Bs).

%% Regularity score — rewards periodic, symmetric patterns
regularity_score(Fabric, Score) :-
    length(Fabric, NRows),
    (   NRows < 6 -> Score = 0.5
    ;   % Check row-to-row similarity at fixed intervals
        check_periodicity(Fabric, NRows, 2, P2),
        check_periodicity(Fabric, NRows, 3, P3),
        check_periodicity(Fabric, NRows, 4, P4),
        check_periodicity(Fabric, NRows, 6, P6),
        MaxP is max(P2, max(P3, max(P4, P6))),
        % Also check horizontal symmetry
        check_h_symmetry(Fabric, HSym),
        Score is min(1.0, MaxP * 0.7 + HSym * 0.3)
    ).

%% check_periodicity(+Fabric, +NRows, +Period, -Score)
%  How similar are rows that are Period apart?
check_periodicity(Fabric, NRows, Period, Score) :-
    MaxCheck is min(30, (NRows - Period) // Period),
    (   MaxCheck < 2 -> Score = 0.0
    ;   check_period_pairs(Fabric, NRows, Period, MaxCheck, 0, 0, SimSum, Count),
        (Count =:= 0 -> Score = 0.0 ; Score is SimSum / Count)
    ).

check_period_pairs(_, _, _, 0, S, C, S, C) :- !.
check_period_pairs(Fabric, NRows, Period, Remaining, SAcc, CAcc, SOut, COut) :-
    Remaining > 0,
    % Pick a random starting row
    MaxStart is NRows - Period,
    random_between(1, MaxStart, Idx),
    Idx2 is Idx + Period,
    nth1(Idx, Fabric, Row1),
    nth1(Idx2, Fabric, Row2),
    row_similarity(Row1, Row2, Sim),
    S1 is SAcc + Sim, C1 is CAcc + 1,
    R1 is Remaining - 1,
    check_period_pairs(Fabric, NRows, Period, R1, S1, C1, SOut, COut).

%% row_similarity(+Row1, +Row2, -Similarity)
%  Fraction of positions where the two rows have the same cell class.
row_similarity([], [], 1.0).
row_similarity(R1, R2, Sim) :-
    row_sim_(R1, R2, 0, 0, Same, Total),
    (Total =:= 0 -> Sim = 0.0 ; Sim is Same / Total).

row_sim_([], [], S, T, S, T) :- !.
row_sim_([A|As], [B|Bs], SAcc, TAcc, SOut, TOut) :-
    cell_class(A, CA), cell_class(B, CB),
    (CA = CB -> S1 is SAcc + 1 ; S1 = SAcc),
    T1 is TAcc + 1,
    row_sim_(As, Bs, S1, T1, SOut, TOut).

%% check_h_symmetry(+Fabric, -Score)
%  Sample rows and check left-right symmetry.
check_h_symmetry(Fabric, Score) :-
    length(Fabric, NRows),
    MaxSample is min(20, NRows),
    check_h_sym_(Fabric, NRows, MaxSample, 0, 0, SymSum, Count),
    (Count =:= 0 -> Score = 0.0 ; Score is SymSum / Count).

check_h_sym_(_, _, 0, S, C, S, C) :- !.
check_h_sym_(Fabric, NRows, Rem, SAcc, CAcc, SOut, COut) :-
    Rem > 0,
    random_between(1, NRows, Idx),
    nth1(Idx, Fabric, Row),
    reverse(Row, RevRow),
    row_similarity(Row, RevRow, Sim),
    S1 is SAcc + Sim, C1 is CAcc + 1,
    R1 is Rem - 1,
    check_h_sym_(Fabric, NRows, R1, S1, C1, SOut, COut).

%% evaluate_crystalline(+Fabric, -Score, -Details)
%  Evaluation biased toward geometric/regular patterns.
evaluate_crystalline(Fabric, Score, Details) :-
    count_cells(Fabric, NBlack, NWhite, NFull, NHalf, NZero, Total),
    bw_ratio_score(NBlack, NWhite, BWScore),
    pass_variety_score(NFull, NHalf, PassScore),
    negative_space_score(NZero, Total, NegScore),
    regularity_score(Fabric, RegScore),
    growth_score(Fabric, GrowthScore),
    Details = details(bw_ratio=BWScore, pass_variety=PassScore,
                      regularity=RegScore, growth=GrowthScore,
                      negative_space=NegScore),
    % Heavy weight on regularity
    Score is BWScore * 0.15 + PassScore * 0.10 + RegScore * 0.40
           + GrowthScore * 0.15 + NegScore * 0.20.

% ============================================================
%  GAME OF LIFE TEMPLATES — birth/death/interaction rules
% ============================================================

%% life_ruleset(-Rules)
%  Rule templates designed for emergent GoL-like behavior.
life_ruleset(Rules) :-
    random_between(0, 7, R),
    life_template(R, Rules).

%  Overcrowding death: die if too many neighbors, grow if isolated
life_template(0, Rules) :-
    random_between(2, 3, DeathN),
    Rules = [edge_rule(neighbor_count(>, DeathN), die),
             edge_rule(neighbor_count(=, 0), shrink_both(1)),
             edge_rule(neighbor_count(=, 1), grow_both(1)),
             edge_rule(territory_narrower(2), die)].

%  Isolation death: die without neighbors, spawn when healthy
life_template(1, Rules) :-
    random_between(3, 6, ChildW),
    random_between(10, 20, SpawnW),
    Rules = [edge_rule(neighbor_count(=, 0), die),
             edge_rule(always, grow_both(1)),
             edge_rule(territory_wider(SpawnW), spawn_right(ChildW)),
             edge_rule(territory_wider(SpawnW), shrink_both(2)),
             edge_rule(at_warp_edge, flip_color)].

%  Pulsing life: grow/shrink cycles, die if too narrow
life_template(2, Rules) :-
    random_between(3, 8, Period),
    PR is Period // 2,
    Rules = [edge_rule(pick_mod(Period, 0), grow_both(2)),
             edge_rule(pick_mod(Period, PR), shrink_both(2)),
             edge_rule(territory_narrower(2), die),
             edge_rule(neighbor_count(>, 2), shrink_both(1)),
             edge_rule(territory_wider(15), spawn_left(4))].

%  Competitive: grow toward neighbors, die if squeezed
life_template(3, Rules) :-
    Rules = [edge_rule(gap_nearby(right, 5), grow_right(2)),
             edge_rule(gap_nearby(left, 5), grow_left(2)),
             edge_rule(neighbor_count(>, 2), shrink_both(1)),
             edge_rule(territory_narrower(2), die),
             edge_rule(territory_wider(20), flip_color)].

%  Reactive: change color/pass based on neighborhood density
life_template(4, Rules) :-
    Rules = [edge_rule(neighbor_count(>, 1), flip_color),
             edge_rule(neighbor_count(=, 0), grow_both(1)),
             edge_rule(neighbor_count(>, 2), die),
             edge_rule(always, shift_right(1)),
             edge_rule(at_warp_edge, flip_color)].

%  Breeder: aggressive spawning with mortality
life_template(5, Rules) :-
    random_between(8, 15, SpawnW),
    random_between(3, 5, ChildW),
    Rules = [edge_rule(always, grow_right(1)),
             edge_rule(territory_wider(SpawnW), spawn_right(ChildW)),
             edge_rule(territory_wider(SpawnW), spawn_left(ChildW)),
             edge_rule(territory_wider(SpawnW), shrink_both(4)),
             edge_rule(neighbor_count(>, 3), die),
             edge_rule(territory_narrower(2), die)].

%  Population-aware: grow when sparse, shrink when dense
life_template(6, Rules) :-
    Rules = [edge_rule(alive_ratio(<, 30), grow_both(2)),
             edge_rule(alive_ratio(>, 70), shrink_both(2)),
             edge_rule(alive_ratio(>, 80), die),
             edge_rule(territory_narrower(2), die),
             edge_rule(neighbor_is(black), toggle_pass),
             edge_rule(neighbor_is(white), flip_color)].

%  Wanderer: shift around, die at edges, spawn when big
life_template(7, Rules) :-
    random_between(4, 7, ChildW),
    Rules = [edge_rule(always, shift_right(1)),
             edge_rule(at_warp_edge, die),
             edge_rule(territory_wider(12), spawn_left(ChildW)),
             edge_rule(neighbor_count(=, 0), grow_both(1)),
             edge_rule(neighbor_count(>, 1), shrink_both(1))].

%% init_bobbins_life(+NB, -Bobbins)
%  Start with a few small seed bobbins using life rules.
init_bobbins_life(NB, Bobbins) :-
    warp_width(W),
    make_life_bobbins(1, NB, W, Bobbins).

make_life_bobbins(Id, Count, _, []) :- Id > Count, !.
make_life_bobbins(Id, Count, W, [B|Bs]) :-
    Id =< Count,
    % Scatter small seeds with gaps between them
    Segment is W // Count,
    SeedW is max(3, min(8, Segment // 3)),
    Mid is (Id - 1) * Segment + Segment // 2,
    L is max(1, Mid - SeedW // 2),
    R is min(W, L + SeedW - 1),
    (Id mod 2 =:= 1 -> C = black ; C = white),
    random_member(P, [full, half]),
    life_ruleset(Rules),
    B = bobbin(Id, L, R, C, P, Rules),
    Id1 is Id + 1,
    make_life_bobbins(Id1, Count, W, Bs).

% ============================================================
%  UNIFORM RULE TEMPLATES — one rule for all bobbins
% ============================================================
%
%  Curated rule sets designed for single-rule emergent behavior.
%  The SAME rule is given to every bobbin; complexity emerges from
%  spatial context (neighbor count, territory width, gaps, edges).

%% uniform_ruleset(-Rules, -CARule)
%  Pick a random CA-enhanced uniform template.
%  Returns both the territory rules and the Wolfram CA rule number.
%  Some templates also assert weft_alternate for weft direction simulation.
uniform_ruleset(Rules, CARule) :-
    random_between(0, 7, R),
    uniform_template(R, Rules, CARule, WeftAlt),
    retractall(weft_alternate),
    (WeftAlt = yes -> assertz(weft_alternate) ; true).

%  0: Sierpinski Weave — Rule 90 (fractal XOR triangles)
%  Density-driven breathing: fractal triangles grow inward from edges.
%  When interior fills up (fractals meet), density rises → shrink → reset.
uniform_template(0, Rules, 90, no) :-
    Rules = [
        edge_rule(territory_density(<, 40), grow_both(1)),
        edge_rule(territory_density(>, 70), shrink_both(1)),
        edge_rule(territory_narrower(4), grow_both(1)),
        edge_rule(territory_narrower(2), die),
        edge_rule(at_warp_edge, flip_color)
    ].

%  1: Glider Loom — Rule 110 (Turing-complete, gliders!)
%  Grow toward active edges, shrink when CA fills densely.
%  Glider propagation at territory boundaries drives organic growth.
uniform_template(1, Rules, 110, no) :-
    Rules = [
        edge_rule(prev_edge_alive(right), grow_right(1)),
        edge_rule(prev_edge_alive(left), grow_left(1)),
        edge_rule(territory_density(>, 70), shrink_both(1)),
        edge_rule(territory_density(<, 30), grow_both(1)),
        edge_rule(territory_narrower(2), die),
        edge_rule(at_warp_edge, flip_color)
    ].

%  2: Chaos Tapestry — Rule 30 (chaotic center, ordered edges)
%  Asymmetric density response: sparse → grow left, dense → shrink right.
%  Creates natural drift from the asymmetry of rule 30 itself.
uniform_template(2, Rules, 30, yes) :-
    Rules = [
        edge_rule(territory_density(<, 35), grow_left(1)),
        edge_rule(territory_density(>, 65), shrink_right(1)),
        edge_rule(territory_narrower(4), grow_both(1)),
        edge_rule(territory_narrower(2), die),
        edge_rule(at_warp_edge, toggle_pass)
    ].

%  3: Coral Growth — Rule 54 (complex persistent structures)
%  Grows toward active edges, shrinks when overfull.
%  Creates organic branching as the CA structures push boundaries.
uniform_template(3, Rules, 54, no) :-
    Rules = [
        edge_rule(prev_edge_alive(right), grow_right(1)),
        edge_rule(prev_edge_alive(left), grow_left(1)),
        edge_rule(territory_density(>, 65), shrink_both(1)),
        edge_rule(territory_density(<, 25), grow_both(1)),
        edge_rule(territory_narrower(2), die),
        edge_rule(pick_mod(7, 0), flip_color)
    ].

%  4: Diamond Lattice — Rule 150 (intersecting fractal diamonds)
%  Density feedback with periodic color/pass modulation.
%  Fractal diamonds from both edges create interference patterns.
uniform_template(4, Rules, 150, no) :-
    random_between(5, 10, Period),
    Rules = [
        edge_rule(territory_density(<, 40), grow_both(1)),
        edge_rule(territory_density(>, 70), shrink_both(1)),
        edge_rule(territory_narrower(4), grow_both(1)),
        edge_rule(territory_narrower(2), die),
        edge_rule(pick_mod(Period, 0), toggle_pass),
        edge_rule(at_warp_edge, flip_color)
    ].

%  5: Particle Flow — Rule 184 (traffic/particle conservation)
%  Rightward drift — this rule genuinely models directional particle flow,
%  so shift_right is semantically appropriate, not a crutch.
uniform_template(5, Rules, 184, yes) :-
    Rules = [
        edge_rule(always, shift_right(1)),
        edge_rule(territory_density(<, 35), grow_both(1)),
        edge_rule(territory_density(>, 65), shrink_both(1)),
        edge_rule(territory_narrower(2), die),
        edge_rule(at_warp_edge, flip_color)
    ].

%  6: Cascade — Rule 60 (asymmetric triangles)
%  Asymmetric growth: grow toward active right edge, shrink from left.
%  Rule 60's inherent asymmetry drives diagonal structure.
uniform_template(6, Rules, 60, yes) :-
    Rules = [
        edge_rule(prev_edge_alive(right), grow_right(1)),
        edge_rule(territory_density(>, 55), shrink_left(1)),
        edge_rule(territory_density(<, 30), grow_both(1)),
        edge_rule(territory_narrower(3), grow_both(1)),
        edge_rule(territory_narrower(2), die),
        edge_rule(at_warp_edge, toggle_pass)
    ].

%  7: Pulse Wave — Rule 73 (right-triangular waves)
%  Periodic grow/shrink via pick_mod. Each boundary change seeds a new
%  CA wavefront, creating layered rhythmic patterns.
uniform_template(7, Rules, 73, no) :-
    random_between(6, 12, Period),
    P1 is Period // 2,
    Rules = [
        edge_rule(pick_mod(Period, 0), grow_both(2)),
        edge_rule(pick_mod(Period, P1), shrink_both(2)),
        edge_rule(territory_density(>, 60), flip_color),
        edge_rule(territory_narrower(2), die),
        edge_rule(at_warp_edge, toggle_pass)
    ].

%% init_bobbins_uniform(+NB, -Bobbins)
%  Create NB bobbins all sharing the same uniform ruleset.
%  Also asserts the paired CA rule for thread-level overlay.
init_bobbins_uniform(NB, Bobbins) :-
    uniform_ruleset(Rules, CARule),
    retractall(uniform_rule(_)),
    assertz(uniform_rule(Rules)),
    retractall(ca_rule(_)),
    assertz(ca_rule(CARule)),
    warp_width(W),
    make_uniform_bobbins(1, NB, W, Rules, Bobbins).

% Like init_bobbins_uniform but does not touch ca_rule/1.
% Used when the caller has already set a specific CA rule.
init_bobbins_uniform_keep_ca(NB, Bobbins) :-
    uniform_ruleset(Rules, _),
    retractall(uniform_rule(_)),
    assertz(uniform_rule(Rules)),
    warp_width(W),
    make_uniform_bobbins(1, NB, W, Rules, Bobbins).

make_uniform_bobbins(Id, Count, _, _, []) :- Id > Count, !.
make_uniform_bobbins(Id, Count, W, Rules, [B|Bs]) :-
    Id =< Count,
    Segment is W // Count,
    % Wide seeds: cover most of the segment so the CA has room to work.
    % Leave a 2-thread gap between territories for border resolution.
    SeedW is max(6, Segment - 2),
    Mid is (Id - 1) * Segment + Segment // 2,
    L is max(1, Mid - SeedW // 2),
    R is min(W, L + SeedW - 1),
    (Id mod 2 =:= 1 -> C = black ; C = white),
    random_member(P, [full, half]),
    B = bobbin(Id, L, R, C, P, Rules),
    Id1 is Id + 1,
    make_uniform_bobbins(Id1, Count, W, Rules, Bs).

%% evaluate_life(+Fabric, -Score, -Details)
%  Evaluation biased toward emergent, dynamic, GoL-like behavior.
evaluate_life(Fabric, Score, Details) :-
    count_cells(Fabric, NBlack, NWhite, NFull, NHalf, NZero, Total),
    bw_ratio_score(NBlack, NWhite, BWScore),
    pass_variety_score(NFull, NHalf, PassScore),
    negative_space_score(NZero, Total, NegScore),
    growth_score(Fabric, GrowthScore),
    population_dynamics_score(Fabric, PopScore),
    Details = details(bw_ratio=BWScore, pass_variety=PassScore,
                      growth=GrowthScore, negative_space=NegScore,
                      population_dynamics=PopScore),
    % Heavy weight on dynamics and negative space (gaps = interesting)
    Score is BWScore * 0.10 + PassScore * 0.05 + GrowthScore * 0.25
           + NegScore * 0.25 + PopScore * 0.35.

%% population_dynamics_score(+Fabric, -Score)
%  Reward patterns where the number of active cells changes over time.
%  High score = population rises and falls (not monotone or flat).
population_dynamics_score(Fabric, Score) :-
    length(Fabric, NRows),
    (   NRows < 10 -> Score = 0.5
    ;   sample_population(Fabric, NRows, 20, Pops),
        population_variance(Pops, Var),
        population_trend_changes(Pops, Changes),
        % Variance: some change is good, too much is chaos
        VarScore is min(1.0, Var / 200.0),
        % Direction changes: reward non-monotone behavior
        MaxChanges is max(1, 20 - 1),
        ChangeScore is min(1.0, Changes / (MaxChanges * 0.3)),
        Score is VarScore * 0.4 + ChangeScore * 0.6
    ).

sample_population(_, _, 0, []) :- !.
sample_population(Fabric, NRows, N, [Pop|Rest]) :-
    N > 0,
    Step is max(1, NRows // 20),
    Idx is (20 - N) * Step + 1,
    Idx1 is min(Idx, NRows),
    nth1(Idx1, Fabric, Row),
    count_active_cells(Row, 0, Pop),
    N1 is N - 1,
    sample_population(Fabric, NRows, N1, Rest).

count_active_cells([], Acc, Acc) :- !.
count_active_cells([0|Cs], Acc, Count) :- !,
    count_active_cells(Cs, Acc, Count).
count_active_cells([_|Cs], Acc, Count) :-
    Acc1 is Acc + 1,
    count_active_cells(Cs, Acc1, Count).

population_variance(Pops, Var) :-
    length(Pops, N),
    (   N < 2 -> Var = 0
    ;   sumlist(Pops, Sum), Mean is Sum / N,
        variance_sum(Pops, Mean, 0, VSum),
        Var is VSum / N
    ).

variance_sum([], _, Acc, Acc) :- !.
variance_sum([P|Ps], Mean, Acc, Var) :-
    D is P - Mean, Acc1 is Acc + D * D,
    variance_sum(Ps, Mean, Acc1, Var).

population_trend_changes([], 0) :- !.
population_trend_changes([_], 0) :- !.
population_trend_changes([A, B|Rest], Changes) :-
    (A < B -> Dir = up ; (A > B -> Dir = down ; Dir = flat)),
    trend_changes_(Rest, B, Dir, 0, Changes).

trend_changes_([], _, _, Acc, Acc) :- !.
trend_changes_([X|Xs], Prev, PrevDir, Acc, Changes) :-
    (X > Prev -> Dir = up ; (X < Prev -> Dir = down ; Dir = flat)),
    (Dir \= PrevDir, Dir \= flat, PrevDir \= flat
    ->  Acc1 is Acc + 1
    ;   Acc1 = Acc
    ),
    trend_changes_(Xs, X, Dir, Acc1, Changes).

% ============================================================
%  ROW BUILDING — O(W) direct construction, no set_nth1 loop
% ============================================================

%% build_row(+SortedActiveBobbins, -Row)
%  Walk positions 1..W, for each check which bobbin covers it.
build_row(Bobbins, Row) :-
    warp_width(W),
    build_row_(1, W, Bobbins, Row).

build_row_(Pos, W, _, []) :- Pos > W, !.
build_row_(Pos, W, Bobbins, [Val|Rest]) :-
    Pos =< W,
    covering_value(Pos, Bobbins, Val),
    Pos1 is Pos + 1,
    build_row_(Pos1, W, Bobbins, Rest).

%% covering_value(+Pos, +Bobbins, -Val)
%  Find the first active bobbin covering Pos, or 0 if none.
covering_value(Pos, [bobbin(_, L, R, C, P, _)|_], Val) :-
    L > 0, R >= L, L =< Pos, R >= Pos, !,
    cell_value(C, P, Val).
covering_value(Pos, [_|Bs], Val) :-
    covering_value(Pos, Bs, Val).
covering_value(_, [], 0).

% ============================================================
%  WEAVING ONE PICK (ROW)
% ============================================================

%% weave_pick(+Bobbins, +PrevRow, +PickNum, -NewRow, -NewBobbins)
weave_pick(Bobbins, PrevRow, PickNum, FinalRow, NewBobbins) :-
    sort_bobbins_lr(Bobbins, Sorted),
    active_bobbins(Sorted, Active),
    build_row(Active, FilledRow),
    resolve_borders(Active, PrevRow, FilledRow, PickNum, ResolvedRow),
    % Apply CA overlay if a Wolfram rule is active
    (   ca_rule(RuleNum)
    ->  apply_ca_overlay(RuleNum, PickNum, PrevRow, ResolvedRow, FinalRow)
    ;   FinalRow = ResolvedRow
    ),
    % Rules look at the pick just woven — what the weaver sees on the loom.
    update_bobbins(Sorted, Sorted, PrevRow, FinalRow, PickNum, Updated, SpawnReqs),
    apply_spawns(SpawnReqs, Updated, Spawned),
    gap_spawn(Spawned, FinalRow, PickNum, NewBobbins).

sort_bobbins_lr(Bs, Sorted) :-
    map_pairs_lr(Bs, Keyed),
    msort(Keyed, SKeyed),
    pairs_values(SKeyed, Sorted).

map_pairs_lr([], []).
map_pairs_lr([bobbin(Id, L, R, C, P, Ru)|Bs],
             [L-bobbin(Id, L, R, C, P, Ru)|Ks]) :-
    map_pairs_lr(Bs, Ks).

active_bobbins([], []).
active_bobbins([B|Bs], [B|As]) :-
    B = bobbin(_, L, R, _, _, _), L > 0, R >= L, !,
    active_bobbins(Bs, As).
active_bobbins([_|Bs], As) :-
    active_bobbins(Bs, As).

% ============================================================
%  BORDER RESOLUTION (slit / interlock)
% ============================================================

resolve_borders(Bobbins, PrevRow, FilledRow, PickNum, Resolved) :-
    find_border_positions(Bobbins, Borders),
    border_style(Style),
    apply_borders(Borders, Style, PrevRow, PickNum, FilledRow, Resolved).

find_border_positions([], []).
find_border_positions([_], []) :- !.
find_border_positions([B1, B2|Bs], Borders) :-
    B1 = bobbin(_, _, R1, _, _, _),
    B2 = bobbin(_, L2, _, _, _, _),
    (   R1 >= L2
    ->  BorderPos is (R1 + L2) // 2,
        Borders = [border(BorderPos, B1, B2)|More]
    ;   Borders = More
    ),
    find_border_positions([B2|Bs], More).

apply_borders([], _, _, _, Row, Row).
apply_borders([border(Pos, _, _)|Bs], slit, PR, PN, RowIn, RowOut) :- !,
    warp_width(W),
    (Pos >= 1, Pos =< W
    ->  set_nth1(Pos, RowIn, 0, RowMid)
    ;   RowMid = RowIn
    ),
    apply_borders(Bs, slit, PR, PN, RowMid, RowOut).
apply_borders([border(Pos, B1, B2)|Bs], interlock, PR, PN, RowIn, RowOut) :-
    warp_width(W),
    (   Pos >= 1, Pos =< W
    ->  (PN mod 2 =:= 0
        ->  B1 = bobbin(_, _, _, C, P, _)
        ;   B2 = bobbin(_, _, _, C, P, _)),
        cell_value(C, P, Val),
        set_nth1(Pos, RowIn, Val, RowMid)
    ;   RowMid = RowIn
    ),
    apply_borders(Bs, interlock, PR, PN, RowMid, RowOut).

set_nth1(1, [_|T], V, [V|T]) :- !.
set_nth1(N, [H|T], V, [H|T2]) :-
    N > 1, N1 is N - 1,
    set_nth1(N1, T, V, T2).

% ============================================================
%  CELLULAR AUTOMATA OVERLAY — Wolfram elementary CA on threads
% ============================================================
%
%  Operates at the thread level: each pick is one CA generation.
%  Reads 3-cell neighborhood from previous row, applies Wolfram rule
%  to determine alive/dead at each position. Bobbin territories define
%  WHERE color can exist; the CA carves the pattern WITHIN territories.
%
%  Territory edges (where CurRow transitions between 0 and non-zero)
%  are always kept alive — they act as seed points for the CA.  Interior
%  cells are governed purely by the Wolfram rule.  This lets classic CA
%  structures (fractal triangles, gliders, chaos) develop inward from
%  the boundaries instead of being reset every generation.

%% apply_ca_overlay(+RuleNum, +Pick, +PrevRow, +CurRow, -MaskedRow)
%  Walk positions 1..W, masking CurRow values based on CA rule applied
%  to PrevRow neighborhoods.
apply_ca_overlay(RuleNum, Pick, PrevRow, CurRow, MaskedRow) :-
    warp_width(W),
    ca_overlay_(1, W, RuleNum, Pick, PrevRow, CurRow, MaskedRow).

ca_overlay_(Pos, W, _, _, _, _, []) :- Pos > W, !.
ca_overlay_(Pos, W, RuleNum, Pick, PrevRow, CurRow, [MVal|Rest]) :-
    Pos =< W,
    nth1(Pos, CurRow, CurVal),
    (   CurVal =:= 0
    ->  MVal = 0  % bare warp stays bare
    ;   % Check if this position is a territory edge in CurRow:
        % a non-zero cell whose left or right neighbor is zero.
        PosL is Pos - 1, PosR is Pos + 1,
        (PosL >= 1 -> nth1(PosL, CurRow, CurL) ; CurL = 0),
        (PosR =< W -> nth1(PosR, CurRow, CurR) ; CurR = 0),
        (   (CurL =:= 0 ; CurR =:= 0)
        ->  MVal = CurVal  % Territory edge: seed point, always keep
        ;   % Interior: apply Wolfram CA rule
            ca_neighborhood(Pos, W, Pick, PrevRow, L, C, R),
            Index is L * 4 + C * 2 + R,
            Bit is (RuleNum >> Index) /\ 1,
            (Bit =:= 1 -> MVal = CurVal ; MVal = 0)
        )
    ),
    Pos1 is Pos + 1,
    ca_overlay_(Pos1, W, RuleNum, Pick, PrevRow, CurRow, Rest).

%% ca_neighborhood(+Pos, +W, +Pick, +PrevRow, -L, -C, -R)
%  Get binarized 3-cell neighborhood from PrevRow.
%  If weft_alternate is asserted and pick is even, flip L<->R.
ca_neighborhood(Pos, W, Pick, PrevRow, LOut, COut, ROut) :-
    PosL is Pos - 1,
    PosR is Pos + 1,
    (PosL >= 1 -> nth1(PosL, PrevRow, VL) ; VL = 0),
    nth1(Pos, PrevRow, VC),
    (PosR =< W -> nth1(PosR, PrevRow, VR) ; VR = 0),
    binarize(VL, BL), binarize(VC, BC), binarize(VR, BR),
    (   weft_alternate, Pick mod 2 =:= 0
    ->  LOut = BR, COut = BC, ROut = BL  % flip for weft direction
    ;   LOut = BL, COut = BC, ROut = BR
    ).

binarize(0, 0) :- !.
binarize(_, 1).

% Double each cell in a row: [a,b,c] -> [a,a,b,b,c,c]
% Maps each logical CA cell to 2 physical warp threads so that even a
% single-cell CA state spans 2 threads (minimum for tapestry structure).
double_row([], []).
double_row([V|Vs], [V,V|Ds]) :- double_row(Vs, Ds).

double_fabric(Fabric, Doubled) :-
    maplist(double_row, Fabric, Doubled).

% ============================================================
%  BOBBIN STATE UPDATE + EDGE BOUNCING
% ============================================================

%% update_bobbins(+Bobbins, +AllBobbins, +PrevRow, +CurRow, +Pick, -New, -SpawnReqs)
%  SpawnReqs: spawn(UpdatedParent, Act) for every spawn rule that fired,
%  in bobbin order then rule order.
update_bobbins([], _, _, _, _, [], []).
update_bobbins([B|Bs], All, PrevRow, CurRow, Pick, [NB|NBs], Reqs) :-
    update_one_bobbin(B, All, PrevRow, CurRow, Pick, NB, Acts),
    (   NB = bobbin(_, NL, _, _, _, _), NL > 0
    ->  findall(spawn(NB, A), member(A, Acts), BReqs)
    ;   BReqs = []  % a bobbin that died this pick spawns nothing
    ),
    update_bobbins(Bs, All, PrevRow, CurRow, Pick, NBs, RestReqs),
    append(BReqs, RestReqs, Reqs).

update_one_bobbin(bobbin(Id, L, R, Color, Pass, Rules),
                  _All, _PrevRow, _CurRow, _Pick,
                  bobbin(Id, L, R, Color, Pass, Rules), []) :-
    (L =< 0 ; R =< 0 ; L > R), !.  % dormant — unchanged
update_one_bobbin(bobbin(Id, L, R, Color, Pass, Rules),
                  All, _PrevRow, CurRow, Pick,
                  bobbin(Id, NL, NR, NColor, NPass, FinalRules), Spawns) :-
    L > 0, R >= L,
    % Conditions about other bobbins see everyone except this bobbin (by Id)
    Ctx = ctx(Id, All),
    apply_edge_rules(Rules, L, R, Color, Pass, Ctx, CurRow, Pick, false,
                     NL, NR, NColor, NPass, Hit, Spawns),
    % Edge bounce: if a move tried to cross a selvedge, mirror directional rules
    (   Hit == true, NL > 0
    ->  maplist(mirror_rule, Rules, FinalRules)
    ;   FinalRules = Rules
    ).

%% other_bobbins(+Ctx, -Others) — every bobbin except the one being updated
other_bobbins(ctx(Id, All), Others) :-
    exclude([bobbin(I, _, _, _, _, _)]>>(I == Id), All, Others).

%% mirror_rule(+Rule, -Mirrored)
%  Swap left<->right in directional actions for bouncing off edges.
mirror_rule(edge_rule(C, grow_left(N)),    edge_rule(C, grow_right(N))) :- !.
mirror_rule(edge_rule(C, grow_right(N)),   edge_rule(C, grow_left(N))) :- !.
mirror_rule(edge_rule(C, shrink_left(N)),  edge_rule(C, shrink_right(N))) :- !.
mirror_rule(edge_rule(C, shrink_right(N)), edge_rule(C, shrink_left(N))) :- !.
mirror_rule(edge_rule(C, shift_left(N)),   edge_rule(C, shift_right(N))) :- !.
mirror_rule(edge_rule(C, shift_right(N)),  edge_rule(C, shift_left(N))) :- !.
mirror_rule(edge_rule(C, spawn_left(N)),   edge_rule(C, spawn_right(N))) :- !.
mirror_rule(edge_rule(C, spawn_right(N)),  edge_rule(C, spawn_left(N))) :- !.
mirror_rule(R, R).

%% apply_edge_rules: fire matching rules in sequence.
%  Each move is clamped immediately, so every later rule sees a real
%  territory. Hit records whether any move tried to cross a selvedge.
%  Spawns collects the spawn actions that fired, in rule order.
apply_edge_rules([], L, R, C, P, _, _, _, H, L, R, C, P, H, []).
apply_edge_rules([edge_rule(Cond, Act)|Rs], L, R, C, P, Ctx, Row, Pick,
                 H0, NL, NR, NC, NP, H, Spawns) :-
    (   condition_met(Cond, L, R, C, P, Ctx, Row, Pick)
    ->  once(apply_action(Act, L, R, C, P, L0, R0, C1, P1)),
        clamp_territory(Act, L0, R0, L1, R1, H0, H1),
        (is_spawn_action(Act) -> Spawns = [Act|Spawns1] ; Spawns = Spawns1)
    ;   L1 = L, R1 = R, C1 = C, P1 = P, H1 = H0, Spawns = Spawns1
    ),
    (   L1 =:= 0
    ->  NL = 0, NR = 0, NC = C1, NP = P1, H = H1, Spawns1 = []  % died: stays dormant
    ;   apply_edge_rules(Rs, L1, R1, C1, P1, Ctx, Row, Pick, H1, NL, NR, NC, NP, H, Spawns1)
    ).

%% clamp_territory(+Act, +L0, +R0, -L, -R, +HitIn, -HitOut)
%  Keep the territory on the warp and at least 1 thread wide.
clamp_territory(die, _, _, 0, 0, H, H) :- !.
clamp_territory(_, L0, R0, L, R, H0, H) :-
    warp_width(W),
    L1 is max(1, min(W, L0)),
    R1 is min(W, max(1, R0)),
    (R1 >= L1 -> L = L1, R = R1 ; L = L1, R = L1),
    ((L0 < 1 ; R0 > W) -> H = true ; H = H0).

% --- Conditions ---

condition_met(always, _, _, _, _, _, _, _).

condition_met(neighbor_is(TC), _, R, _, _, Ctx, _, _) :-
    warp_width(W), RN is R + 1, RN =< W,
    other_bobbins(Ctx, Others),
    member(bobbin(_, OL, OR, TC, _, _), Others),
    OL =< RN, OR >= RN.

condition_met(below_edge_is(TC), L, R, _, _, _, Row, _) :-
    warp_width(W),
    BR is R + 1,
    (   BR =< W
    ->  nth1(BR, Row, V), color_of_cell(V, TC)
    ;   BL is L - 1, BL >= 1,
        nth1(BL, Row, V2), color_of_cell(V2, TC)
    ).

condition_met(at_warp_edge, L, R, _, _, _, _, _) :-
    warp_width(W), (L =:= 1 ; R =:= W).

condition_met(territory_wider(N), L, R, _, _, _, _, _) :-
    R - L + 1 > N.

condition_met(territory_narrower(N), L, R, _, _, _, _, _) :-
    R - L + 1 < N.

condition_met(pick_mod(M, Rem), _, _, _, _, _, _, Pick) :-
    Pick mod M =:= Rem.

%% neighbor_count(Op, N) — count active bobbins adjacent (within 2 threads)
condition_met(neighbor_count(Op, N), L, R, _, _, Ctx, _, _) :-
    other_bobbins(Ctx, Others),
    count_neighbors(L, R, Others, Count),
    compare_op(Op, Count, N).

count_neighbors(L, R, Bobbins, Count) :-
    count_neighbors_(Bobbins, L, R, 0, Count).
count_neighbors_([], _, _, Acc, Acc) :- !.
count_neighbors_([bobbin(_, BL, BR, _, _, _)|Bs], L, R, Acc, Count) :-
    BL > 0, BR >= BL,
    (BR >= L - 2, BL =< R + 2),  % within 2 threads
    !, Acc1 is Acc + 1,
    count_neighbors_(Bs, L, R, Acc1, Count).
count_neighbors_([_|Bs], L, R, Acc, Count) :-
    count_neighbors_(Bs, L, R, Acc, Count).

compare_op(<, A, B) :- A < B.
compare_op(>, A, B) :- A > B.
compare_op(=, A, B) :- A =:= B.

%% gap_nearby(Side, MinWidth) — is there an empty gap of MinWidth on given side
condition_met(gap_nearby(left, MinW), L, _, _, _, Ctx, _, _) :-
    GapR is L - 1, GapL is L - MinW,
    GapL >= 1,
    other_bobbins(Ctx, Others),
    \+ overlaps_any(GapL, GapR, Others).
condition_met(gap_nearby(right, MinW), _, R, _, _, Ctx, _, _) :-
    GapL is R + 1, GapR is R + MinW,
    warp_width(W), GapR =< W,
    other_bobbins(Ctx, Others),
    \+ overlaps_any(GapL, GapR, Others).

%% alive_ratio(Op, Pct) — percentage of warp covered by active bobbins
condition_met(alive_ratio(Op, Pct), _, _, _, _, ctx(_, All), _, _) :-
    warp_width(W),
    total_coverage(All, 0, Cov),
    Ratio is (Cov * 100) / W,
    compare_op(Op, Ratio, Pct).

total_coverage([], Acc, Acc) :- !.
total_coverage([bobbin(_, L, R, _, _, _)|Bs], Acc, Cov) :-
    L > 0, R >= L, !,
    Width is R - L + 1,
    Acc1 is Acc + Width,
    total_coverage(Bs, Acc1, Cov).
total_coverage([_|Bs], Acc, Cov) :-
    total_coverage(Bs, Acc, Cov).

%% prev_edge_alive(Side) — is the thread just beyond the territory edge non-zero
%%  in the pick just woven? Lets bobbins grow toward active CA areas.
condition_met(prev_edge_alive(left), L, _, _, _, _, Row, _) :-
    Pos is L - 1,
    Pos >= 1,
    nth1(Pos, Row, V), V =\= 0.
condition_met(prev_edge_alive(right), _, R, _, _, _, Row, _) :-
    warp_width(W),
    Pos is R + 1,
    Pos =< W,
    nth1(Pos, Row, V), V =\= 0.

%% territory_density(Op, Pct) — percentage of positions within [L,R] that were
%%  non-zero in the pick just woven. Lets bobbins react to CA fill level.
condition_met(territory_density(Op, Pct), L, R, _, _, _, Row, _) :-
    count_density_(Row, L, R, 1, 0, 0, Alive, Total),
    Total > 0,
    Density is (Alive * 100) / Total,
    compare_op(Op, Density, Pct).

count_density_([], _, _, _, A, T, A, T) :- !.
count_density_(_, L, R, Pos, A, T, A, T) :- Pos > R, !.
count_density_([V|Vs], L, R, Pos, A, T, AOut, TOut) :-
    Pos1 is Pos + 1,
    (   Pos >= L, Pos =< R
    ->  T1 is T + 1,
        (V =\= 0 -> A1 is A + 1 ; A1 = A),
        count_density_(Vs, L, R, Pos1, A1, T1, AOut, TOut)
    ;   count_density_(Vs, L, R, Pos1, A, T, AOut, TOut)
    ).

%% neighbor_width(Op, N) — find the nearest active bobbin on either side,
%%  compare its width to N. Lets bobbins react to neighbor size.
condition_met(neighbor_width(Op, N), L, R, _, _, Ctx, _, _) :-
    other_bobbins(Ctx, Others),
    nearest_neighbor_width(L, R, Others, Width),
    compare_op(Op, Width, N).

nearest_neighbor_width(L, R, All, Width) :-
    nearest_neighbor_width_(All, L, R, 999999, 999999, Width).
nearest_neighbor_width_([], _, _, _, BestW, BestW) :- !.
nearest_neighbor_width_([B|Bs], L, R, BestDist, BestW, Width) :-
    (   B = bobbin(_, BL, BR, _, _, _),
        BL > 0, BR >= BL
    ->  BW is BR - BL + 1,
        (BR < L -> Dist is L - BR ; (BL > R -> Dist is BL - R ; Dist = 0)),
        (Dist < BestDist -> NewDist = Dist, NewW = BW ; NewDist = BestDist, NewW = BestW)
    ;   NewDist = BestDist, NewW = BestW
    ),
    nearest_neighbor_width_(Bs, L, R, NewDist, NewW, Width).

color_of_cell(1, black). color_of_cell(3, black).
color_of_cell(2, white). color_of_cell(4, white).

% --- Actions ---

apply_action(grow_left(N), L, R, C, P, NL, R, C, P)     :- NL is L - N.
apply_action(grow_right(N), L, R, C, P, L, NR, C, P)    :- NR is R + N.
apply_action(shrink_left(N), L, R, C, P, NL, R, C, P)   :- NL is L + N.
apply_action(shrink_right(N), L, R, C, P, L, NR, C, P)  :- NR is R - N.
apply_action(grow_both(N), L, R, C, P, NL, NR, C, P)    :- NL is L - N, NR is R + N.
apply_action(shrink_both(N), L, R, C, P, NL, NR, C, P)  :- NL is L + N, NR is R - N.
apply_action(shift_left(N), L, R, C, P, NL, NR, C, P)   :- NL is L - N, NR is R - N.
apply_action(shift_right(N), L, R, C, P, NL, NR, C, P)  :- NL is L + N, NR is R + N.
apply_action(flip_color, L, R, black, P, L, R, white, P).
apply_action(flip_color, L, R, white, P, L, R, black, P).
apply_action(toggle_pass, L, R, C, full, L, R, C, half).
apply_action(toggle_pass, L, R, C, half, L, R, C, full).
% Spawn actions are no-ops for territory — handled separately
apply_action(spawn_left(_), L, R, C, P, L, R, C, P).
apply_action(spawn_right(_), L, R, C, P, L, R, C, P).
% Die: set territory to 0,0 — bobbin goes dormant
apply_action(die, _, _, C, P, 0, 0, C, P).

% ============================================================
%  SPAWNING — Rule-driven bobbin creation
% ============================================================
%
%  Spawn actions in edge rules (spawn_left(W), spawn_right(W))
%  create new bobbins adjacent to the parent. They fire in rule
%  order like any other rule; the child is placed after all
%  bobbins are updated, beside the parent's new territory.
%  Respects max_bobbins cap.

is_spawn_action(spawn_left(_)).
is_spawn_action(spawn_right(_)).
is_death_action(die).

%% apply_spawns(+Requests, +Bobbins, -Result)
%  Process spawn requests, creating new bobbins up to the cap.
apply_spawns([], Bobbins, Bobbins).
apply_spawns([spawn(Parent, Act)|Rest], Bobbins, Result) :-
    max_bobbins(Cap),
    length(Bobbins, CurCount),
    (   CurCount < Cap
    ->  Parent = bobbin(_PId, PL, PR, PC, PP, PRules),
        make_spawn(Act, PL, PR, PC, PP, NewL, NewR, NewC, NewP),
        warp_width(W),
        NL is max(1, NewL), NR is min(W, NewR),
        (   NR >= NL,
            \+ overlaps_any(NL, NR, Bobbins)  % don't spawn on top of others
        ->  NextId is CurCount + 1,
            inherit_from_parent(PRules, NewRules),
            append(Bobbins, [bobbin(NextId, NL, NR, NewC, NewP, NewRules)], Bobbins1),
            apply_spawns(Rest, Bobbins1, Result)
        ;   apply_spawns(Rest, Bobbins, Result)
        )
    ;   Result = Bobbins  % at cap, ignore remaining spawns
    ).

%% make_spawn(+Action, +ParentL, +ParentR, +ParentC, +ParentP,
%%            -NewL, -NewR, -NewC, -NewP)
make_spawn(spawn_left(W), PL, _PR, PC, PP, NL, NR, NC, PP) :-
    NR is PL - 1, NL is NR - W + 1,
    flip_color_val(PC, NC).
make_spawn(spawn_right(W), _PL, PR, PC, PP, NL, NR, NC, PP) :-
    NL is PR + 1, NR is NL + W - 1,
    flip_color_val(PC, NC).

%% overlaps_any(+L, +R, +Bobbins)
%  True if the range L..R overlaps any active bobbin's territory.
overlaps_any(L, R, Bobbins) :-
    member(bobbin(_, BL, BR, _, _, _), Bobbins),
    BL > 0, BR >= BL,
    L =< BR, R >= BL, !.

flip_color_val(black, white). flip_color_val(white, black).

% ============================================================
%  GAP SPAWNING — Game of Life style automatic birth
% ============================================================
%
%  After rule-driven spawns, scan for empty gaps in the warp.
%  A gap of 3+ threads flanked by active bobbins on both sides births
%  a new bobbin — like GoL's "3 neighbors = birth".
%  The child copies its left neighbour (opposite colour, same pass/rules).
%  Controlled by gap_spawn_enabled/0 (dynamic flag).

:- dynamic gap_spawn_enabled/0.
gap_spawn_enabled.  % enabled by default

%% gap_spawn(+Bobbins, +Row, +Pick, -Result)
%  Find gaps in the current row and possibly spawn bobbins in them.
gap_spawn(Bobbins, _Row, _Pick, Bobbins) :-
    \+ gap_spawn_enabled, !.
gap_spawn(Bobbins, _Row, Pick, Result) :-
    max_bobbins(Cap),
    length(Bobbins, Cur),
    (   Cur >= Cap
    ->  Result = Bobbins
    ;   sort_bobbins_lr(Bobbins, Sorted),
        active_bobbins(Sorted, Active),
        find_gaps(Active, Gaps),
        pick_gap_spawns(Gaps, Active, Pick, Cap, Cur, Bobbins, Result)
    ).

%% find_gaps(+SortedActive, -Gaps)
%  Find empty regions between active bobbins (and at edges).
find_gaps([], []) :- !.
find_gaps(Active, Gaps) :-
    warp_width(W),
    find_gaps_(Active, 1, W, Gaps).

find_gaps_([], CurPos, W, Gaps) :-
    (   CurPos =< W
    ->  GapW is W - CurPos + 1,
        (GapW >= 3 -> Gaps = [gap(CurPos, W, none, none)] ; Gaps = [])
    ;   Gaps = []
    ), !.
find_gaps_([bobbin(_, L, R, C, P, Rules)|Bs], CurPos, W, Gaps) :-
    L > 0, R >= L,
    (   L > CurPos
    ->  GapW is L - CurPos,
        (   GapW >= 3
        ->  GapEnd is L - 1,
            Gaps = [gap(CurPos, GapEnd, none, bobbin_info(C, P, Rules))|MoreGaps]
        ;   Gaps = MoreGaps
        )
    ;   Gaps = MoreGaps
    ),
    NextPos is R + 1,
    find_gaps_rest(Bs, bobbin_info(C, P, Rules), NextPos, W, MoreGaps), !.
find_gaps_([_|Bs], CurPos, W, Gaps) :-
    find_gaps_(Bs, CurPos, W, Gaps).

find_gaps_rest([], LeftInfo, CurPos, W, Gaps) :-
    (   CurPos =< W
    ->  GapW is W - CurPos + 1,
        (GapW >= 3 -> Gaps = [gap(CurPos, W, LeftInfo, none)] ; Gaps = [])
    ;   Gaps = []
    ), !.
find_gaps_rest([bobbin(_, L, R, C, P, Rules)|Bs], LeftInfo, CurPos, W, Gaps) :-
    L > 0, R >= L,
    (   L > CurPos
    ->  GapW is L - CurPos,
        (   GapW >= 3
        ->  GapEnd is L - 1,
            RightInfo = bobbin_info(C, P, Rules),
            Gaps = [gap(CurPos, GapEnd, LeftInfo, RightInfo)|MoreGaps]
        ;   Gaps = MoreGaps
        )
    ;   Gaps = MoreGaps
    ),
    % A territory nested inside an earlier one does not end the covered run
    (   R + 1 > CurPos
    ->  NextPos is R + 1, NextInfo = bobbin_info(C, P, Rules)
    ;   NextPos = CurPos, NextInfo = LeftInfo
    ),
    find_gaps_rest(Bs, NextInfo, NextPos, W, MoreGaps), !.
find_gaps_rest([_|Bs], LeftInfo, CurPos, W, Gaps) :-
    find_gaps_rest(Bs, LeftInfo, CurPos, W, Gaps).

%% pick_gap_spawns(+Gaps, +Active, +Pick, +Cap, +Cur, +Bobbins, -Result)
%  Every gap of 3+ threads flanked by 2 active bobbins gets a child.
%  Deterministic, so a weaver can follow it from the printed instructions.
pick_gap_spawns([], _, _, _, _, Bs, Bs) :- !.
pick_gap_spawns(_, _, _, Cap, Cur, Bs, Bs) :- Cur >= Cap, !.
pick_gap_spawns([gap(GL, GR, LeftInfo, RightInfo)|Gs], Active, Pick, Cap, Cur, Bs, Result) :-
    % Only spawn in gaps flanked on both sides
    LeftInfo \= none, RightInfo \= none,
    !,
    GapW is GR - GL + 1,
    % Place child in center of gap, width = gap/2 (at least 3)
    ChildW is max(3, GapW // 2),
    Mid is (GL + GR) // 2,
    CL is max(GL, Mid - ChildW // 2),
    CR is min(GR, CL + ChildW - 1),
    NextId is Cur + 1,
    % Opposite colour of the left neighbour, same pass, same rules
    LeftInfo = bobbin_info(LC, LP, LRules),
    flip_color_val(LC, ChildC),
    inherit_from_parent(LRules, ChildRules),
    NewBobbin = bobbin(NextId, CL, CR, ChildC, LP, ChildRules),
    append(Bs, [NewBobbin], Bs1),
    Cur1 is Cur + 1,
    pick_gap_spawns(Gs, Active, Pick, Cap, Cur1, Bs1, Result).
pick_gap_spawns([_|Gs], Active, Pick, Cap, Cur, Bs, Result) :-
    pick_gap_spawns(Gs, Active, Pick, Cap, Cur, Bs, Result).

% ============================================================
%  RULE INHERITANCE FOR SPAWNS
% ============================================================

%% inherit_from_parent(+ParentRules, -ChildRules)
%  In uniform mode the child gets the shared uniform rules (as printed);
%  otherwise an exact copy of the parent's current rules. No mutation —
%  the weaver must be able to predict every child.
inherit_from_parent(_, Rules) :-
    uniform_mode, uniform_rule(Rules), !.
inherit_from_parent(ParentRules, ParentRules).

% ============================================================
%  FULL FABRIC GENERATION
% ============================================================

weave(NumPicks, Fabric) :-
    init_bobbins(Bobbins),
    empty_row(Init),
    weave_rows(NumPicks, Bobbins, Init, 1, [], Fabric).

weave_capturing(NumPicks, Config, Fabric) :-
    init_bobbins(Bobbins),
    bobbins_to_config(Bobbins, Config),
    empty_row(Init),
    weave_rows(NumPicks, Bobbins, Init, 1, [], Fabric).

weave_with_config(Config, NumPicks, Fabric) :-
    init_bobbins_from_config(Config, Bobbins),
    empty_row(Init),
    weave_rows(NumPicks, Bobbins, Init, 1, [], Fabric).

empty_row(Row) :-
    warp_width(W), length(Row, W), maplist(=(0), Row).

weave_rows(0, _, _, _, Acc, Fabric) :- !, reverse(Acc, Fabric).
weave_rows(N, Bobbins, PrevRow, Pick, Acc, Fabric) :-
    N > 0,
    weave_pick(Bobbins, PrevRow, Pick, NewRow, NewBobbins),
    N1 is N - 1, Pick1 is Pick + 1,
    weave_rows(N1, NewBobbins, NewRow, Pick1, [NewRow|Acc], Fabric).

% ============================================================
%  EVALUATION — single-pass cell counting for efficiency
% ============================================================

%% evaluate_fabric(+Fabric, -Score, -Details)
evaluate_fabric(Fabric, Score, Details) :-
    count_cells(Fabric, NBlack, NWhite, NFull, NHalf, NZero, Total),
    bw_ratio_score(NBlack, NWhite, BWScore),
    pass_variety_score(NFull, NHalf, PassScore),
    negative_space_score(NZero, Total, NegScore),
    edge_complexity_score(Fabric, EdgeScore),
    growth_score(Fabric, GrowthScore),
    Details = details(bw_ratio=BWScore, pass_variety=PassScore,
                      edge_complexity=EdgeScore, growth=GrowthScore,
                      negative_space=NegScore),
    Score is BWScore * 0.20 + PassScore * 0.15 + EdgeScore * 0.25
           + GrowthScore * 0.20 + NegScore * 0.20.

%% count_cells(+Fabric, -NBlack, -NWhite, -NFull, -NHalf, -NZero, -Total)
%  Single pass over all cells to collect all counts.
count_cells(Fabric, NBlack, NWhite, NFull, NHalf, NZero, Total) :-
    count_cells_(Fabric, 0, 0, 0, 0, 0, 0,
                 NBlack, NWhite, NFull, NHalf, NZero, Total).

count_cells_([], B, W, F, H, Z, T, B, W, F, H, Z, T).
count_cells_([Row|Rows], BA, WA, FA, HA, ZA, TA,
             BO, WO, FO, HO, ZO, TO) :-
    count_row_(Row, BA, WA, FA, HA, ZA, TA,
               B1, W1, F1, H1, Z1, T1),
    count_cells_(Rows, B1, W1, F1, H1, Z1, T1,
                 BO, WO, FO, HO, ZO, TO).

count_row_([], B, W, F, H, Z, T, B, W, F, H, Z, T) :- !.
count_row_([0|Cs], B, W, F, H, Z, T, BO, WO, FO, HO, ZO, TO) :- !,
    Z1 is Z + 1, T1 is T + 1,
    count_row_(Cs, B, W, F, H, Z1, T1, BO, WO, FO, HO, ZO, TO).
count_row_([1|Cs], B, W, F, H, Z, T, BO, WO, FO, HO, ZO, TO) :- !,
    B1 is B + 1, F1 is F + 1, T1 is T + 1,
    count_row_(Cs, B1, W, F1, H, Z, T1, BO, WO, FO, HO, ZO, TO).
count_row_([2|Cs], B, W, F, H, Z, T, BO, WO, FO, HO, ZO, TO) :- !,
    W1 is W + 1, F1 is F + 1, T1 is T + 1,
    count_row_(Cs, B, W1, F1, H, Z, T1, BO, WO, FO, HO, ZO, TO).
count_row_([3|Cs], B, W, F, H, Z, T, BO, WO, FO, HO, ZO, TO) :- !,
    B1 is B + 1, H1 is H + 1, T1 is T + 1,
    count_row_(Cs, B1, W, F, H1, Z, T1, BO, WO, FO, HO, ZO, TO).
count_row_([4|Cs], B, W, F, H, Z, T, BO, WO, FO, HO, ZO, TO) :- !,
    W1 is W + 1, H1 is H + 1, T1 is T + 1,
    count_row_(Cs, B, W1, F, H1, Z, T1, BO, WO, FO, HO, ZO, TO).
count_row_([_|Cs], B, W, F, H, Z, T, BO, WO, FO, HO, ZO, TO) :-
    T1 is T + 1,
    count_row_(Cs, B, W, F, H, Z, T1, BO, WO, FO, HO, ZO, TO).

%% bw_ratio_score(+NBlack, +NWhite, -Score)
bw_ratio_score(NBlack, NWhite, Score) :-
    Colored is NBlack + NWhite,
    (   Colored =:= 0 -> Score = 0.0
    ;   Ratio is NBlack / Colored,
        Dev is abs(Ratio - 0.5),
        (   Dev >= 0.05, Dev =< 0.2
        ->  Raw is 1.0 - (Dev - 0.1) * 5.0
        ;   Dev < 0.05
        ->  Raw = 0.6
        ;   Raw is max(0.0, 1.0 - Dev * 3.0)
        ),
        Score is max(0.0, min(1.0, Raw))
    ).

%% pass_variety_score(+NFull, +NHalf, -Score)
pass_variety_score(NFull, NHalf, Score) :-
    Total is NFull + NHalf,
    (   Total =:= 0 -> Score = 0.0
    ;   Ratio is NFull / Total,
        (   Ratio >= 0.3, Ratio =< 0.7
        ->  Score is 1.0 - abs(Ratio - 0.5) * 3.0
        ;   Score is max(0.0, 0.5 - abs(Ratio - 0.5) * 2.0)
        )
    ).

%% negative_space_score(+NZero, +Total, -Score)
negative_space_score(NZero, Total, Score) :-
    (   Total =:= 0 -> Score = 0.0
    ;   ZR is NZero / Total,
        (   ZR >= 0.15, ZR =< 0.45
        ->  Raw is 1.0 - abs(ZR - 0.30) * 4.0
        ;   ZR < 0.15
        ->  Raw is ZR * 5.0
        ;   Raw is max(0.0, 1.0 - (ZR - 0.45) * 3.0)
        ),
        Score is max(0.0, min(1.0, Raw))
    ).

%% edge_complexity_score(+Fabric, -Score)
%  Sample boundary positions from a subset of rows for speed.
edge_complexity_score(Fabric, Score) :-
    length(Fabric, NRows),
    (   NRows < 3 -> Score = 0.5
    ;   % Sample up to 50 row pairs for speed with large fabrics
        sample_boundary_pairs(Fabric, NRows, 50, 0, 0, ShiftSum, PairCount),
        (PairCount =:= 0 -> Score = 0.3
        ;   Jaggedness is ShiftSum / PairCount,
            (   Jaggedness >= 0.2, Jaggedness =< 0.7
            ->  Raw is 1.0 - abs(Jaggedness - 0.45) * 3.0
            ;   Raw is max(0.0, Jaggedness * 1.5)
            ),
            Score is max(0.0, min(1.0, Raw))
        )
    ).

%% sample_boundary_pairs(+Fabric, +NRows, +MaxSamples, +SAcc, +PAcc, -SOut, -POut)
sample_boundary_pairs(_, NRows, _, S, P, S, P) :- NRows < 2, !.
sample_boundary_pairs(_, _, 0, S, P, S, P) :- !.
sample_boundary_pairs(Fabric, NRows, Remaining, SAcc, PAcc, SOut, POut) :-
    Remaining > 0,
    MaxIdx is NRows - 1,
    random_between(1, MaxIdx, Idx),
    Idx2 is Idx + 1,
    nth1(Idx, Fabric, Row1),
    nth1(Idx2, Fabric, Row2),
    row_bw_boundaries(Row1, 1, B1),
    row_bw_boundaries(Row2, 1, B2),
    compare_boundary_sets(B1, B2, Shift, Pairs),
    S1 is SAcc + Shift, P1 is PAcc + Pairs,
    R1 is Remaining - 1,
    sample_boundary_pairs(Fabric, NRows, R1, S1, P1, SOut, POut).

row_bw_boundaries([_], _, []) :- !.
row_bw_boundaries([], _, []) :- !.
row_bw_boundaries([A, B|Rest], Pos, Bounds) :-
    Pos1 is Pos + 1,
    cell_class(A, CA), cell_class(B, CB),
    (   CA \= CB
    ->  Bounds = [Pos|More], row_bw_boundaries([B|Rest], Pos1, More)
    ;   row_bw_boundaries([B|Rest], Pos1, Bounds)
    ).

cell_class(0, bare). cell_class(1, black). cell_class(2, white).
cell_class(3, black). cell_class(4, white).

compare_boundary_sets([], _, 0, 0).
compare_boundary_sets([P|Ps], B2, TotalShift, TotalPairs) :-
    min_dist_to_set(P, B2, Dist),
    compare_boundary_sets(Ps, B2, RS, RP),
    TotalShift is Dist + RS,
    TotalPairs is 1 + RP.

min_dist_to_set(_, [], 5.0).
min_dist_to_set(P, [Q|Qs], MinDist) :-
    D is abs(P - Q),
    min_dist_to_set(P, Qs, Rest),
    warp_width(W),
    Norm is D / max(1, W),
    MinDist is min(Norm, Rest).

%% growth_score(+Fabric, -Score)
growth_score(Fabric, Score) :-
    maplist(row_coverage, Fabric, Covs),
    (   Covs = [] -> Score = 0.0
    ;   sum_list(Covs, Sum), length(Covs, N), Mean is Sum / N,
        maplist(sq_diff(Mean), Covs, SDs),
        sum_list(SDs, SqSum),
        StdDev is sqrt(SqSum / N),
        warp_width(W), NSD is StdDev / W,
        (   NSD >= 0.05, NSD =< 0.3
        ->  Score is min(1.0, NSD * 4.0)
        ;   Score is max(0.0, NSD * 2.0)
        )
    ).

row_coverage(Row, Cov) :-
    row_coverage_(Row, 0, Cov).
row_coverage_([], A, A) :- !.
row_coverage_([0|Cs], A, R) :- !, row_coverage_(Cs, A, R).
row_coverage_([_|Cs], A, R) :- A1 is A + 1, row_coverage_(Cs, A1, R).

sq_diff(Mean, X, D) :- D is (X - Mean) * (X - Mean).

% ============================================================
%  DISPLAY
% ============================================================

display_fabric(Fabric) :-
    reverse(Fabric, TopDown),  % pick 1 at the bottom
    double_fabric(TopDown, Doubled),
    nl, write('  WOVEN AUTOMATA v2 — B&W Pattern'), nl,
    warp_width(W), W2 is W * 2, length(Fabric, NP),
    format('  (~w logical threads x2 = ~w physical, ~w picks)~n~n', [W, W2, NP]),
    maplist(display_row, Doubled), nl.

display_row(Row) :-
    write('  '), maplist(display_cell, Row), nl.

display_cell(0) :- write('\u00b7').   % ·
display_cell(1) :- write('\u2588').   % █
display_cell(2) :- write('\u2591').   % ░
display_cell(3) :- write('\u2592').   % ▒
display_cell(4) :- write('\u2593').   % ▓
display_cell(_) :- write('?').

% ============================================================
%  HUMAN-READABLE INSTRUCTIONS
% ============================================================

print_instructions(Bobbins) :-
    nl, write('=== WEAVING INSTRUCTIONS ==='), nl, nl,
    warp_width(W), num_picks(NP),
    format('Warp: ~w thread positions, numbered 1 to ~w from the left~n', [W, W]),
    format('      (the .ppm image draws each position 2 pixels wide)~n'),
    format('Picks: ~w (pick 1 is the bottom row)~n', [NP]),
    active_bobbins(Bobbins, Active),
    length(Active, NB), format('Active bobbins: ~w~n', [NB]),
    border_style(BS), format('Border style: ~w~n', [BS]),
    format('Yarn: full pass = solid black / white,~n'),
    format('      half pass = half-tone yarn (dark grey / light grey)~n~n'),
    maplist(print_bobbin_instr, Active),
    print_pick_procedure(Bobbins).

print_bobbin_instr(bobbin(Id, L, R, Color, Pass, Rules)) :-
    Width is R - L + 1,
    format('Bobbin #~w:~n', [Id]),
    format('  Territory: threads ~w to ~w (~w threads)~n', [L, R, Width]),
    format('  Color: ~w, Pass: ~w~n', [Color, Pass]),
    format('  Rules (checked after each pick, top to bottom):~n'),
    maplist(print_edge_rule, Rules), nl.

print_edge_rule(edge_rule(Cond, Action)) :-
    cond_text(Cond, CT), act_text(Action, AT),
    format('    When ~w -> ~w~n', [CT, AT]).

%% print_pick_procedure(+Bobbins) — the per-pick steps weave_pick/5 performs,
%  written so a weaver can follow them by hand.
print_pick_procedure(Bobbins) :-
    write('=== EVERY PICK, IN THIS ORDER ==='), nl,
    write('Before pick 1, every thread counts as bare.'), nl, nl,
    write('1. LAY OUT. Each active bobbin covers its territory.'), nl,
    write('   Put the active bobbins in order of their left end (same left'), nl,
    write('   end: lower number first). Where territories overlap, the one'), nl,
    write('   earlier in that order covers the shared threads. For each'), nl,
    write('   bobbin and the NEXT one in that order only: if they overlap,'), nl,
    write('   the thread (right end of first + left end of next) // 2'), nl,
    border_style(BS),
    (   BS == slit
    ->  write('   is left bare (slit).'), nl
    ;   write('   is woven by the left bobbin on even picks and by the right'), nl,
        write('   bobbin on odd picks (interlock).'), nl
    ),
    nl,
    (ca_rule(CA) -> print_ca_step(CA) ; write('2. THREAD PATTERN. None: weave every thread from step 1.'), nl, nl),
    write('3. UPDATE TERRITORIES, looking at the pick you just finished:'), nl,
    write('   - "woven" means the thread carries weft (any colour, any pass);'), nl,
    write('     "density" is the share of the territory''s threads that are woven.'), nl,
    write('   - Go through each bobbin''s rules top to bottom; each rule sees the'), nl,
    write('     territory as already changed by the rules above it.'), nl,
    write('   - Rules about other bobbins (never the bobbin itself) use their'), nl,
    write('     territories, colours and passes from before this update.'), nl,
    write('   - Do the bobbins in the order of step 1.'), nl,
    write('   - A territory never goes past a selvedge and is never narrower'), nl,
    write('     than 1 thread (if a shrink would make it vanish, keep just its'), nl,
    write('     left-end thread). If a move would cross a selvedge, stop at the'), nl,
    write('     selvedge. Each pick where that happened, swap left and right in'), nl,
    write('     that bobbin''s actions, starting from the next pick (grow right'), nl,
    write('     <-> grow left, shrink left <-> shrink right, shift/spawn likewise;'), nl,
    write('     hitting a selvedge again swaps them back). Conditions never swap.'), nl,
    write('   - A bobbin that dies stops for good; its remaining rules are'), nl,
    write('     skipped.'), nl,
    write('   - A "spawn" rule that fires is noted (with the side it says now);'), nl,
    write('     the new bobbin is placed in step 4.'), nl, nl,
    max_bobbins(Cap), length(Bobbins, NAll),
    Room is max(0, Cap - NAll), First is NAll + 1,
    format('4. NEW BOBBINS (at most ~w new bobbins during the whole weave):~n', [Room]),
    write('   a) noted spawns, in the order they were noted: the new bobbin'), nl,
    write('      goes directly beside its parent''s updated territory (cut off'), nl,
    write('      at the selvedge), only if none of its threads is in an active'), nl,
    write('      territory (new bobbins included). Opposite colour of the'), nl,
    write('      parent, same pass. A parent that died spawns nothing.'), nl,
    write('   b) then, every gap of 3 or more uncovered threads between two'), nl,
    write('      active bobbins gets a new bobbin: width = max(3, gap // 2),'), nl,
    write('      starting at (gap start + gap end) // 2 - width // 2; opposite'), nl,
    write('      colour to the bobbin on its left, same pass as that bobbin.'), nl,
    (   uniform_mode
    ->  write('   New bobbins get the same rules as printed above (unswapped).'), nl
    ;   write('   New bobbins copy the rules of their parent / left neighbour'), nl,
        write('   as they currently are (including any left/right swaps).'), nl
    ),
    Second is First + 1,
    format('   New bobbins are numbered ~w, ~w, ... in the order they are added.~n',
           [First, Second]),
    nl, write('=== REPEAT FOR EVERY PICK ==='), nl, nl.

print_ca_step(Rule) :-
    format('2. THREAD PATTERN (cellular automaton rule ~w).~n', [Rule]),
    write('   Always weave a thread from step 1 that has a bare thread or a'), nl,
    write('   selvedge right next to it (the two ends of every woven run).'), nl,
    write('   For every other thread, look at the pick directly below: the'), nl,
    write('   thread to its left, the thread itself and the thread to its right'), nl,
    write('   (# = woven, . = bare, off the warp = bare), then:'), nl,
    forall(( between(0, 7, K), Idx is 7 - K ),
           (   ca_pattern(Idx, Pat),
               (   (Rule >> Idx) /\ 1 =:= 1
               ->  Do = 'weave it'
               ;   Do = 'leave it bare'
               ),
               format('       ~w  -> ~w~n', [Pat, Do])
           )),
    (   weft_alternate
    ->  write('   On even-numbered picks swap left and right before using the'), nl,
        write('   table (read the three threads below right-to-left).'), nl
    ;   true
    ),
    nl.

ca_pattern(Idx, Pat) :-
    L is (Idx >> 2) /\ 1, C is (Idx >> 1) /\ 1, R is Idx /\ 1,
    maplist([B, Ch]>>(B =:= 1 -> Ch = '#' ; Ch = '.'), [L, C, R], Chs),
    atomic_list_concat(Chs, Pat).

op_text(<, 'less than').
op_text(>, 'more than').
op_text(=, 'exactly').

cond_text(always, 'every pick').
cond_text(neighbor_is(C), T) :-
    format(atom(T), 'the thread just right of the territory is in the territory of another ~w bobbin', [C]).
cond_text(below_edge_is(C), T) :-
    format(atom(T), 'the thread just right of the territory (just left, if at the right selvedge) was woven ~w', [C]).
cond_text(at_warp_edge, 'territory touches a selvedge').
cond_text(territory_wider(N), T) :- format(atom(T), 'territory wider than ~w threads', [N]).
cond_text(territory_narrower(N), T) :- format(atom(T), 'territory narrower than ~w threads', [N]).
cond_text(pick_mod(M, R), T) :- format(atom(T), 'pick number divided by ~w leaves ~w', [M, R]).
cond_text(neighbor_count(Op, N), T) :-
    op_text(Op, OT),
    format(atom(T), 'number of other bobbins reaching within 2 threads of the territory is ~w ~w', [OT, N]).
cond_text(gap_nearby(Side, W), T) :-
    format(atom(T), 'the ~w threads just ~w of the territory are on the warp and in no other bobbin''s territory', [W, Side]).
cond_text(alive_ratio(Op, Pct), T) :-
    op_text(Op, OT),
    format(atom(T), 'all territory widths added up (as they were before this update, this one included) are ~w ~w% of the warp', [OT, Pct]).
cond_text(prev_edge_alive(Side), T) :-
    format(atom(T), 'the thread just ~w of the territory was woven', [Side]).
cond_text(territory_density(Op, Pct), T) :-
    op_text(Op, OT),
    format(atom(T), 'territory density is ~w ~w%', [OT, Pct]).
cond_text(neighbor_width(Op, N), T) :-
    op_text(Op, OT),
    format(atom(T), 'the nearest other bobbin (overlapping counts as nearest; on a tie, the first in step-1 order; no other bobbin = endlessly wide) is ~w ~w threads wide', [OT, N]).
cond_text(no_neighbors, 'no adjacent bobbins').
cond_text(Other, T) :- format(atom(T), '~w', [Other]).

act_text(grow_left(N), T) :- format(atom(T), 'grow left ~w', [N]).
act_text(grow_right(N), T) :- format(atom(T), 'grow right ~w', [N]).
act_text(shrink_left(N), T) :- format(atom(T), 'shrink left ~w (move left end ~w right)', [N, N]).
act_text(shrink_right(N), T) :- format(atom(T), 'shrink right ~w (move right end ~w left)', [N, N]).
act_text(grow_both(N), T) :- format(atom(T), 'grow both ~w', [N]).
act_text(shrink_both(N), T) :- format(atom(T), 'shrink both ~w', [N]).
act_text(shift_left(N), T) :- format(atom(T), 'shift left ~w', [N]).
act_text(shift_right(N), T) :- format(atom(T), 'shift right ~w', [N]).
act_text(flip_color, 'flip color').
act_text(toggle_pass, 'toggle pass (full <-> half)').
act_text(spawn_left(N), T) :- format(atom(T), 'spawn bobbin left (width ~w)', [N]).
act_text(spawn_right(N), T) :- format(atom(T), 'spawn bobbin right (width ~w)', [N]).
act_text(die, 'die (stop for good)').
act_text(Other, T) :- format(atom(T), '~w', [Other]).

% ============================================================
%  SEARCH + EVOLUTION
% ============================================================

search(best, Iterations) :-
    search_loop(Iterations, -999, nil, nil, BestS, BestC, BestF),
    format('~n=== BEST (Score: ~4f) ===~n', [BestS]),
    init_bobbins_from_config(BestC, Bs),
    print_instructions(Bs),
    display_fabric(BestF).

search_loop(0, S, C, F, S, C, F) :- !.
search_loop(N, CS, CC, CF, FS, FC, FF) :-
    N > 0, search_eval_picks(SEP),
    catch(
        (weave_capturing(SEP, Config, Fabric), evaluate_fabric(Fabric, Score, _)),
        _, (Score = -1, Fabric = [], Config = nil)
    ),
    format('\r  Trial ~w: ~4f', [N, Score]), flush_output,
    (Score > CS -> NS = Score, NC = Config, NF = Fabric
    ;             NS = CS,    NC = CC,     NF = CF),
    N1 is N - 1,
    search_loop(N1, NS, NC, NF, FS, FC, FF).

%% mutate_config(+Config, -Mutated)
mutate_config(config(Specs, Style), config(NewSpecs, Style)) :-
    length(Specs, N),
    random_between(1, N, Idx),
    nth1(Idx, Specs, spec(Id, L, R, C, P, Rules), Rest),
    mutate_spec(L, R, C, P, Rules, NL, NR, NC, NP2, NRules),
    nth1(Idx, NewSpecs, spec(Id, NL, NR, NC, NP2, NRules), Rest).

mutate_spec(L, R, C, P, Rules, NL, NR, NC, NP2, NRules) :-
    random_between(0, 5, W),
    mutate_spec_(W, L, R, C, P, Rules, NL, NR, NC, NP2, NRules).

mutate_spec_(0, L, R, _, P, Ru, L, R, NC, P, Ru) :- rand_color(NC).
mutate_spec_(1, L, R, C, full, Ru, L, R, C, half, Ru).
mutate_spec_(1, L, R, C, half, Ru, L, R, C, full, Ru).
mutate_spec_(2, L, R, C, P, Ru, NL, NR, C, P, Ru) :-
    random_between(-5, 5, DL), random_between(-5, 5, DR),
    NL0 is L + DL, NR0 is R + DR,
    NL is max(1, NL0),
    warp_width(W), NR is min(W, max(NL, NR0)).
mutate_spec_(3, L, R, C, P, Rules, L, R, C, P, NRules) :-
    length(Rules, NR),
    (NR > 0
    ->  random_between(1, NR, RI), rand_edge_rule(New),
        nth1(RI, Rules, _, RR), nth1(RI, NRules, New, RR)
    ;   rand_edge_rule(New), NRules = [New]).
mutate_spec_(4, L, R, C, P, Rules, L, R, C, P, NRules) :-
    rand_edge_rule(New), append(Rules, [New], NRules).
mutate_spec_(5, L, R, C, P, Rules, L, R, C, P, NRules) :-
    length(Rules, NR),
    (NR > 1 -> random_between(1, NR, RI), nth1(RI, Rules, _, NRules)
    ;          NRules = Rules).

evolve(Config, 0, _, Config, Score) :-
    !, search_eval_picks(SEP),
    weave_with_config(Config, SEP, Fabric),
    evaluate_fabric(Fabric, Score, _).
evolve(Config, Gens, Trials, BestC, BestS) :-
    Gens > 0, search_eval_picks(SEP),
    weave_with_config(Config, SEP, F0),
    evaluate_fabric(F0, S0, _),
    try_mutations(Config, Trials, S0, Config, MS, MC),
    format('  Gen ~w: ~4f~n', [Gens, MS]),
    G1 is Gens - 1,
    evolve(MC, G1, Trials, BestC, BestS).

try_mutations(_, 0, BS, BC, BS, BC) :- !.
try_mutations(Base, N, CS, CC, FS, FC) :-
    N > 0, mutate_config(Base, Mut), search_eval_picks(SEP),
    catch(
        (weave_with_config(Mut, SEP, Fabric), evaluate_fabric(Fabric, Score, _)),
        _, Score = -1
    ),
    (Score > CS -> NS = Score, NC = Mut ; NS = CS, NC = CC),
    N1 is N - 1,
    try_mutations(Base, N1, NS, NC, FS, FC).

% ============================================================
%  EXPORT — PPM image
% ============================================================

export_ppm(Fabric, Filename) :-
    % Pick 1 is woven first, at the bottom of the cloth
    reverse(Fabric, TopDown),
    double_fabric(TopDown, Doubled),
    length(Doubled, H),
    (H > 0 -> Doubled = [R1|_], length(R1, W) ; W = 0),
    open(Filename, write, S),
    format(S, 'P3~n~w ~w~n255~n', [W, H]),
    maplist(write_ppm_row(S), Doubled),
    close(S),
    format('Saved ~w (~wx~w)~n', [Filename, W, H]).

write_ppm_row(S, Row) :- maplist(write_ppm_pixel(S), Row), nl(S).

write_ppm_pixel(S, 0) :- format(S, '210 200 185 ', []).
write_ppm_pixel(S, 1) :- format(S, '20 20 20 ', []).
write_ppm_pixel(S, 2) :- format(S, '240 240 235 ', []).
write_ppm_pixel(S, 3) :- format(S, '80 80 80 ', []).
write_ppm_pixel(S, 4) :- format(S, '200 200 195 ', []).
write_ppm_pixel(S, _) :- format(S, '255 0 255 ', []).

% ============================================================
%  ENTRY POINTS
% ============================================================

run :-
    num_picks(NP), num_bobbins(NB), warp_width(W),
    format('Weaving ~w picks, ~w bobbins, ~w threads...~n', [NP, NB, W]),
    weave_capturing(NP, Config, Fabric),
    evaluate_fabric(Fabric, Score, Details),
    format('Score: ~4f~n', [Score]),
    format('Details: ~w~n', [Details]),
    init_bobbins_from_config(Config, Bs),
    print_instructions(Bs),
    display_fabric(Fabric).

demo :- demo(80).
demo(W) :-
    set_warp(W),
    run,
    set_warp(W).

%% set_warp(+Width) — set warp width and scale bobbins accordingly
set_warp(W) :-
    retractall(warp_width(_)), retractall(num_bobbins(_)),
    retractall(num_picks(_)), retractall(border_style(_)),
    NB is max(3, W // 10),
    assertz(warp_width(W)), assertz(num_bobbins(NB)),
    assertz(num_picks(500)), assertz(border_style(slit)).

%% eval_picks — shorter pick count for fast search/evaluation
eval_picks(EP) :- num_picks(EP).

find_good :- find_good(80).
find_good(W) :-
    set_warp(W),
    find_good_.
find_good_ :-
    search_eval_picks(SEP),
    format('Phase 1: Random search (20 trials, ~w eval picks)...~n', [SEP]),
    search_random_best(20, -999, nil, BestConfig, BestScore),
    format('~nBest random: ~4f~n', [BestScore]),
    format('Phase 2: Evolving (10 gen x 5 mut)...~n'),
    evolve(BestConfig, 10, 5, FinalConfig, FinalScore),
    format('~nFinal: ~4f~n', [FinalScore]),
    num_picks(NP),
    format('Rendering final at ~w picks...~n', [NP]),
    weave_with_config(FinalConfig, NP, Fabric),
    init_bobbins_from_config(FinalConfig, Bobbins),
    print_instructions(Bobbins),
    display_fabric(Fabric),
    export_ppm(Fabric, 'woven_pattern.ppm'),
    format('~nDone.~n').

%% search_eval_picks — shorter window for search speed
search_eval_picks(100).

%% find_crystalline/0 — Search for geometric/crystalline patterns
find_crystalline :- find_crystalline(80).
find_crystalline(W) :-
    set_warp(W),
    find_crystalline_.
find_crystalline_ :-
    search_eval_picks(SEP),
    format('Searching for crystalline patterns (~w eval picks)...~n', [SEP]),
    search_crystalline(30, -999, nil, BestConfig, BestScore),
    format('~nBest crystalline: ~4f~n', [BestScore]),
    format('Evolving (10 gen x 5 mut)...~n'),
    evolve_crystalline(BestConfig, 10, 5, FinalConfig, FinalScore),
    format('~nFinal: ~4f~n', [FinalScore]),
    num_picks(NP),
    format('Rendering at ~w picks...~n', [NP]),
    weave_with_config(FinalConfig, NP, Fabric),
    init_bobbins_from_config(FinalConfig, Bobbins),
    print_instructions(Bobbins),
    display_fabric(Fabric),
    export_ppm(Fabric, 'woven_pattern.ppm'),
    format('~nDone.~n').

%% search_crystalline — generate geometric bobbins, evaluate with regularity
search_crystalline(0, BS, BC, BC, BS) :- !.
search_crystalline(N, CurBS, CurBC, OutC, OutS) :-
    N > 0, search_eval_picks(SEP),
    num_bobbins(Base),
    Lo is max(3, Base - 3), Hi is Base + 3,
    random_between(Lo, Hi, NB),
    catch(
        (   init_bobbins_geometric(NB, Bobbins),
            bobbins_to_config(Bobbins, Config),
            empty_row(Init),
            weave_rows(SEP, Bobbins, Init, 1, [], Fabric),
            evaluate_crystalline(Fabric, Score, _)
        ),
        _, (Score = -1, Config = nil)
    ),
    format('\r  Trial ~w: ~4f', [N, Score]), flush_output,
    (Score > CurBS -> NS = Score, NC = Config ; NS = CurBS, NC = CurBC),
    N1 is N - 1,
    search_crystalline(N1, NS, NC, OutC, OutS).

%% evolve_crystalline — like evolve but uses crystalline evaluation
evolve_crystalline(Config, 0, _, Config, Score) :-
    !, search_eval_picks(SEP),
    weave_with_config(Config, SEP, Fabric),
    evaluate_crystalline(Fabric, Score, _).
evolve_crystalline(Config, Gens, Trials, BestC, BestS) :-
    Gens > 0, search_eval_picks(SEP),
    weave_with_config(Config, SEP, F0),
    evaluate_crystalline(F0, S0, _),
    try_mutations_cryst(Config, Trials, S0, Config, MS, MC),
    format('  Gen ~w: ~4f~n', [Gens, MS]),
    G1 is Gens - 1,
    evolve_crystalline(MC, G1, Trials, BestC, BestS).

try_mutations_cryst(_, 0, BS, BC, BS, BC) :- !.
try_mutations_cryst(Base, N, CS, CC, FS, FC) :-
    N > 0, mutate_config(Base, Mut), search_eval_picks(SEP),
    catch(
        (weave_with_config(Mut, SEP, Fabric),
         evaluate_crystalline(Fabric, Score, _)),
        _, Score = -1
    ),
    (Score > CS -> NS = Score, NC = Mut ; NS = CS, NC = CC),
    N1 is N - 1,
    try_mutations_cryst(Base, N1, NS, NC, FS, FC).

%% search_random_best — uses eval_picks for speed
search_random_best(0, BS, BC, BC, BS) :- !.
search_random_best(N, CurBS, CurBC, OutC, OutS) :-
    N > 0, search_eval_picks(SEP),
    catch(
        (weave_capturing(SEP, Config, Fabric), evaluate_fabric(Fabric, Score, _)),
        _, (Score = -1, Config = nil)
    ),
    format('\r  Trial ~w: ~4f', [N, Score]), flush_output,
    (Score > CurBS -> NS = Score, NC = Config ; NS = CurBS, NC = CurBC),
    N1 is N - 1,
    search_random_best(N1, NS, NC, OutC, OutS).

% ============================================================
%  FIND_LIFE — Game of Life pattern search
% ============================================================

find_life :- find_life(80).
find_life(W) :-
    set_warp(W),
    find_life_.
find_life_ :-
    search_eval_picks(SEP),
    format('Searching for Game of Life patterns (~w eval picks)...~n', [SEP]),
    search_life(30, -999, nil, BestConfig, BestScore),
    format('~nBest life pattern: ~4f~n', [BestScore]),
    format('Evolving (10 gen x 5 mut)...~n'),
    evolve_life(BestConfig, 10, 5, FinalConfig, FinalScore),
    format('~nFinal: ~4f~n', [FinalScore]),
    num_picks(NP),
    format('Rendering at ~w picks...~n', [NP]),
    weave_with_config(FinalConfig, NP, Fabric),
    init_bobbins_from_config(FinalConfig, Bobbins),
    print_instructions(Bobbins),
    display_fabric(Fabric),
    export_ppm(Fabric, 'woven_pattern.ppm'),
    format('~nDone.~n').

%% search_life — generate life-rule bobbins, evaluate with dynamics
search_life(0, BS, BC, BC, BS) :- !.
search_life(N, CurBS, CurBC, OutC, OutS) :-
    N > 0, search_eval_picks(SEP),
    num_bobbins(Base),
    Lo is max(2, Base - 4), Hi is Base + 2,
    random_between(Lo, Hi, NB),
    catch(
        (   init_bobbins_life(NB, Bobbins),
            bobbins_to_config(Bobbins, Config),
            empty_row(Init),
            weave_rows(SEP, Bobbins, Init, 1, [], Fabric),
            evaluate_life(Fabric, Score, _)
        ),
        _, (Score = -1, Config = nil)
    ),
    format('\r  Trial ~w: ~4f', [N, Score]), flush_output,
    (Score > CurBS -> NS = Score, NC = Config ; NS = CurBS, NC = CurBC),
    N1 is N - 1,
    search_life(N1, NS, NC, OutC, OutS).

%% evolve_life — like evolve but uses life evaluation
evolve_life(Config, 0, _, Config, Score) :-
    !, search_eval_picks(SEP),
    weave_with_config(Config, SEP, Fabric),
    evaluate_life(Fabric, Score, _).
evolve_life(Config, Gens, Trials, BestC, BestS) :-
    Gens > 0, search_eval_picks(SEP),
    weave_with_config(Config, SEP, F0),
    evaluate_life(F0, S0, _),
    try_mutations_life(Config, Trials, S0, Config, MS, MC),
    format('  Gen ~w: ~4f~n', [Gens, MS]),
    G1 is Gens - 1,
    evolve_life(MC, G1, Trials, BestC, BestS).

try_mutations_life(_, 0, BS, BC, BS, BC) :- !.
try_mutations_life(Base, N, CS, CC, FS, FC) :-
    N > 0, mutate_config(Base, Mut), search_eval_picks(SEP),
    catch(
        (weave_with_config(Mut, SEP, Fabric),
         evaluate_life(Fabric, Score, _)),
        _, Score = -1
    ),
    (Score > CS -> NS = Score, NC = Mut ; NS = CS, NC = CC),
    N1 is N - 1,
    try_mutations_life(Base, N1, NS, NC, FS, FC).

% ============================================================
%  FIND_UNIFORM — Uniform rule mode (one rule for all bobbins)
% ============================================================

%% enable_uniform_mode/0, disable_uniform_mode/0
%  Toggle uniform mode on/off.
enable_uniform_mode :-
    (uniform_mode -> true ; assertz(uniform_mode)).
disable_uniform_mode :-
    retractall(uniform_mode),
    retractall(uniform_rule(_)),
    retractall(ca_rule(_)),
    retractall(ca_rule_fixed),
    retractall(weft_alternate).

demo_uniform :- demo_uniform(80).
demo_uniform(W) :-
    set_warp(W),
    enable_uniform_mode,
    NB is max(2, W // 20),
    init_bobbins_uniform(NB, Bobbins),
    demo_uniform_(NB, Bobbins).
demo_uniform(W, CARule) :-
    set_warp(W),
    enable_uniform_mode,
    retractall(ca_rule(_)), assertz(ca_rule(CARule)),
    NB is max(2, W // 20),
    init_bobbins_uniform_keep_ca(NB, Bobbins),
    demo_uniform_(NB, Bobbins).
demo_uniform(W, CARule, Picks) :-
    set_warp(W),
    retractall(num_picks(_)), assertz(num_picks(Picks)),
    enable_uniform_mode,
    retractall(ca_rule(_)), assertz(ca_rule(CARule)),
    NB is max(2, W // 20),
    init_bobbins_uniform_keep_ca(NB, Bobbins),
    demo_uniform_(NB, Bobbins).

demo_uniform_(NB, Bobbins) :-
    (uniform_rule(UR) -> true ; UR = []),
    (ca_rule(CAR) -> true ; CAR = none),
    format('Uniform rule: ~w~n', [UR]),
    format('CA rule (Wolfram): ~w~n', [CAR]),
    bobbins_to_config(Bobbins, _Config),
    num_picks(NP),
    format('Weaving ~w picks, ~w bobbins (uniform mode)...~n', [NP, NB]),
    empty_row(Init),
    weave_rows(NP, Bobbins, Init, 1, [], Fabric),
    evaluate_life(Fabric, Score, Details),
    format('Score: ~4f~n', [Score]),
    format('Details: ~w~n', [Details]),
    print_instructions(Bobbins),
    display_fabric(Fabric),
    export_ppm(Fabric, 'woven_pattern.ppm'),
    disable_uniform_mode,
    format('~nDone.~n').

find_uniform :- find_uniform(80).
find_uniform(W) :-
    set_warp(W),
    enable_uniform_mode,
    find_uniform_,
    disable_uniform_mode.
find_uniform(W, CARule) :-
    set_warp(W),
    enable_uniform_mode,
    retractall(ca_rule(_)), assertz(ca_rule(CARule)),
    assertz(ca_rule_fixed),
    find_uniform_,
    retractall(ca_rule_fixed),
    disable_uniform_mode.
find_uniform(W, CARule, Picks) :-
    set_warp(W),
    retractall(num_picks(_)), assertz(num_picks(Picks)),
    enable_uniform_mode,
    retractall(ca_rule(_)), assertz(ca_rule(CARule)),
    assertz(ca_rule_fixed),
    find_uniform_,
    retractall(ca_rule_fixed),
    disable_uniform_mode.
find_uniform_ :-
    search_eval_picks(SEP),
    format('Searching for uniform-rule patterns (~w eval picks)...~n', [SEP]),
    search_uniform(30, -999, nil, BestConfig, BestScore),
    format('~nBest uniform: ~4f~n', [BestScore]),
    (BestConfig = config(_, loom(CAR, _, _)), CAR \== none
     -> format('CA rule (Wolfram): ~w~n', [CAR]) ; true),
    format('Evolving (10 gen x 5 mut)...~n'),
    evolve_uniform(BestConfig, 10, 5, FinalConfig, FinalScore),
    format('~nFinal: ~4f~n', [FinalScore]),
    (FinalConfig = config(_, loom(CAR2, _, _)), CAR2 \== none
     -> format('Final CA rule (Wolfram): ~w~n', [CAR2]) ; true),
    num_picks(NP),
    format('Rendering at ~w picks...~n', [NP]),
    weave_with_config(FinalConfig, NP, Fabric),
    init_bobbins_from_config(FinalConfig, Bobbins),
    print_instructions(Bobbins),
    display_fabric(Fabric),
    export_ppm(Fabric, 'woven_pattern.ppm'),
    format('~nDone.~n').

%% search_uniform — generate uniform-rule bobbins, evaluate with life dynamics
search_uniform(0, BS, BC, BC, BS) :- !.
search_uniform(N, CurBS, CurBC, OutC, OutS) :-
    N > 0, search_eval_picks(SEP),
    warp_width(WW),
    NB is max(2, WW // 20),
    catch(
        (   (ca_rule_fixed -> init_bobbins_uniform_keep_ca(NB, Bobbins)
            ;   init_bobbins_uniform(NB, Bobbins)
            ),
            bobbins_to_config(Bobbins, Config),
            empty_row(Init),
            weave_rows(SEP, Bobbins, Init, 1, [], Fabric),
            evaluate_life(Fabric, Score, _)
        ),
        _, (Score = -1, Config = nil)
    ),
    format('\r  Trial ~w: ~4f', [N, Score]), flush_output,
    (Score > CurBS -> NS = Score, NC = Config ; NS = CurBS, NC = CurBC),
    N1 is N - 1,
    search_uniform(N1, NS, NC, OutC, OutS).

%% evolve_uniform — mutation changes spatial layout + template, not per-bobbin rules
evolve_uniform(Config, 0, _, Config, Score) :-
    !, search_eval_picks(SEP),
    weave_with_config(Config, SEP, Fabric),
    evaluate_life(Fabric, Score, _).
evolve_uniform(Config, Gens, Trials, BestC, BestS) :-
    Gens > 0, search_eval_picks(SEP),
    weave_with_config(Config, SEP, F0),
    evaluate_life(F0, S0, _),
    try_mutations_uniform(Config, Trials, S0, Config, MS, MC),
    format('  Gen ~w: ~4f~n', [Gens, MS]),
    G1 is Gens - 1,
    evolve_uniform(MC, G1, Trials, BestC, BestS).

try_mutations_uniform(_, 0, BS, BC, BS, BC) :- !.
try_mutations_uniform(Base, N, CS, CC, FS, FC) :-
    N > 0, mutate_config_uniform(Base, Mut), search_eval_picks(SEP),
    catch(
        (weave_with_config(Mut, SEP, Fabric),
         evaluate_life(Fabric, Score, _)),
        _, Score = -1
    ),
    (Score > CS -> NS = Score, NC = Mut ; NS = CS, NC = CC),
    N1 is N - 1,
    try_mutations_uniform(Base, N1, NS, NC, FS, FC).

%% mutate_config_uniform(+Config, -Mutated)
%  Mutate positions/colors/passes but NOT individual rules.
%  Occasionally replace ALL rules with a new uniform template.
mutate_config_uniform(config(Specs, Loom), config(NewSpecs, NewLoom)) :-
    random_between(0, 5, Choice),
    (   Choice =:= 5
    ->  % Replace all rules with a new uniform template (keep CA rule if fixed).
        % The new settings go into the config, never into globals, so a
        % rejected mutation cannot leak into the final render.
        Loom = loom(OldCA, _, _),
        random_between(0, 7, T),
        uniform_template(T, NewRules, TemplCA, WeftAlt),
        (ca_rule_fixed -> NewCA = OldCA ; NewCA = TemplCA),
        NewLoom = loom(NewCA, WeftAlt, NewRules),
        maplist(replace_rules(NewRules), Specs, NewSpecs)
    ;   NewLoom = Loom,
        % Mutate spatial properties only (position, color, pass)
        length(Specs, N),
        random_between(1, N, Idx),
        nth1(Idx, Specs, spec(Id, L, R, C, P, Rules), Rest),
        mutate_spec_spatial(L, R, C, P, NL, NR, NC, NP2),
        nth1(Idx, NewSpecs, spec(Id, NL, NR, NC, NP2, Rules), Rest)
    ).

replace_rules(Rules, spec(Id, L, R, C, P, _), spec(Id, L, R, C, P, Rules)).

mutate_spec_spatial(L, R, C, P, NL, NR, NC, NP2) :-
    random_between(0, 2, W),
    mutate_spec_spatial_(W, L, R, C, P, NL, NR, NC, NP2).

mutate_spec_spatial_(0, L, R, _, P, L, R, NC, P) :- rand_color(NC).
mutate_spec_spatial_(1, L, R, C, full, L, R, C, half).
mutate_spec_spatial_(1, L, R, C, half, L, R, C, full).
mutate_spec_spatial_(2, L, R, C, P, NL, NR, C, P) :-
    random_between(-5, 5, DL), random_between(-5, 5, DR),
    NL0 is L + DL, NR0 is R + DR,
    NL is max(1, NL0),
    warp_width(WW), NR is min(WW, max(NL, NR0)).
