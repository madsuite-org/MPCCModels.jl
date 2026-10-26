# Publish the repository guides as local documentation pages. Preserve their
# relative layout so links also work in offline builds and fork previews.
function prepare_opf_guides()
  source = joinpath(@__DIR__, "..", "examples", "opf")
  destination = joinpath(@__DIR__, "src", "generated", "opf")
  isdir(destination) && rm(destination; recursive = true)
  directories = ("", "pglib", "pglib/data", "pglib/hard-cases")
  for relative in directories
    directory = joinpath(source, relative)
    for name in readdir(directory)
      # Tables and the upstream license remain downloadable beside their guides.
      (endswith(name, ".md") || endswith(name, ".tsv") || name == "LICENSE") || continue
      target = joinpath(destination, relative, name)
      mkpath(dirname(target))
      if endswith(name, ".md")
        # GitHub and Documenter generate different automatic heading anchors.
        # Give the published copy explicit GitHub-compatible IDs so the same
        # relative fragment links work on both surfaces.
        counts = Dict{String, Int}()
        fenced = false
        content = String[]
        for line in readlines(joinpath(directory, name))
          startswith(line, "```") && (fenced = !fenced)
          heading = fenced ? nothing : match(r"^(#{1,6}) (.+)$", line)
          if !isnothing(heading)
            title = heading[2]
            slug = replace(lowercase(title), r"[^\p{L}\p{N}\s_-]" => "")
            slug = replace(strip(slug), r"\s" => "-")
            count = get(counts, slug, 0)
            counts[slug] = count + 1
            anchor = count == 0 ? slug : "$slug-$count"
            line = "$(heading[1]) [$title](@id $anchor)"
          end
          push!(content, line)
        end
        write(target, "```@meta\nEditURL = nothing\n```\n\n" * join(content, "\n") * "\n")
      else
        cp(joinpath(directory, name), target)
      end
    end
  end
  return nothing
end
