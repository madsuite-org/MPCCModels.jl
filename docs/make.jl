push!(LOAD_PATH,"../src/")
using Documenter, MPCCModels, NLPModels

makedocs(
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
    "Reference" => "reference.md",
  ],
  linkcheck_ignore = [
      "https://opensource.org/license/mit" # Fails for some unknown reason making docs build red.
  ],
)

deploydocs(
  repo = "github.com/MadNLP/MPCCModels.jl.git",
  push_preview = true,
  devbranch = "master",
)
