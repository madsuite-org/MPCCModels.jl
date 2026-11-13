module BenchmarkEvidence

using CodecZlib, SHA, TOML
export evidence_file

const DIRECTORY=joinpath(@__DIR__, "hard-cases", "evidence")
const CACHE=joinpath(tempdir(), "mpccmodels-opf-evidence")
_sha(path) = bytes2hex(sha256(read(path)))

"""Resolve a lossless historical receipt, verifying compressed and original bytes.

Extraction is local and needs no download. The content-addressed cache is outside
this checkout and may be deleted at any time. An existing corrupt cache is an
error; it is never silently accepted or substituted for historical evidence.
"""
function evidence_file(name; directory = DIRECTORY, cache = CACHE)
    index=TOML.parsefile(joinpath(directory, "index.toml"))
    haskey(index["receipts"], name) ||
        throw(ArgumentError("unknown evidence receipt: $name"))
    entry=index["receipts"][name]
    compressed=joinpath(directory, entry["file"])
    _sha(compressed)==entry["compressed_sha256"] ||
        error("compressed evidence checksum mismatch")
    target=joinpath(cache, entry["sha256"], name)
    if !isfile(target)
        bytes=open(compressed) do input
            stream=GzipDecompressorStream(input)
            try
                read(stream)
            finally
                close(stream)
            end
        end
        length(bytes)==entry["bytes"] && bytes2hex(sha256(bytes))==entry["sha256"] ||
            error("unpacked evidence checksum mismatch")
        mkpath(dirname(target))
        temporary, io=mktemp(dirname(target))
        try
            write(io, bytes)
            close(io)
            mv(temporary, target; force = true)
        finally
            isopen(io) && close(io)
            isfile(temporary) && rm(temporary)
        end
    end
    filesize(target)==entry["bytes"] && _sha(target)==entry["sha256"] ||
        error("cached evidence checksum mismatch; remove $target and retry")
    return target
end

end
