# ============================================================
# Stage 1: Builder
# ============================================================
FROM swift:6.2-noble AS builder

WORKDIR /build

# Copy package manifests first — SPM resolution re-runs only when these change.
COPY Package.swift Package.resolved ./

RUN --mount=type=cache,target=/root/.cache/org.swift.swiftpm \
    swift package resolve

COPY Sources ./Sources
# SPM validates all target paths at planning time, even targets that won't be compiled.
COPY Tests ./Tests

RUN --mount=type=cache,target=/build/.build \
    --mount=type=cache,target=/root/.cache/org.swift.swiftpm \
    swift build -c release --product Run && \
    cp .build/release/Run /tmp/Run

# ============================================================
# Stage 2: Runtime
# ============================================================
FROM swift:6.2-noble

WORKDIR /app

# Non-root user for the server process.
RUN useradd --uid 1001 --create-home --shell /bin/bash vapor

COPY --from=builder /tmp/Run /app/run
RUN chown vapor:vapor /app/run && chmod +x /app/run

# Default Docker configuration.
# BIND_HOST=0.0.0.0 is required for Docker port mapping to work.
ENV BIND_HOST=0.0.0.0
ENV PORT=8080
ENV LOG_LEVEL=info

EXPOSE 8080

USER vapor

ENTRYPOINT ["/app/run"]
