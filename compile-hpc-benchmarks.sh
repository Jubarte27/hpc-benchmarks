#!/bin/bash
set -e

main() {
    set_log_depth 0
    cd "$BENCHMARKS_DIR" || exit 1

    if [ "$JUSTCLEAN" == "true" ]; then
        clean || exit 1
        return
    fi

    if ! [ -z ${BENCHMARKS_TO_CONSIDER+x} ]; then
        for bench in "${BENCHMARKS_TO_CONSIDER[@]}"; do
            compile_benchmark "$bench"
        done
        return
    fi

    compile_ja
    compile_po
    compile_st
    compile_lulesh
    compile_hpcg
    compile_rodinia
    compile_nas
    compile_parboil
    compile_mw
    compile_lagraph
}

compile_ja() {
    silent_make JA
}

compile_po() {
    silent_make PO
}

compile_st() {
    silent_make ST
}

compile_lulesh() {
    silent_make LULESH
}

compile_hpcg() {
    silent_make HPCG
}

compile_rodinia() {
    silent_make RODINIA/openmp/streamcluster
    make -C RODINIA/openmp/hotspot hotspot
    silent_make RODINIA/data/hotspot/inputGen
    silent_make RODINIA/openmp/hotspot3D
    silent_make RODINIA/openmp/srad
    make -C RODINIA/openmp/bfs bfs
}

compile_nas() {
    if [ ! -f "$BENCHMARKS_DIR/NAS/config/make.def" ]; then
        cp "$BENCHMARKS_DIR/NAS/config/make.def.template" "$BENCHMARKS_DIR/NAS/config/make.def"
    fi
    mkdir -p "$BENCHMARKS_DIR/NAS/bin"
    silent_make NAS BT CLASS=C
    silent_make NAS CG CLASS=C
    silent_make NAS FT CLASS=C
    silent_make NAS IS CLASS=C
    silent_make NAS LU CLASS=C
    silent_make NAS MG CLASS=C
    silent_make NAS EP CLASS=C
    silent_make NAS SP CLASS=C
    silent_make NAS UA CLASS=C
}

compile_parboil() {
    if [ ! -f "$BENCHMARKS_DIR/PARBOIL/common/Makefile.conf" ]; then
        cp "$BENCHMARKS_DIR/PARBOIL/common/Makefile.conf.example-nvidia" "$BENCHMARKS_DIR/PARBOIL/common/Makefile.conf"
    fi
    (cd "$BENCHMARKS_DIR/PARBOIL" && ./parboil compile stencil omp_base)
}

compile_mw() {
    local MW_BUILD_DIR="$BENCHMARKS_DIR/MW/c/build"
    mkdir -p "$MW_BUILD_DIR"
    (
        cd "$MW_BUILD_DIR"
        cmake -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
              -DCMAKE_CXX_COMPILER=mpic++ \
              -DCXXFLAGS="-I$PROJECT_DIR/.deps/include" \
              -DLDFLAGS="-L$PROJECT_DIR/.deps/lib -lpnetcdf" \
              -DOPENMP_FLAGS="-fopenmp" \
              ..
        make
    )
}

compile_lagraph() {
    local LAGRAPH_BUILD_DIR="$BENCHMARKS_DIR/LAGRAPH/build"
    mkdir -p "$LAGRAPH_BUILD_DIR"
    (
        cd "$LAGRAPH_BUILD_DIR"
        cmake -DCMAKE_INSTALL_PREFIX="$PROJECT_DIR/.deps" \
              -DCMAKE_C_COMPILER="$PROJECT_DIR/.deps/bin/gcc" \
              -DCMAKE_CXX_COMPILER="$PROJECT_DIR/.deps/bin/g++" \
              -DGraphBLAS_ROOT="$PROJECT_DIR/.deps" \
              -DSUITESPARSE_USE_FORTRAN=OFF \
              ..
        cmake --build . --config Release -j"$(nproc)"
    )
}

compile_benchmark() {
    local bench="$1"
    case "$bench" in
        JA)
            compile_ja
            ;;
        PO)
            compile_po
            ;;
        ST)
            compile_st
            ;;
        LULESH)
            compile_lulesh
            ;;
        HPCG)
            compile_hpcg
            ;;
        RODINIA)
            compile_rodinia
            ;;
        NAS)
            compile_nas
            ;;
        PARBOIL)
            compile_parboil
            ;;
        MW)
            compile_mw
            ;;
        LAGRAPH)
            compile_lagraph
            ;;
        *)
            silent_make "$bench"
            ;;
    esac
}

