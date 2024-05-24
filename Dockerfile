FROM golang:1.22.2 AS build-stage

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY ./ ./

ENV TZ="America/Los_Angeles"

RUN make test
RUN CGO_ENABLED=0 go build -ldflags "-s -w" -o bin/poolish cmd/poolish/main.go

FROM scratch AS release-stage

WORKDIR /

COPY --from=build-stage /app/bin/poolish /poolish

EXPOSE 8080
ENV TZ="America/Los_Angeles"

ENTRYPOINT ["/poolish"]
