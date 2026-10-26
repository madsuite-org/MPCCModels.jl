# Run from the repository root in the optional PGLib project; research is opt-in.
include("hard-search.jl")
using .HardCaseSearch
length(ARGS)>=1 || error("expected OUTPUT [--references-only] [--resume]")
all(a->a in ("--references-only", "--resume"), ARGS[2:end]) || error("unknown option")
run_operating_matrix(
    ARGS[1];
    benchmark = !("--references-only" in ARGS),
    resume = "--resume" in ARGS,
)
