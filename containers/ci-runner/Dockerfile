FROM node:24-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install MoonBit CLI
RUN curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
ENV PATH="/root/.moon/bin:$PATH"

WORKDIR /workspace

# CI runner script: receives job spec via env, reports status back
COPY run.sh /usr/local/bin/ci-run
RUN chmod +x /usr/local/bin/ci-run

EXPOSE 8080
CMD ["ci-run"]
