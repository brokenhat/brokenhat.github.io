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
%  Settings = settings(Mode, Width, Picks, Bobbins, MaxBobbins, Border, CA, Seed)
%  Mode     = random | good | crystalline | life | uniform
%  CA       = auto | none | 0..255 (Wolfram rule for the thread pattern;
%             auto = the mode's own choice: uniform picks one, others none)
%  Result   = result(Rows, Lanes, Text, Score)
%
%  Bobbins is used exactly, in every mode (the program's own searches vary
%  it by ±3, and uniform mode sets it from the warp width).
wa_generate(settings(Mode, W, Picks, NB, Max, Border, CA, Seed),
            result(Rows, Lanes, Text, Score)) :-
    set_random(seed(Seed)),
    wa_reset,
    wa_set(W, Picks, NB, Max, Border),
    (   Mode == uniform -> enable_uniform_mode ; true ),
    wa_set_ca(Mode, CA),
    with_output_to(string(_Progress), wa_config(Mode, NB, Config)),
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
    Cap is max(Max, NB),
    retractall(max_bobbins(_)), assertz(max_bobbins(Cap)),
    retractall(border_style(_)), assertz(border_style(Border)).

% A chosen rule (or none) is fixed: uniform mode keeps it through its
% search and mutations, the other modes carry it in every config.
wa_set_ca(_, auto) :- !.
wa_set_ca(Mode, CA) :-
    retractall(ca_rule(_)),
    (   integer(CA) -> assertz(ca_rule(CA)) ; true ),
    (   Mode == uniform -> assertz(ca_rule_fixed) ; true ).

wa_reset :- disable_uniform_mode.

%% wa_config(+Mode, +NB, -Config) — the program's own generators,
%  evaluations and evolution, searched with exactly NB bobbins
wa_config(random, NB, Config) :-
    wa_random_bobbins(NB, Bobbins),
    bobbins_to_config(Bobbins, Config).
wa_config(good, NB, Config) :-
    wa_search(20, wa_random_bobbins(NB), evaluate_fabric, Best),
    evolve(Best, 10, 5, Config, _).
wa_config(crystalline, NB, Config) :-
    wa_search(30, init_bobbins_geometric(NB), evaluate_crystalline, Best),
    evolve_crystalline(Best, 10, 5, Config, _).
wa_config(life, NB, Config) :-
    wa_search(30, init_bobbins_life(NB), evaluate_life, Best),
    evolve_life(Best, 10, 5, Config, _).
wa_config(uniform, NB, Config) :-
    wa_search(30, wa_uniform_bobbins(NB), evaluate_life, Best),
    evolve_uniform(Best, 10, 5, Config, _).

wa_random_bobbins(NB, Bobbins) :-
    rand_start_style(Style),
    init_bobbins_style(Style, NB, Bobbins).

wa_uniform_bobbins(NB, Bobbins) :-
    (   ca_rule_fixed -> init_bobbins_uniform_keep_ca(NB, Bobbins)
    ;   init_bobbins_uniform(NB, Bobbins)
    ).

%% wa_search(+Trials, :Init, :Eval, -Best)
%  Like the program's search_* loops: weave each trial for the
%  evaluation length, keep the best config.
wa_search(Trials, Init, Eval, Best) :-
    wa_search_(Trials, Init, Eval, -999, nil, Best),
    Best \== nil.

wa_search_(0, _, _, _, Best, Best) :- !.
wa_search_(N, Init, Eval, BS, BC, Best) :-
    search_eval_picks(SEP),
    catch(
        (   call(Init, Bobbins),
            bobbins_to_config(Bobbins, Config),
            empty_row(Row0),
            weave_rows(SEP, Bobbins, Row0, 1, [], Fabric),
            call(Eval, Fabric, Score, _)
        ),
        _, (Score = -1, Config = nil)
    ),
    (   Score > BS -> NS = Score, NC = Config ; NS = BS, NC = BC ),
    N1 is N - 1,
    wa_search_(N1, Init, Eval, NS, NC, Best).

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
