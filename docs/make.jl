push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))
using Documenter, MPCCModels, NLPModels
include(joinpath(@__DIR__, "opf-guides.jl"))
prepare_opf_guides()

makedocs(
  root = @__DIR__,
  modules = [MPCCModels],
  doctest = true,
  linkcheck = true,
  format = Documenter.HTML(
    assets = ["assets/style.css"],
    prettyurls = get(ENV, "CI", nothing) == "true",
    size_threshold_ignore = ["reference.md"],
  ),
  sitename = "MPCCModels.jl",
  pages = [
    "Home" => "index.md",
    "API" => "api.md",
    "Balanced AC OPF" => "opf.md",
    "OPF study guides" => [
      "Small examples" => "generated/opf/README.md",
      "Small-case design" => "generated/opf/CASE_DESIGN.md",
      "Small-case roadmap" => "generated/opf/ROADMAP.md",
      "Transmission examples" => "generated/opf/pglib/README.md",
      "Application families" => "generated/opf/pglib/APPLICATIONS.md",
      "Coverage and fleets" => "generated/opf/pglib/EXPANSIONS.md",
      "IEEE 300" => "generated/opf/pglib/IEEE300.md",
      "IEEE 300 policy matrix" => "generated/opf/pglib/POLICY_MATRIX.md",
      "Search and replay" => "generated/opf/pglib/HARD_SEARCH.md",
      "Operating conditions" => "generated/opf/pglib/OPERATING_CONDITIONS.md",
      "Test tiers" => "generated/opf/pglib/TESTING.md",
      "Benchmark evidence" => "generated/opf/pglib/hard-cases/README.md",
      "Source attribution" => "generated/opf/pglib/data/README.md",
      "Initial coverage review" => "generated/opf/pglib/REVIEW.md",
      "Transmission roadmap" => "generated/opf/pglib/ROADMAP.md",
    ],
    "Reference" => "reference.md",
  ],
)

deploydocs(
  repo = "github.com/MadNLP/MPCCModels.jl.git",
  push_preview = true,
  devbranch = "master",
)
