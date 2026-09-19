#!/usr/bin/env bash
set -e

SCRIPT_DIR=$(dirname "$(readlink -e "${BASH_SOURCE[0]}")") && source "$SCRIPT_DIR/util.bash"

GraphBLAS=https://github.com/DrTimothyAldenDavis/GraphBLAS/archive/refs/tags/v10.5.1.zip

main() {
    set_log_depth 0
    ensure update_submodules
    ensure setup_deps
    ensure install_pnetcdf
    ensure install_graphblas
    ensure setup_venv
    ensure setup_parboil
    ensure setup_nas

    log_info "Initialization completed successfully!"
}

update_submodules() {
    enter_new_func "Updating git submodules"
    cd "$PROJECT_DIR"
    git submodule update --init --recursive
}

setup_deps() {
    enter_new_func "Setting up self-contained userspace dependencies (.deps)"
    local DEPS_DIR="$PROJECT_DIR/.deps"
    local TOOLS_DIR="$PROJECT_DIR/.tools"
    mkdir -p "$TOOLS_DIR/bin"

    # Check if micromamba is already present
    if [ ! -f "$TOOLS_DIR/bin/micromamba" ]; then
        log_info "Downloading standalone micromamba..."
        local MAMBA_URL="https://micro.mamba.pm/api/micromamba/linux-64/latest"
        curl -Ls "$MAMBA_URL" | tar -xj -C "$TOOLS_DIR" bin/micromamba
        chmod +x "$TOOLS_DIR/bin/micromamba"
    fi

    # Check if essential tools are already provisioned in .deps
    if [ ! -f "$DEPS_DIR/bin/mpicxx" ] || [ ! -f "$DEPS_DIR/bin/gfortran" ] || [ ! -f "$DEPS_DIR/bin/cmake" ]; then
        log_info "Installing toolchain (gfortran, gcc, g++, openmpi, cmake, make, m4) into .deps..."
        "$TOOLS_DIR/bin/micromamba" create -y -p "$DEPS_DIR" -c conda-forge \
            gfortran gcc gxx openmpi cmake make m4
    else
        log_info "Dependencies already present in $DEPS_DIR"
    fi
}

install_pnetcdf() {
    enter_new_func "Setting up Parallel-NetCDF (PnetCDF) in .deps"
    local DEPS_DIR="$PROJECT_DIR/.deps"

    if [ -f "$DEPS_DIR/include/pnetcdf.h" ] && [ -f "$DEPS_DIR/lib/libpnetcdf.a" ]; then
        log_info "PnetCDF already built and installed in $DEPS_DIR"
        return 0
    fi

    local PNETCDF_SRC_DIR="$DEPS_DIR/src/pnetcdf-1.15.1"
    if [ ! -d "$PNETCDF_SRC_DIR" ]; then
        mkdir -p "$DEPS_DIR/src"
        log_info "Downloading PnetCDF release 1.15.1..."
        curl -sL https://parallel-netcdf.github.io/Release/pnetcdf-1.15.1.tar.gz | tar -xz -C "$DEPS_DIR/src"
    fi

    log_info "Compiling PnetCDF into $DEPS_DIR..."
    (
        export PATH="$DEPS_DIR/bin:$PATH"
        export LD_LIBRARY_PATH="$DEPS_DIR/lib:${LD_LIBRARY_PATH:-}"
        cd "$PNETCDF_SRC_DIR"
        ./configure --prefix="$DEPS_DIR" --disable-fortran MPICC="$DEPS_DIR/bin/mpicc" MPICXX="$DEPS_DIR/bin/mpicxx"
        make -j"$(nproc)" install
    )
    log_info "PnetCDF installed successfully"
}

