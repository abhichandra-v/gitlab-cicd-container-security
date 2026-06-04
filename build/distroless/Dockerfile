# COMPARISON ONLY. Never built or pushed by the pipeline.
#
# Same build stage as the root Dockerfile, but on distroless/static instead of
# scratch. scripts/size-report.sh builds it so the choice between the two
# runtime bases is backed by a measurement (docs/DECISIONS.md, D-007).

FROM golang:1.27.2-alpine3.24@sha256:f92b6ef800e499660581efdabdf25d9d817a9d124eaf900924f0504e7e27e12d AS build

WORKDIR /src

COPY go.mod ./
RUN go mod download

COPY cmd ./cmd
COPY internal ./internal

RUN CGO_ENABLED=0 GOOS=linux go build \
      -trimpath \
      -ldflags "-s -w" \
      -o /out/orders-api ./cmd/orders-api

FROM gcr.io/distroless/static-debian12:nonroot@sha256:afa5c872c891853ca7fcf1f12c3edb23f7eeef36189728842dd51042ff57f7ab

COPY --from=build /out/orders-api /orders-api

USER 65532:65532

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["/orders-api", "healthcheck"]

ENTRYPOINT ["/orders-api"]
