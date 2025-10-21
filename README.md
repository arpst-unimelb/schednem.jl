# SchedNEM

[![Build Status](https://github.com/tim-powersystems/SchedNEM.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/tim-powersystems/SchedNEM.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/tim-powersystems/SchedNEM.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/tim-powersystems/SchedNEM.jl)

Scheduling module for reliability studies of the NEM. Complementary to PRASNEM.jl.


---
## Examples

```Julia
using SchedNEM
using PRAS
sys = SystemModel("./src/sample_data/pras_files/2025-01-07_to_2025-01-13_s2_123456789101112_regions.pras")
```