clean() {
    clean_make JA
    clean_make PO
    clean_make ST
    clean_make LULESH
    clean_make HPCG

    clean_make RODINIA/openmp/hotspot
    clean_make RODINIA/openmp/streamcluster
    clean_make RODINIA/data/hotspot/inputGen
    clean_make RODINIA/openmp/hotspot3D
    clean_make RODINIA/openmp/srad
    clean_make RODINIA/openmp/bfs

    silent_make NAS clean

    if [ -d "$BENCHMARKS_DIR/PARBOIL" ]; then
        (cd "$BENCHMARKS_DIR/PARBOIL" && ./parboil clean stencil omp_base)
    fi
    clean_submodules
}

clean_submodules() {
    # Clean miniWeather (MW) build directories
    if [ -f "$BENCHMARKS_DIR/MW/c/build/cmake_clean.sh" ]; then
        (cd "$BENCHMARKS_DIR/MW/c/build" && bash cmake_clean.sh)
    elif [ -d "$BENCHMARKS_DIR/MW/c/build" ]; then
        rm -rf "$BENCHMARKS_DIR/MW/c/build"/CMakeCache.txt "$BENCHMARKS_DIR/MW/c/build"/CMakeFiles \
               "$BENCHMARKS_DIR/MW/c/build"/CTestTestfile.cmake "$BENCHMARKS_DIR/MW/c/build"/Makefile \
               "$BENCHMARKS_DIR/MW/c/build"/cmake_install.cmake "$BENCHMARKS_DIR/MW/c/build"/Testing \
               "$BENCHMARKS_DIR/MW/c/build"/mpi* "$BENCHMARKS_DIR/MW/c/build"/open* \
               "$BENCHMARKS_DIR/MW/c/build"/serial* "$BENCHMARKS_DIR/MW/c/build"/output.nc
    fi

    if [ -f "$BENCHMARKS_DIR/MW/cpp/build/cmake_clean.sh" ]; then
        (cd "$BENCHMARKS_DIR/MW/cpp/build" && bash cmake_clean.sh)
    fi

    # Clean LAGRAPH build directory
    if [ -d "$BENCHMARKS_DIR/LAGRAPH/build" ]; then
        rm -rf "$BENCHMARKS_DIR/LAGRAPH/build"/*
    fi

    # Clean untracked/ignored build artifacts across all git submodules recursively
    if [ -d "$BENCHMARKS_DIR/.git" ]; then
        git -C "$BENCHMARKS_DIR" submodule foreach --recursive 'git clean -fdx'
    fi
}

clean_make() {
    if [ -d "$1" ]; then
        make -C "$1" clean
    fi
}

silent_make() {
    make --silent -C "$@"
}

_setConfigArgs() {
    while [ "${1:-}" != '' ]; do
        case "$1" in
            ## Options
            -c | --clean)
                JUSTCLEAN=true
                ;;
            -s | --silent)
                SILENT=true
                ;;
            ## end of Options
            [!-]*)
                break
                ;;
            *)
                log "$WARN" "Unknown option \"$1\", ignoring" 0 
            ;;
        esac
        shift
    done

    if ! [ -z "$1" ]; then
        IFS=, read -r -a BENCHMARKS_TO_CONSIDER <<< "$1"
    fi
}

set_env() {
    BENCHMARKS_DIR="$PROJECT_DIR"

    # Prioritize project userspace dependencies (.deps)
    if [ -d "$PROJECT_DIR/.deps/bin" ]; then
        export PATH="$PROJECT_DIR/.deps/bin:$PATH"
    fi
    if [ -d "$PROJECT_DIR/.deps/lib" ]; then
        export LD_LIBRARY_PATH="$PROJECT_DIR/.deps/lib:${LD_LIBRARY_PATH:-}"
    fi

    # Prioritize project python virtualenv (.venv)
    if [ -d "$PROJECT_DIR/.venv/bin" ]; then
        export PATH="$PROJECT_DIR/.venv/bin:$PATH"
    fi
}

SCRIPT_DIR=$(dirname "$(readlink -e "${BASH_SOURCE[0]}")") && source "$SCRIPT_DIR/util.bash"
_setConfigArgs "$@"
if [ "${SILENT:-false}" = "true" ]; then
    exec >/dev/null 2>&1
fi
set_env
main "$@"
