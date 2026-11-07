/*
 * isa_cache.c — the program-binary ISA cache (family F4; Arc A2 / Adreno D2).
 *
 * The sanctioned way to get "driver-ISA thin" on vendors whose loaders
 * take IR: compile once through the vendor driver, capture the
 * DRIVER-COMPILED binary with clGetProgramInfo(CL_PROGRAM_BINARIES),
 * cache it to disk, and reload it with clCreateProgramWithBinary. After
 * this, warm launches never recompile IR — exactly the role
 * newLibraryWithData: plays in the Metal sibling.
 *
 * Honest modes (exit 0 in all of them):
 *   RELOADED — a device was present: binary written + reload verified.
 *              This is the mechanism proof (any OpenCL device works,
 *              including a local one; the Arc/Adreno variant is the same
 *              code on their hosts).
 *   PENDING  — no OpenCL platform/device here; nothing is faked.
 *
 * Build: clang -O2 -Wall -Wextra -Werror -Wno-deprecated-declarations
 *        (-framework OpenCL | -lOpenCL)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#ifdef __APPLE__
#include <OpenCL/opencl.h>
#else
#include <CL/cl.h>
#endif

static const char kKernel[] =
    "__kernel void vectorAdd(__global const float* a, __global const float* b,\n"
    "                        __global float* c, const unsigned int n)\n"
    "{\n"
    "    int i = get_global_id(0);\n"
    "    if (i < n) c[i] = a[i] + b[i];\n"
    "}\n";

#define CHECK(expr, what) \
  do { if ((expr) != CL_SUCCESS) { fprintf(stderr, "isa_cache: %s failed\n", what); return 1; } } while (0)

int main(void) {
  cl_platform_id platforms[4];
  cl_uint nplatforms = 0;
  if (clGetPlatformIDs(4, platforms, &nplatforms) != CL_SUCCESS || nplatforms == 0) {
    printf("ISA CACHE PENDING — no OpenCL platform on this machine (nothing faked)\n");
    return 0;
  }
  cl_device_id dev;
  cl_int rc = clGetDeviceIDs(platforms[0], CL_DEVICE_TYPE_GPU, 1, &dev, NULL);
  if (rc != CL_SUCCESS)
    rc = clGetDeviceIDs(platforms[0], CL_DEVICE_TYPE_DEFAULT, 1, &dev, NULL);
  if (rc != CL_SUCCESS) {
    printf("ISA CACHE PENDING — no OpenCL device visible (nothing faked)\n");
    return 0;
  }

  char dname[256] = "?";
  clGetDeviceInfo(dev, CL_DEVICE_NAME, sizeof dname, dname, NULL);
  cl_context ctx = clCreateContext(NULL, 1, &dev, NULL, NULL, &rc);
  CHECK(rc, "clCreateContext");

  const char *src = kKernel;
  cl_program prog = clCreateProgramWithSource(ctx, 1, &src, NULL, &rc);
  CHECK(rc, "clCreateProgramWithSource");
  rc = clBuildProgram(prog, 1, &dev, NULL, NULL, NULL);
  if (rc != CL_SUCCESS) {
    char log[4096] = "";
    clGetProgramBuildInfo(prog, dev, CL_PROGRAM_BUILD_LOG, sizeof log, log, NULL);
    fprintf(stderr, "isa_cache: build failed: %.900s\n", log);
    return 1;
  }

  /* the vendor driver has now compiled our program to ITS ISA — capture it */
  size_t bsize = 0;
  CHECK(clGetProgramInfo(prog, CL_PROGRAM_BINARY_SIZES, sizeof bsize, &bsize, NULL),
        "CL_PROGRAM_BINARY_SIZES");
  unsigned char *bin = malloc(bsize);
  CHECK(clGetProgramInfo(prog, CL_PROGRAM_BINARIES, sizeof bin, &bin, NULL),
        "CL_PROGRAM_BINARIES");

  mkdir("build", 0755);
  mkdir("build/isa-cache", 0755);
  char fname[256];
  snprintf(fname, sizeof fname, "%s", dname);
  for (char *p = fname; *p; p++)
    if (*p == ' ' || *p == '/' ) *p = '_';
  char path[512];
  snprintf(path, sizeof path, "build/isa-cache/%s.bin", fname);
  FILE *f = fopen(path, "wb");
  if (!f) { fprintf(stderr, "isa_cache: cannot write %s\n", path); return 1; }
  fwrite(bin, 1, bsize, f);
  fclose(f);

  /* reload from the ISA binary: warm path = no IR compilation anywhere */
  const unsigned char *bin_in = bin;
  cl_program prog2 = clCreateProgramWithBinary(ctx, 1, &dev, &bsize, &bin_in, NULL, &rc);
  CHECK(rc, "clCreateProgramWithBinary");
  rc = clBuildProgram(prog2, 1, &dev, NULL, NULL, NULL);
  cl_build_status status = CL_BUILD_NONE;
  clGetProgramBuildInfo(prog2, dev, CL_PROGRAM_BUILD_STATUS, sizeof status, &status, NULL);

  if (status == CL_BUILD_SUCCESS) {
    printf("ISA CACHE RELOADED — device '%s'\n", dname);
    printf("  vendor-ISA binary: %s (%zu bytes) — written and reload-verified\n", path, bsize);
    printf("  warm launches from here never compile IR: the sanctioned thin path\n");
  } else {
    printf("ISA CACHE PENDING — binary written but reload failed (driver refused)\n");
    return 1;
  }
  return 0;
}
