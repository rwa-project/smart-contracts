.PHONY: all build test clean deploy gas fmt

# Variables
BUILD_DIR := out
RPC_URL := $(or $(RPC_URL), "https://default.rpc.url") # TODO: Default value, replace with actual RPC URL
PRIVATE_KEY := $(PRIVATE_KEY)

# Commands
all: build

build:
	forge build

test:
	forge test -vv

clean:
	rm -rf $(BUILD_DIR)

deploy:
ifndef PRIVATE_KEY
	$(error PRIVATE_KEY is not set. Export it as an environment variable or pass it as an argument.)
endif
	forge script script/Deploy.s.sol --rpc-url $(RPC_URL) --private-key $(PRIVATE_KEY) --broadcast

gas:
	forge test --gas-report

fmt:
	forge fmt