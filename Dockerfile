# Use an official Julia image as the base image
FROM julia:1.9

# Set the working directory inside the container
WORKDIR /app

# Install necessary system dependencies (e.g., Git for cloning repositories)
RUN apt-get update && apt-get install -y \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy all required project files into the container
COPY leaquor.jl patterns.yaml /app/

# Install required Julia packages
RUN julia -e 'using Pkg; \
    Pkg.add("Glob"); \
    Pkg.add("JSON"); \
    Pkg.add("YAML"); \
    Pkg.add("LibGit2");'

# Make the script executable
RUN chmod +x /app/leaquor.jl

# Set the entry point to run the script
ENTRYPOINT ["julia", "/app/leaquor.jl"]

# Default command (can be overridden when running the container)
CMD ["--help"]
