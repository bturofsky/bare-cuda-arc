# Intel Arc A770 16GB — the primary workstation target.
TARGET_NAME      = arc-a770
TARGET_GPU       = Intel Arc A770 16GB
TARGET_ARCH      = Xe-HPG (DG2-512, Alchemist)
TARGET_SPIRV_ENV = spv1.5
TARGET_DRIVER    = intel-compute-runtime / Level Zero (OpenCL 3.0 full profile)
TARGET_COMPUTE   = Xe cores x vector engines; fp32 native, fp64 emulated-by-driver note recorded
TARGET_MULTI_GPU = single card; Level Zero multi-device lane (phase 3)
TARGET_ROLE      = primary — the workstation story; every artifact verified for this profile first
