VERSION ?= 1.3.0
GO ?= $(shell command -v go || echo /usr/local/go/bin/go)
export GOTOOLCHAIN ?= local

.PHONY: all build dist test vet clean

all: test dist

build:
	CGO_ENABLED=0 $(GO) build -trimpath -ldflags "-s -w -X main.version=$(VERSION)" -o homestream-server .

dist:
	VERSION=$(VERSION) GO=$(GO) ./build.sh

vet:
	$(GO) vet ./...

test: vet
	$(GO) test ./...

clean:
	rm -rf dist homestream-server
