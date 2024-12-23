#! /bin/bash

set -e
set -x

pip install "cmake==3.22.*"

if [ "$CIBW_ARCHS" == "aarch64" ]; then

    OPENBLAS_VERSION=0.3.21
    curl -L -O https://github.com/xianyi/OpenBLAS/releases/download/v${OPENBLAS_VERSION}/OpenBLAS-${OPENBLAS_VERSION}.tar.gz
    tar xf *.tar.gz && rm *.tar.gz
    cd OpenBLAS-*
    # NUM_THREADS: maximum value for intra_threads
    # NUM_PARALLEL: maximum value for inter_threads
    make TARGET=ARMV8 NO_SHARED=1 BUILD_SINGLE=1 NO_LAPACK=1 ONLY_CBLAS=1 USE_OPENMP=1 NUM_THREADS=32 NUM_PARALLEL=8
    make install NO_SHARED=1
    cd ..
    rm -r OpenBLAS-*

else
    # Install CUDA 12.2:
    yum-config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/rhel8/x86_64/cuda-rhel8.repo
    # error mirrorlist.centos.org doesn't exists anymore.
    sed -i s/mirror.centos.org/vault.centos.org/g /etc/yum.repos.d/*.repo
    sed -i s/^#.*baseurl=http/baseurl=http/g /etc/yum.repos.d/*.repo
    sed -i s/^mirrorlist=http/#mirrorlist=http/g /etc/yum.repos.d/*.repo
    yum install --setopt=obsoletes=0 -y \
        cuda-nvcc-12-2-12.2.140-1 \
        cuda-cudart-devel-12-2-12.2.140-1 \
        libcurand-devel-12-2-10.3.3.141-1 \
        libcudnn9-devel-cuda-12-9.1.0.70-1 \
        libcublas-devel-12-2-12.2.5.6-1 \
        libnccl-devel-2.19.3-1+cuda12.2
    ln -s cuda-12.2 /usr/local/cuda

    ONEAPI_VERSION=2023.2.0
    yum-config-manager --add-repo https://yum.repos.intel.com/oneapi
    rpm --import https://yum.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB
    yum install -y intel-oneapi-mkl-devel-$ONEAPI_VERSION

    ONEDNN_VERSION=3.1.1
    curl -L -O https://github.com/oneapi-src/oneDNN/archive/refs/tags/v${ONEDNN_VERSION}.tar.gz
    tar xf *.tar.gz && rm *.tar.gz
    cd oneDNN-*
    cmake -DCMAKE_BUILD_TYPE=Release -DONEDNN_LIBRARY_TYPE=STATIC -DONEDNN_BUILD_EXAMPLES=OFF -DONEDNN_BUILD_TESTS=OFF -DONEDNN_ENABLE_WORKLOAD=INFERENCE -DONEDNN_ENABLE_PRIMITIVE="CONVOLUTION;REORDER" -DONEDNN_BUILD_GRAPH=OFF .
    make -j$(nproc) install
    cd ..
    rm -r oneDNN-*

    OPENMPI_VERSION=4.1.6
    curl -L -O https://download.open-mpi.org/release/open-mpi/v4.1/openmpi-${OPENMPI_VERSION}.tar.bz2
    tar xf *.tar.bz2 && rm *.tar.bz2
    cd openmpi-*
    ./configure
    make -j$(nproc) install
    cd ..
    rm -r openmpi-*
    export LD_LIBRARY_PATH="/usr/local/lib/:$LD_LIBRARY_PATH"
fi

mkdir build-release && cd build-release

if [ "$CIBW_ARCHS" == "aarch64" ]; then
    cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_CLI=OFF -DWITH_MKL=OFF -DOPENMP_RUNTIME=COMP -DCMAKE_PREFIX_PATH="/opt/OpenBLAS" -DWITH_OPENBLAS=ON -DWITH_RUY=ON ..
else
    cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS="-msse4.1" -DBUILD_CLI=OFF -DWITH_DNNL=ON -DOPENMP_RUNTIME=COMP -DWITH_CUDA=ON -DWITH_CUDNN=ON -DCUDA_DYNAMIC_LOADING=ON -DCUDA_NVCC_FLAGS="-Xfatbin=-compress-all" -DCUDA_ARCH_LIST="Common"  -DWITH_TENSOR_PARALLEL=ON ..
fi

VERBOSE=1 make -j$(nproc) install
cd ..
rm -r build-release

cp README.md python/
