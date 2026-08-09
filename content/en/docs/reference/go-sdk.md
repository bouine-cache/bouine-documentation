---
title: "Go SDK"
weight: 94
description: "Use the bouine Go SDK to manage cache invalidation, check health, and inspect cluster peers programmatically."
---

The bouine Go SDK (`pkg/bouineapi`) provides typed methods for every
admin API endpoint. It shares wire types with the Cobra CLI and the
admin server, so there is no drift between the SDK and the API.

## Installation

```bash
go get github.com/bouine-cache/bouine/pkg/bouineapi@latest
```

## Quick start

```go
package main

import (
    "context"
    "fmt"
    "log"

    "github.com/bouine-cache/bouine/pkg/api"
    "github.com/bouine-cache/bouine/pkg/bouineapi"
)

func main() {
    c := bouineapi.New("http://127.0.0.1:9000").WithToken("your-token")
    ctx := context.Background()

    // Health check
    health, err := c.Healthz(ctx)
    if err != nil {
        log.Fatal(err)
    }
    fmt.Println("health:", health.Status)

    // Purge a URL
    result, err := c.Purge(ctx, "https://example.com/page")
    if err != nil {
        log.Fatal(err)
    }
    fmt.Println("purge:", result.Status)
}
```

## Methods

### Health and metadata

```go
// Liveness probe
health, err := c.Healthz(ctx)

// Readiness probe
ready, err := c.Readyz(ctx)

// Build version
version, err := c.Version(ctx)

// List cluster peers
peers, err := c.Peers(ctx)
```

### Cache invalidation

```go
// Purge a single URL
result, err := c.Purge(ctx, "https://example.com/page")

// Purge multiple URLs (max 1000 per batch)
batch, err := c.BatchPurge(ctx, []string{
    "https://example.com/page1",
    "https://example.com/page2",
})

// Ban by predicate (host and/or path regex, surrogate key)
ban, err := c.Ban(ctx, api.BanExpr{
    HostRegex: "example.com",
    PathRegex: "^/api/",
})

// Soft-purge (mark stale, revalidate on next request)
refresh, err := c.Refresh(ctx, "https://example.com/page")
```

### Authentication

```go
// Verify the admin token is valid
err := c.AuthCheck(ctx)
```

## Configuration

### Bearer token

```go
c := bouineapi.New("http://127.0.0.1:9000").WithToken("your-token")
```

`WithToken` returns a copy of the client with the token set. The
original is not mutated.

### Custom HTTP client

```go
c := &bouineapi.Client{
    BaseURL:    "http://127.0.0.1:9000",
    Token:      "your-token",
    HTTPClient: &http.Client{Timeout: 30 * time.Second},
}
```

If `HTTPClient` is nil, a default client with a 10s timeout is used.

## Error handling

Non-2xx responses return an error containing the HTTP method, path,
status code, and a sanitized body:

```
bouineapi: POST /v1/purge: status 401: unauthorized
```

- Error bodies are capped at 4 KiB to prevent memory exhaustion.
- Control characters are stripped from error bodies to prevent log
  injection.
- All methods accept `context.Context` for cancellation and timeouts.

```go
result, err := c.Purge(ctx, "https://example.com/page")
if err != nil {
    if errors.Is(err, context.DeadlineExceeded) {
        // context deadline hit
    }
    // other error
    log.Fatal(err)
}
```

## OpenAPI spec

A formal OpenAPI 3.0 specification is available at
[`api/openapi.yaml`](https://github.com/bouine-cache/bouine/blob/main/api/openapi.yaml)
in the repository. Use it with `openapi-generator` to produce SDKs
in Python, TypeScript, and other languages.