# Stage 1: build the Haskell binary
FROM haskell:9.10 AS builder

RUN apt-get update && apt-get install -y libpq-dev && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy cabal file first so dependency installs are cached
COPY haskell-ledger.cabal ./
RUN cabal update && cabal build --only-dependencies

# Now copy source and build the actual app
COPY src/ src/
COPY app/ app/
COPY LICENSE CHANGELOG.md ./
RUN cabal build exe:haskell-ledger

# Pull the binary out of cabal's nested build dir
RUN cp $(cabal list-bin haskell-ledger) /app/server

# Stage 2: minimal runtime image
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y libpq5 ca-certificates && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/server /usr/local/bin/server

CMD ["server"]