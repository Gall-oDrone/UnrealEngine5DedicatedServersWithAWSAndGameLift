# Stage 1 — Prepare files
FROM public.ecr.aws/amazonlinux/amazonlinux:latest AS build-server

# Create directory for the packaged game server
WORKDIR /server

# Copy your packaged Linux game server files (already built by UE)
COPY . /server

# Optional: copy OpenSSL libraries if your binary needs them
RUN cp /usr/lib64/libssl.so.3 /server/ || true && \
    cp /usr/lib64/libcrypto.so.3 /server/ || true

# Stage 2 — minimal runtime container
FROM scratch AS server

# Copy all game server files from the build stage
COPY --from=build-server /server/ /

# Make the game server the entrypoint
ENTRYPOINT ["/FPSTemplateServer"]
