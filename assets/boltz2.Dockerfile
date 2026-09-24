# 1. Use the Runtime image (no compiler/nvcc, smaller than -devel)
# CUDA 12.6 (not 12.1) is required: cuequivariance-ops-cu12's compiled
# libcue_ops.so calls cublasGemmGroupedBatchedEx, which cuBLAS only added in
# 12.5 - on cu121 it fails at import time with "undefined symbol:
# cublasGemmGroupedBatchedEx, version libcublas.so.12" (confirmed via a real
# failed BOLTZ2_REFOLD task). CUDA 12.6 bundles a cuBLAS new enough to have it.
FROM pytorch/pytorch:2.7.1-cuda12.6-cudnn9-runtime

# Set flags to keep things clean and non-interactive
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# 2. Install minimal system tools
# We need git for the install, wget for mmseqs2, and build-essential/cmake for
# 'dm-tree' and other deps that compile C++ extensions at install time. These
# also turn out to be a genuine RUNTIME dependency, not just a build-time one:
# Triton (cuequivariance-ops-torch's fallback kernel path) JIT-compiles its own
# CUDA driver bootstrap (triton/backends/nvidia/driver.py's CudaUtils) on first
# use, every time a container starts, and needs a real C compiler to do it -
# "RuntimeError: Failed to find C compiler" (confirmed via a real failed
# BOLTZ2_REFOLD task, after we used to purge build-essential/cmake post-install
# assuming they were build-time-only). Do not remove these after installing.
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    wget \
    tar \
    build-essential \
    cmake \
    && rm -rf /var/lib/apt/lists/*

# 3. Install Boltz
# We install 'rdkit' specifically to ensure the pip-optimized version is used.
#
# boltz[cuda] pulls in cuequivariance-ops-torch-cu12 with no upper bound. We used
# to pin that (and its two sibling cuequivariance packages) to 0.11.0 to stop pip
# upgrading torch past the base image's version and duplicating the CUDA install -
# but that pin caused a real, confirmed runtime failure instead: 0.11.0's own
# fallback code imports a torch.fx-internal symbol
# (`is_fx_symbolic_tracing`/`is_fx_tracing_symbolic_tracing`) that doesn't exist in
# torch 2.7.1 - "ImportError: cannot import name 'is_fx_symbolic_tracing' from
# 'torch.fx._symbolic_trace'". That's almost certainly exactly why 0.11.1 added its
# `torch>=2.11` floor: it was updated for newer torch internals. So instead of
# fighting the resolver, let it pick a mutually-compatible torch + cuequivariance
# version on its own - a bigger image is a better trade than a broken one.
#
# The base image also comes with torchvision pre-installed, built against its
# torch 2.7.1. boltz[cuda] upgrading torch (above) leaves that torchvision
# behind, and it turns out something down pytorch_lightning's own import chain
# (pytorch_lightning -> torchmetrics -> torchvision) touches it eagerly at
# import time - so it's a real, confirmed dependency, not dead weight. A stale
# torchvision's compiled ops no longer match the new torch's dispatcher:
# "RuntimeError: operator torchvision::nms does not exist" (confirmed via a
# real failed BOLTZ2_REFOLD task).
#
# Just adding unconstrained torchvision alongside boltz[cuda] isn't enough:
# pip's resolver took the path of least resistance and kept torch at the base
# image's 2.7.1 (matching an old, compatible torchvision) rather than
# upgrading - which brought back cuequivariance-ops-torch-cu12 0.11.0 and its
# torch.fx-internal-symbol bug from above. torchvision's latest release
# (0.29.0) requires torch==2.14.0 exactly, so pin both explicitly to force
# that specific, mutually-compatible, already-torch>=2.11 pair instead of
# leaving it to chance.
RUN pip install "rdkit>=2022.9.5" && \
    pip install "boltz[cuda]" "torch==2.14.0" "torchvision==0.29.0"

# Setup working directory
WORKDIR /app