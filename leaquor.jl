#!/usr/bin/env julia
using Glob
using Base.Filesystem
using JSON  # For JSON output
using YAML  # Add YAML package for reading YAML files
using LibGit2  # For cloning GitHub repositories
using Logging  # For improved logging

# Default Patterns to detect secrets
const DEFAULT_SECRET_PATTERNS = Dict(
    "api_key" => r"(?i)(api|access|secret)[_-]?key[\\\"']?\\s*[:=]\\s*[\\\"']([a-z0-9]{32,})",
    "password" => r"(?i)(password|passwd|pwd)[\\\"']?\\s*[:=]\\s*[\\\"']([^\\\"'\\s]+)",
    "private_key" => r"-----BEGIN (RSA|OPENSSH|DSA|EC|PGP)? PRIVATE KEY-----",
    "oauth_token" => r"(?i)oauth[_-]?token[\\\"']?\\s*[:=]\\s*[\\\"']([a-z0-9]{32,})",
    "slack_token" => r"(xox[pboa]-[0-9]{12}-[0-9]{12}-[0-9]{12}-[a-z0-9]{32})",
    "aws_key" => r"(?i)(aws|amazon)[_-]?(access|secret)[_-]?key[\\\"']?\\s*[:=]\\s*[\\\"']([a-z0-9]{40})",
    "high_entropy" => r"([a-z0-9+/=]{32,})",  # Simple pattern for high entropy strings
    "database_url" => r"(?i)(postgres|mysql|mongodb)://[a-z0-9_]+:[^@]+@[a-z0-9.-]+/[a-z0-9_]+",
    "authorization" => r"(?i)authorization:\\s*(bearer|basic)\\s+([a-z0-9._-]+)"
)

# File extensions to scan
const SCAN_EXTENSIONS = [
    ".yml", ".yaml", ".json", ".js", ".py", ".rb",
    ".php", ".java", ".go", ".sh", ".env", ".config",
    ".pem", ".ppk", ".key", ".sql", ".xml", ".conf"
]

# Skip these directories
const SKIP_DIRS = [
    "node_modules", ".git", "vendor", "dist", "build",
    "__pycache__", ".idea", ".vscode", "tmp", "log"
]

function is_text_file(filepath)
    try
        open(filepath) do f
            while !eof(f)
                byte = read(f, UInt8)
                # Check for non-text bytes (0-8, 14-31, except \t, \n, \r)
                if byte < 32 && !(byte in [9, 10, 13])
                    return false
                end
            end
        end
        return true
    catch e
        @warn "Could not read file $filepath: $e"
        return false
    end
end

function calculate_entropy(s)
    length(s) < 16 && return 0.0  # Skip short strings
    freq = Dict{Char,Int}()
    for c in lowercase(s)
        freq[c] = get(freq, c, 0) + 1
    end
    entropy = 0.0
    len = length(s)
    for (_, count) in freq
        p = count / len
        entropy -= p * log2(p)
    end
    entropy
end

function load_custom_patterns(yaml_file)
    try
        # Parse the YAML file
        yaml_data = YAML.load_file(yaml_file)
        # Extract patterns from YAML
        patterns = Dict{String, Regex}()
        for entry in yaml_data["patterns"]
            name = entry["pattern"]["name"]
            regex_str = entry["pattern"]["regex"]
            patterns[name] = Regex(regex_str)
        end
        return patterns
    catch e
        @error "Failed to load custom patterns from $yaml_file: $e"
        return Dict{String, Regex}()
    end
end

function should_skip(path, ignore_files)
    # Check if path matches any ignored file names or patterns
    if any(file -> occursin(file, basename(path)), ignore_files)
        return true
    end
    # Check if path matches any skipped directories
    any(skip -> occursin(skip, path), SKIP_DIRS)
end