install_graphblas() {
    enter_new_func "Setting up GraphBLAS in .deps"
    local DEPS_DIR="$PROJECT_DIR/.deps"

    if [ -f "$DEPS_DIR/lib/libgraphblas.so" ] && [ -f "$DEPS_DIR/include/suitesparse/GraphBLAS.h" ]; then
        log_info "GraphBLAS already built and installed in $DEPS_DIR"
        return 0
    fi

    local GRAPHBLAS_SRC_DIR="$DEPS_DIR/src/GraphBLAS-10.5.1"
    local GRAPHBLAS_ZIP="$DEPS_DIR/src/GraphBLAS-10.5.1.zip"
    mkdir -p "$DEPS_DIR/src"

    if [ ! -d "$GRAPHBLAS_SRC_DIR" ]; then
        log_info "Downloading GraphBLAS from $GraphBLAS..."
        curl -fSL -o "$GRAPHBLAS_ZIP" "$GraphBLAS"
        log_info "Extracting GraphBLAS archive..."
        python3 -m zipfile -e "$GRAPHBLAS_ZIP" "$DEPS_DIR/src"
    fi

    log_info "Compiling and installing GraphBLAS into $DEPS_DIR..."
    local BUILD_DIR="$GRAPHBLAS_SRC_DIR/build"
    mkdir -p "$BUILD_DIR"
    (
        export PATH="$DEPS_DIR/bin:$PATH"
        export LD_LIBRARY_PATH="$DEPS_DIR/lib:${LD_LIBRARY_PATH:-}"
        cd "$BUILD_DIR"
        cmake -DCMAKE_INSTALL_PREFIX="$DEPS_DIR" \
              -DCMAKE_C_COMPILER="$DEPS_DIR/bin/gcc" \
              -DCMAKE_CXX_COMPILER="$DEPS_DIR/bin/g++" \
              -DSUITESPARSE_USE_FORTRAN=OFF \
              ..
        cmake --build . --config Release -j"$(nproc)"
        cmake --install .
    )
    ln -sf suitesparse/GraphBLAS.h "$DEPS_DIR/include/GraphBLAS.h"
    log_info "GraphBLAS installed successfully"
}

setup_venv() {
    enter_new_func "Setting up Python virtualenv (.venv)"
    if [ ! -f "$PROJECT_DIR/.venv/bin/python" ]; then
        log_info "Creating Python virtualenv at $PROJECT_DIR/.venv..."
        python3 -m venv "$PROJECT_DIR/.venv"
    else
        log_info "Python virtualenv already present at $PROJECT_DIR/.venv"
    fi
}

setup_parboil() {
    enter_new_func "Configuring PARBOIL benchmark suite"
    local PARBOIL_DIR="$PROJECT_DIR/PARBOIL"

    # Datasets setup
    if [ ! -d "$PARBOIL_DIR/datasets/stencil" ]; then
        if [ -f "$PARBOIL_DIR/pb2.5datasets_standard.tgz" ]; then
            log_info "Extracting Parboil datasets from $PARBOIL_DIR/pb2.5datasets_standard.tgz..."
            tar -xzf "$PARBOIL_DIR/pb2.5datasets_standard.tgz" -C "$PARBOIL_DIR"
        elif [ -f "$PROJECT_DIR/pb2.5datasets_standard.tgz" ]; then
            log_info "Extracting Parboil datasets from $PROJECT_DIR/pb2.5datasets_standard.tgz..."
            tar -xzf "$PROJECT_DIR/pb2.5datasets_standard.tgz" -C "$PARBOIL_DIR"
        else
            log_warn "Parboil dataset archive pb2.5datasets_standard.tgz not found. Datasets may need to be placed in $PARBOIL_DIR/datasets."
        fi
    else
        log_info "Parboil datasets already present in $PARBOIL_DIR/datasets"
    fi

    # Makefile.conf setup
    if [ ! -f "$PARBOIL_DIR/common/Makefile.conf" ]; then
        log_info "Generating $PARBOIL_DIR/common/Makefile.conf..."
        cp "$PARBOIL_DIR/common/Makefile.conf.example-nvidia" "$PARBOIL_DIR/common/Makefile.conf"
    fi

    # Permissions
    if [ -f "$PARBOIL_DIR/parboil" ]; then
        chmod +x "$PARBOIL_DIR/parboil"
    fi
    find "$PARBOIL_DIR/benchmarks" -name "compare-output" -exec chmod +x {} +
}

setup_nas() {
    enter_new_func "Configuring NAS benchmark suite"
    local NAS_DIR="$PROJECT_DIR/NAS"

    if [ ! -f "$NAS_DIR/config/make.def" ]; then
        log_info "Generating $NAS_DIR/config/make.def from template..."
        cp "$NAS_DIR/config/make.def.template" "$NAS_DIR/config/make.def"
    fi

    mkdir -p "$NAS_DIR/bin"
}

_setConfigArgs() {
    while [ "${1:-}" != '' ]; do
        case "$1" in
            [!-]*)
                break
                ;;
            *)
                log "$WARN" "Unknown option \"$1\", ignoring" 0
                ;;
        esac
        shift
    done
}

_setConfigArgs "$@"
main "$@"
