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
    make --silent -C RODINIA/openmp/hotspot hotspot
    silent_make RODINIA/data/hotspot/inputGen
    silent_make RODINIA/openmp/hotspot3D
    silent_make RODINIA/openmp/srad
    make --silent -C RODINIA/openmp/bfs bfs
}

compile_nas() {
    if [ ! -f "$BENCHMARKS_DIR/NAS/config/make.def" ]; then
        cp "$BENCHMARKS_DIR/NAS/config/make.def.template" "$BENCHMARKS_DIR/NAS/config/make.def"
    fi
    mkdir -p "$BENCHMARKS_DIR/NAS/bin"
    {
        silent_make NAS BT CLASS=C
        silent_make NAS CG CLASS=C
        silent_make NAS FT CLASS=C
        silent_make NAS IS CLASS=C
        silent_make NAS LU CLASS=C
        silent_make NAS MG CLASS=C
        silent_make NAS EP CLASS=C
        silent_make NAS SP CLASS=C
        silent_make NAS UA CLASS=C
    } > /dev/null
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
              .. >/dev/null
        make --silent
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

    (cd "$BENCHMARKS_DIR/PARBOIL" && ./parboil clean stencil omp_base 2>/dev/null || true)
    (cd "$BENCHMARKS_DIR/MW/c/build" && make --silent clean 2>/dev/null || true)
}

clean_make() {
    if [ -d "$1" ]; then
        make --silent -C "$1" clean 2>/dev/null || true
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
set_env
main "$@"
