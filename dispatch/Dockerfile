# Stage 1: The Builder (Compiles the code)
FROM golang:1.24-alpine AS builder

WORKDIR /app

# Copy only the Go files initially
COPY *.go .

# Initialize the module and download dependencies.
# 'go get' is deprecated for this usage in newer versions; 'go mod tidy' is the modern replacement.
RUN go mod init dispatch && go mod tidy

# Build the binary. CGO_ENABLED=0 ensures a static binary that runs anywhere.
RUN CGO_ENABLED=0 go build -o dispatch .

# ---

# Stage 2: The Runner (Holds only the final binary)
FROM alpine:latest

WORKDIR /app

# Copy only the compiled binary from the builder stage
COPY --from=builder /app/dispatch .

CMD ["./dispatch"]