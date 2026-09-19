# Optional top-level Makefile for HPC Benchmarks
# Wraps initialize.sh and compile-hpc-benchmarks.sh for convenience

SHELL := /usr/bin/env bash

BENCHMARKS := HPCG JA LAGRAPH LULESH MW NAS PARBOIL PO RODINIA ST

.PHONY: all init initialize clean distclean help $(BENCHMARKS)

# Default target: compile all benchmark suites
all:
	@if [ ! -d ".deps" ]; then $(MAKE) init; fi
	./compile-hpc-benchmarks.sh

# Initialize userspace dependencies, tools, datasets, and configurations
init initialize:
	./initialize.sh

# Target rules for individual benchmark suites
$(BENCHMARKS):
	@if [ ! -d ".deps" ]; then $(MAKE) init; fi
	./compile-hpc-benchmarks.sh $@

# Clean compiled objects and binaries
clean:
	./compile-hpc-benchmarks.sh -c

# Clean build artifacts and remove self-contained dependencies (.deps, .tools, .venv)
distclean: clean
	@echo "Cleaning up .deps, .tools, .venv, and datasets..."
	rm -rf .deps .tools .venv PARBOIL/datasets
	@echo "Clean completed."

# Display help information
help:
	@echo "HPC Benchmarks - Available Make Targets:"
	@echo "  make [all]          Build all 10 benchmark suites (initializes if needed)"
	@echo "  make init           Run initialize.sh to download & configure dependencies"
	@echo "  make <SUITE>        Build a specific benchmark suite:"
	@echo "                      Available: $(BENCHMARKS)"
	@echo "  make clean          Clean build artifacts and binaries across all suites"
	@echo "  make distclean      Clean build artifacts and remove .deps, .tools, .venv"
	@echo "  make help           Display this help summary"

