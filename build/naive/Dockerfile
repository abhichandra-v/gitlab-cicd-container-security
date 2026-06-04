# COMPARISON ONLY. Do not deploy. Never built or pushed by the pipeline.
#
# This is the "it works, ship it" image the hardened Dockerfile replaces:
# single stage, full Go toolchain and Debian userland in the runtime image,
# default build flags, runs as root. scripts/size-report.sh builds it to
# measure the difference. The scanners skip this directory on purpose; see
# docs/SECURITY.md.

FROM golang:1.27.2@sha256:007a316059246276cb214df93950be77837545dc78007a73e0291a4963d5d3bf

WORKDIR /app

COPY . .

RUN go build -o orders-api ./cmd/orders-api

EXPOSE 8080

CMD ["./orders-api"]
