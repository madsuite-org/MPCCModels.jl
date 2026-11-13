# Package complete local evidence for later distribution; never uploads anything.
using TOML, SHA, Tar
include("benchmark-evidence.jl")
using .BenchmarkEvidence

function package_evidence(output, raw_directory)
    (ispath(output) || ispath(output*".sha256")) &&
        error("refusing to overwrite existing evidence bundle or checksum")
    directory=BenchmarkEvidence.DIRECTORY
    index=TOML.parsefile(joinpath(directory, "raw-archives.toml"))
    # Validate every archive before creating an output or staging copies.
    for (name, entry) in index["archives"]
        path=joinpath(raw_directory, name)
        filesize(path)==entry["bytes"] && bytes2hex(sha256(read(path)))==entry["sha256"] ||
            error("raw archive checksum mismatch: $name")
    end
    receipts=TOML.parsefile(joinpath(directory, "index.toml"))["receipts"]
    foreach(evidence_file, keys(receipts))
    mktempdir() do stage
        mkpath(joinpath(stage, "receipts"))
        for name in
            ("index.toml", "raw-archives.toml", (r["file"] for r in values(receipts))...)
            cp(joinpath(directory, name), joinpath(stage, "receipts", name))
        end
        mkpath(joinpath(stage, "raw"))
        for name in keys(index["archives"])
            cp(joinpath(raw_directory, name), joinpath(stage, "raw", name))
        end
        write(
            joinpath(stage, "README.txt"),
            "Complete MPCCModels OPF evidence. Raw archives retain original source, environments, inputs, logs, failures and witnesses. Receipts are lossless gzip files. Verify compressed and expanded SHA-256 against receipts/index.toml and raw archives against receipts/raw-archives.toml. No solver rerun or success claim is implied.\n",
        )
        return Tar.create(stage, output)
    end
    digest=bytes2hex(sha256(read(output)))
    write(output*".sha256", digest*"  "*basename(output)*"\n")
    return println((bundle = abspath(output), bytes = filesize(output), sha256 = digest))
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS) in (1, 2) || error("expected OUTPUT.tar [RAW_DIRECTORY]")
    package_evidence(
        ARGS[1],
        length(ARGS)==2 ? ARGS[2] : joinpath(@__DIR__, "search-results"),
    )
end
