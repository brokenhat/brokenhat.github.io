% ============================================================
%  WOVEN AUTOMATA — web entry point
% ============================================================
%
%  Loaded next to woven_automata.pl (unchanged) by the website. One
%  predicate, wa_generate/2, runs a generation with the settings from
%  the page and hands back everything the page shows:
%
%    rows       — the fabric, one list of cell values per pick (pick 1 first)
%    lanes      — per pick, the active bobbins laid out for it:
%                 [Id, Left, Right, Color, Pass]
%    text       — the program's own weaving instructions (print_instructions)
%    score      — the evaluation score of the result
%
%  Every run is seeded, so the same settings + seed give the same design.

:- use_module(library(random)).

%% wa_generate(+Settings, -Result)
%  Settings = settings(Mode, Width, Picks, Bobbins, MaxBobbins, Border, Seed)
%  Mode     = random | good | crystalline | life | uniform
%  Result   = result(Rows, Lanes, Text, Score)
wa_generate(settings(Mode, W, Picks, NB, Max, Border, Seed),
            result(Rows, Lanes, Text, Score)) :-
    set_random(seed(Seed)),
    wa_reset,
    wa_set(W, Picks, NB, Max, Border),
    (   Mode == uniform -> enable_uniform_mode ; true ),
    with_output_to(string(_Progress), wa_config(Mode, Config)),
    init_bobbins_from_config(Config, Bobbins),
    wa_weave(Bobbins, Picks, Rows, Lanes),
    wa_score(Mode, Rows, Score),
    with_output_to(string(Text), print_instructions(Bobbins)),
    wa_reset.

% Settings, the same way set_warp/1 does it, then the page's values.
wa_set(W, Picks, NB, Max, Border) :-
    set_warp(W),
    retractall(num_picks(_)), assertz(num_picks(Picks)),
    retractall(num_bobbins(_)), assertz(num_bobbins(NB)),
    retractall(max_bobbins(_)), assertz(max_bobbins(Max)),
    retractall(border_style(_)), assertz(border_style(Border)).

wa_reset :- disable_uniform_mode.

%% wa_config(+Mode, -Config) — the program's own generators and searches
wa_config(random, Config) :-
    init_bobbins(Bobbins),
    bobbins_to_config(Bobbins, Config).
wa_config(good, Config) :-
    search_random_best(20, -999, nil, Best, _),
    evolve(Best, 10, 5, Config, _).
wa_config(crystalline, Config) :-
    search_crystalline(30, -999, nil, Best, _),
    evolve_crystalline(Best, 10, 5, Config, _).
wa_config(life, Config) :-
    search_life(30, -999, nil, Best, _),
    evolve_life(Best, 10, 5, Config, _).
wa_config(uniform, Config) :-
    search_uniform(30, -999, nil, Best, _),
    evolve_uniform(Best, 10, 5, Config, _).

%% wa_weave(+Bobbins, +Picks, -Rows, -Lanes)
%  Same loop as weave_rows/6, also recording who weaves where on each pick.
wa_weave(Bobbins, Picks, Rows, Lanes) :-
    empty_row(Init),
    wa_weave_(Picks, Bobbins, Init, 1, Rows, Lanes).

wa_weave_(0, _, _, _, [], []) :- !.
wa_weave_(N, Bobbins, Prev, Pick, [Row|Rows], [Lane|Lanes]) :-
    sort_bobbins_lr(Bobbins, Sorted),
    active_bobbins(Sorted, Active),
    maplist(wa_lane, Active, Lane),
    weave_pick(Bobbins, Prev, Pick, Row, Next),
    N1 is N - 1, Pick1 is Pick + 1,
    wa_weave_(N1, Next, Row, Pick1, Rows, Lanes).

wa_lane(bobbin(Id, L, R, C, P, _), [Id, L, R, C, P]).

wa_score(Mode, Rows, Score) :-
    (   memberchk(Mode, [life, uniform]) -> evaluate_life(Rows, Score, _)
    ;   Mode == crystalline -> evaluate_crystalline(Rows, Score, _)
    ;   evaluate_fabric(Rows, Score, _)
    ).
