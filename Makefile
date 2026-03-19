SHELL := /bin/bash

.PHONY: fmt lint calibrate analyze

fmt:
	terraform -chdir=terraform fmt -recursive

lint:
	@echo "Add tflint/kubeval if you want"

# ─── Calibration ───────────────────────────────────────────────────────────────
# Run calibration sweep on Mode A (baseline) before benchmark runs.
# Override MODE=A|B, REPEAT=2 (or more), CAL_QPS_START/END/STEP for custom ranges.
calibrate:
	@echo "=== Calibration sweep ==="
	@echo "1) Ensure workload is deployed: kubectl apply -f workload/server/ workload/client/"
	@echo "2) Ensure Cilium (Mode A) is installed"
	MODE=A REPEAT=2 ./scripts/calibrate.sh

# ─── Statistical Analysis ─────────────────────────────────────────────────────
# Run after benchmark results are available.
analyze:
	python3 scripts/analyze_results.py

# ─── Full pipeline (calibrate → benchmark → analyze) ──────────────────────────
# Requires MODE and LOAD set. Example:
#   make pipeline MODE=A LOAD=L1 REPEAT=3
pipeline:
	@if [ -z "$(MODE)" ]; then echo "MODE must be set, e.g. MODE=A"; exit 1; fi
	@if [ -z "$(LOAD)" ]; then echo "LOAD must be set, e.g. LOAD=L1"; exit 1; fi
	@echo "=== Benchmark pipeline: MODE=$(MODE) LOAD=$(LOAD) REPEAT=$(REPEAT) ==="
	./scripts/run_s1.sh
	python3 scripts/analyze_results.py
