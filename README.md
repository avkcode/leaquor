# leaquor.jl

<table>
  <tr>
    <td valign="top" width="100">
      <img src="https://raw.githubusercontent.com/avkcode/leaquor/refs/heads/main/favicon.svg"
           alt="leaquor.jl Logo"
           width="80">
    </td>
    <td valign="middle">
    A powerful secrets scanning tool designed to detect sensitive information in codebases and files. Scans local directories or GitHub repositories for API keys, passwords, private keys, and other high-entropy patterns. Features customizable detection rules via YAML configuration and supports JSON output for integration into CI/CD pipelines.
    </td>
  </tr>
</table>

## Usage

Scanning a Local Directory
```
julia leaquor.jl --dir ./my_project
```

Scanning a GitHub Repository
```
julia leaquor.jl --repo https://github.com/user/repo.git
```

Using Custom Patterns
```
julia leaquor.jl --patterns patterns.yaml --dir ./my_project
```

Generating JSON Output
```
julia leaquor.jl --json --output-file results.json --dir ./my_project
```

## Installation

Clone the Repository
```
git clone https://github.com/avkcode/leaquor.git
cd leaquor
```

Install Dependencies  Ensure you have Julia installed, then run:
```
julia -e 'using Pkg; Pkg.add(["Glob", "JSON", "YAML", "LibGit2"])'
```

Run the Script
```
julia leaquor.jl --help
```
## Docker Support

You can also run Leaquor in a Docker container for seamless deployment:
```bash
docker build -t leaquor .
```
Run the Container
```bash
docker run --rm -v $(pwd)/my_project:/app/my_project leaquor --dir /app/my_project
```

## License

This project is licensed under the MIT License .

## Contributing

We welcome contributions! If you'd like to improve Leaquor or add new features, feel free to submit a pull request. Please ensure your changes are well-tested and documented.
