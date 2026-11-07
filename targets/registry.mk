# Bare CUDA Arc — target pull-down registry.
#
# A "target" is one Intel GPU generation this project AOT-compiles CUDA
# kernels for, expressed as a SPIR-V profile: the portable IR that Intel's
# compute runtime (intel-compute-runtime / Level Zero) consumes. Adding a
# GPU is one file plus one line in TARGETS.
#
#   make targets          list the pull-down
#   make select           interactive pull-down (persists .target)
#   make TARGET=arc-a770 aot      override for one invocation
#   TARGET unset          the persisted .target choice (default: arc-a770)

TARGETS = arc-a770 arc-b580 flex-170

# The primary workstation target: Arc A770 16GB (Xe-HPG).
DEFAULT_TARGET = arc-a770