function scan_file(filepath, secret_patterns, entropy_threshold=3.5)
    secrets_found = []
    if !is_text_file(filepath)
        @info "Skipping binary file: $filepath"
        return secrets_found
    end
    try
        content = read(filepath, String)
        # Check for each secret pattern
        for (pattern_name, pattern) in secret_patterns
            matches = eachmatch(pattern, content)
            for m in matches
                secret = length(m.captures) > 0 ? m.captures[end] : m.match
                # Skip empty matches
                isnothing(secret) && continue
                # For high entropy pattern, verify entropy
                if pattern_name == "high_entropy"
                    entropy = calculate_entropy(secret)
                    if entropy < entropy_threshold
                        @info "Skipping low entropy string: $secret (Entropy: $entropy)"
                        continue
                    end
                end
                push!(secrets_found, (
                    filepath = filepath,
                    line = something(findnext('\n', content, m.offset), length(content)),
                    pattern = pattern_name,
                    match = secret,
                    context = replace(get_line(content, m.offset), r"[\x00-\x1F]" => "")  # Remove control characters
                   ))
            end
        end
        # Special case for private keys - check the whole file
        if occursin(secret_patterns["private_key"], content)
            push!(secrets_found, (
                filepath = filepath,
                line = 1,
                pattern = "private_key",
                match = "PRIVATE KEY BLOCK",
                context = "Contains private key material"
            ))
        end
    catch e
        @warn "Error scanning file $filepath: $e"
    end
    secrets_found
end

function get_line(content, offset)
    start = something(findprev(isequal('\n'), content, offset), 0) + 1
    stop = something(findnext(isequal('\n'), content, offset), length(content)) - 1
    content[start:stop]
end

function scan_directory(root_dir, secret_patterns, ignore_files, entropy_threshold=3.5)
    @info "Scanning directory: $root_dir"
    secrets = []
    for (root, dirs, files) in walkdir(root_dir)
        # Log skipped directories
        filter!(d -> begin
            skip = should_skip(joinpath(root, d), ignore_files)
            if skip
                @info "Skipping directory: $(joinpath(root, d))"
            end
            !skip
        end, dirs)

        for file in files
            filepath = joinpath(root, file)
            if should_skip(filepath, ignore_files)
                @info "Skipping file: $filepath"
                continue
            elseif !(any(endswith(filepath, ext) for ext in SCAN_EXTENSIONS))
                @info "File does not match scan extensions: $filepath"
                continue
            end
            @info "Scanning file: $filepath"
            found = scan_file(filepath, secret_patterns, entropy_threshold)
            append!(secrets, found)
        end
    end
    secrets
end

function print_results(secrets, json_output=false, output_file=nothing)
    if isempty(secrets)
        if json_output
            json_data = "[]"
        else
            println(stderr, "No secrets found")
            return
        end
    else
        json_data = map(secrets) do secret
            Dict(
                "file" => secret.filepath,
                "line" => secret.line,
                "type" => secret.pattern,
                "match" => secret.match,
                "context" => secret.context
            )
        end
    end
    if json_output
        if !isnothing(output_file)
            try
                open(output_file, "w") do io
                    JSON.print(io, json_data, 4)  # Pretty-print with 4 spaces indentation
                end
                println(stderr, "JSON results written to $output_file")
            catch e
                @error "Failed to write JSON output to file: $e"
                JSON.print(stdout, json_data, 4)
            end
        else
            # This is the only line that should go to stdout when using --json
            JSON.print(stdout, json_data, 4)
        end
    else
        # Plain text output goes to stderr to avoid mixing with JSON
        println(stderr, "\nFound $(length(secrets)) potential secrets:")
        println(stderr, "="^60)
        for secret in secrets
            println(stderr, "\nFile: $(secret.filepath)")
            println(stderr, "Line: $(secret.line)")
            println(stderr, "Type: $(secret.pattern)")
            println(stderr, "Match: $(secret.match)")
            println(stderr, "Context: $(secret.context)")
            println(stderr, "-"^60)
        end
    end
end

function print_help()
    println(stderr, """
Usage: julia leaquor.jl [options]
Options:
  -h, --help          Display this help message.
  --json              Output results in JSON format.
  --output-file FILE  Write JSON results to the specified file.
  --patterns FILE     Load additional patterns from a YAML file.
  --ignore-files LIST Comma-separated list of files to ignore (e.g., "file1.txt,file2.json").
  --repo URL          Clone and scan a GitHub repository (e.g., https://github.com/user/repo.git).
  --dir PATH          Scan a specific directory on the file system.
  --entropy-threshold FLOAT Set custom entropy threshold (default: 3.5).
  --log-file FILE     Write logs to the specified file.
Arguments:
  Either --repo or --dir must be provided.
Examples:
  julia leaquor.jl --repo https://github.com/user/repo.git --json --output-file out.json
  julia leaquor.jl --dir ./my_project --patterns custom_patterns.yaml | jq .
""")
end

