# Build stage
FROM golang:1.20 as builder

WORKDIR /app

# Copy go mod and sum files
COPY go.mod go.sum ./
# Download all dependencies. Dependencies will be cached if the go.mod and go.sum files are not changed
RUN go mod download

# Copy the source code into the container
COPY . .

# Build the Go app
RUN CGO_ENABLED=0 GOOS=linux go build .

# Final stage
FROM alpine:latest

WORKDIR /app/

# Copy the Pre-built binary file from the previous stage
COPY --from=builder /app/event-watcher .

# Command to run the executable
CMD ["./event-watcher"]
