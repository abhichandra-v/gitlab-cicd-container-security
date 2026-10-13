# Hardened production image: static binary on an empty base.
# See docs/SECURITY.md for the reasoning behind each choice.

FROM golang:1.27.2-alpine3.24@sha256:f92b6ef800e499660581efdabdf25d9d817a9d124eaf900924f0504e7e27e12d AS build

WORKDIR /src

# go.mod first, so the module layer is reused until dependencies change.
COPY go.mod ./
RUN go mod download

COPY cmd ./cmd
COPY internal ./internal

ARG VERSION=dev
# CGO off gives a static binary that needs no libc, so it can run on scratch.
# -trimpath removes build-machine paths; -s -w drops symbol and debug tables.
RUN CGO_ENABLED=0 GOOS=linux go build \
      -trimpath \
      -ldflags "-s -w -X main.version=${VERSION}" \
      -o /out/orders-api ./cmd/orders-api

# scratch: no shell, no package manager, no libc. The image is the binary.
FROM scratch

COPY --from=build /out/orders-api /orders-api

# Numeric UID:GID, so Kubernetes can verify runAsNonRoot without /etc/passwd.
USER 65532:65532

EXPOSE 8080

# No shell or curl in the image: the binary probes its own /healthz.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["/orders-api", "healthcheck"]

ENTRYPOINT ["/orders-api"]