function clone_github_repo(repo_url)
    temp_dir = mktempdir()
    @info "Cloning repository from $repo_url into $temp_dir..."
    try
        LibGit2.clone(repo_url, temp_dir)
        @info "Repository cloned successfully."
    catch e
        @error "Failed to clone repository: $e"
        rm(temp_dir, recursive=true, force=true)
        return nothing
    end
    return temp_dir
end

function setup_logger(log_file)
    if !isnothing(log_file)
        io = open(log_file, "w+")
        logger = ConsoleLogger(io, Logging.Debug)
        global_logger(logger)
        return io
    else
        global_logger(ConsoleLogger(stderr, Logging.Debug))
        return nothing
    end
end

function main()
    # Print all status messages to stderr
    println(stderr, "Secrets Scanner in Julia")
    # Parse command-line arguments
    args = ARGS
    # Show help by default if no arguments are provided
    if isempty(args)
        print_help()
        return
    end

    json_output = "--json" in args
    show_help = ("-h" in args) || ("--help" in args)
    output_file = nothing
    patterns_file = nothing
    ignore_files = []
    repo_url = nothing
    dir_path = nothing
    entropy_threshold = 3.5  # Default entropy threshold
    log_file = nothing

    # Extract arguments
    for i in 1:length(args)
        if args[i] == "--output-file" && i + 1 <= length(args)
            output_file = args[i + 1]
        elseif args[i] == "--patterns" && i + 1 <= length(args)
            patterns_file = args[i + 1]
        elseif args[i] == "--ignore-files" && i + 1 <= length(args)
            ignore_files = split(args[i + 1], ",")
        elseif args[i] == "--repo" && i + 1 <= length(args)
            repo_url = args[i + 1]
        elseif args[i] == "--dir" && i + 1 <= length(args)
            dir_path = args[i + 1]
        elseif args[i] == "--entropy-threshold" && i + 1 <= length(args)
            entropy_threshold = parse(Float64, args[i + 1])
        elseif args[i] == "--log-file" && i + 1 <= length(args)
            log_file = args[i + 1]
        end
    end

    if show_help
        print_help()
        return
    end

    # Validate that either --repo or --dir is provided
    if isnothing(repo_url) && isnothing(dir_path)
        println(stderr, "Error: Either --repo or --dir must be provided.")
        print_help()
        return
    end

    # Set up logging
    log_io = setup_logger(log_file)
    if !isnothing(log_file)
        @info "Logging to $log_file"
    else
        @info "Logging to console"
    end

    # Initialize secret patterns
    secret_patterns = copy(DEFAULT_SECRET_PATTERNS)
    # Load custom patterns if provided
    if !isnothing(patterns_file)
        custom_patterns = load_custom_patterns(patterns_file)
        merge!(secret_patterns, custom_patterns)
    end

    # Determine the directory to scan
    scan_dir = nothing
    if !isnothing(repo_url)
        scan_dir = clone_github_repo(repo_url)
        if isnothing(scan_dir)
            println(stderr, "Aborting due to failure in cloning the repository.")
            return
        end
    elseif !isnothing(dir_path)
        scan_dir = dir_path
    end

    @info "Using entropy threshold: $entropy_threshold"
    @info "Scanning $scan_dir for potential secrets..."

    secrets = scan_directory(scan_dir, secret_patterns, ignore_files, entropy_threshold)
    print_results(secrets, json_output, output_file)

    # Clean up temporary directory if a repository was cloned
    if !isnothing(repo_url) && !isnothing(scan_dir)
        @info "Cleaning up temporary directory..."
        rm(scan_dir, recursive=true, force=true)
    end

    # Close log file if it exists
    if !isnothing(log_io)
        close(log_io)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
