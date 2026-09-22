#!/usr/bin/env bash
set -e

SCRIPT_DIR=$(dirname "$(readlink -e "${BASH_SOURCE[0]}")") && source "$SCRIPT_DIR/util.bash"
main() {
    set_log_depth 0
    ensure update_submodules
    ensure setup_deps
    ensure install_pnetcdf
    ensure ensure_uv
    ensure setup_venv
    ensure setup_parboil
    ensure setup_nas

    log_info "Initialization completed successfully!"
}

update_submodules() {
    enter_new_func "Updating git submodules"
    cd "$PROJECT_DIR"
    git submodule update --init
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

#there may be a better way to do this
find_system_library() {
    local header_names;
    local lib_pattern="$2"
    local env_vars=;
    local pkg_names; 
    local config_tool="${5:-}"
    local DEPS_DIR="$PROJECT_DIR/.deps"
    read -r -a header_names <<< "$1"
    read -r -a env_vars <<< "$3"
    read -r -a pkg_names <<< "$4"

    unset SYSTEM_INC_DIR SYSTEM_LIB_DIR

    _check_dirs() {
        local inc="$1"
        local lib="$2"
        if [ -z "$inc" ] || [ -z "$lib" ] || [ ! -d "$inc" ] || [ ! -d "$lib" ]; then
            return 1
        fi
        if [[ "$inc" == "$DEPS_DIR"* ]] || [[ "$lib" == "$DEPS_DIR"* ]]; then
            return 1
        fi
        local hdr_found=false
        for h in "${header_names[@]}"; do
            if [ -f "$inc/$h" ]; then
                hdr_found=true
                break
            fi
        done
        if [ "$hdr_found" != "true" ]; then
            return 1
        fi
        if compgen -G "$lib/$lib_pattern" >/dev/null; then
            SYSTEM_INC_DIR="$inc"
            SYSTEM_LIB_DIR="$lib"
            return 0
        fi
        return 1
    }

    # 1. Environment variables
    for var in "${env_vars[@]}"; do
        local dir="${!var:-}"
        if [ -n "$dir" ] && [ -d "$dir" ] && [ "$dir" != "$DEPS_DIR" ]; then
            for inc_sub in include include/suitesparse ""; do
                local inc_path="$dir"
                [ -n "$inc_sub" ] && inc_path="$dir/$inc_sub"
                for lib_sub in lib lib64 ""; do
                    local lib_path="$dir"
                    [ -n "$lib_sub" ] && lib_path="$dir/$lib_sub"
                    if _check_dirs "$inc_path" "$lib_path"; then
                        return 0
                    fi
                done
            done
        fi
    done

    # 2. Config tool (e.g. pnetcdf-config)
    if [ -n "$config_tool" ] && command -v "$config_tool" >/dev/null 2>&1; then
        local cfg_path
        cfg_path=$(command -v "$config_tool")
        if [[ "$cfg_path" != "$DEPS_DIR"* ]]; then
            local inc lib
            inc=$("$cfg_path" --includedir 2>/dev/null || true)
            lib=$("$cfg_path" --libdir 2>/dev/null || true)
            if _check_dirs "$inc" "$lib"; then
                return 0
            fi
        fi
    fi

    # 3. pkg-config
    if command -v pkg-config >/dev/null 2>&1; then
        for pc in "${pkg_names[@]}"; do
            if pkg-config --exists "$pc" 2>/dev/null; then
                local inc lib
                inc=$(pkg-config --variable=includedir "$pc" 2>/dev/null || true)
                lib=$(pkg-config --variable=libdir "$pc" 2>/dev/null || true)
                if _check_dirs "$inc" "$lib"; then
                    return 0
                fi
            fi
        done
    fi

    # 4. Standard system search paths
    local standard_incs=(
        "/usr/include"
        "/usr/include/suitesparse"
        "/usr/local/include"
        "/usr/local/include/suitesparse"
        "/opt/local/include"
        "/opt/local/include/suitesparse"
        "/usr/include/pnetcdf"
    )
    local standard_libs=(
        "/usr/lib"
        "/usr/lib64"
        "/usr/lib/x86_64-linux-gnu"
        "/usr/local/lib"
        "/usr/local/lib64"
    )

    for inc in "${standard_incs[@]}"; do
        for lib in "${standard_libs[@]}"; do
            if _check_dirs "$inc" "$lib"; then
                return 0
            fi
        done
    done

    return 1
}

install_from_system() {
    local lib_name="$1"
    local inc_dir="$2"
    local lib_dir="$3"
    local lib_pattern="$4"
    local headers;
    local pkg_pc="${6:-}"
    local cmake_name="${7:-}"
    local DEPS_DIR="$PROJECT_DIR/.deps"
    read -r -a headers <<< "$5"

    log_info "Found system $lib_name (include: $inc_dir, lib: $lib_dir). Using system $lib_name."
    mkdir -p "$DEPS_DIR/include" "$DEPS_DIR/lib"

    for hdr in "${headers[@]}"; do
        if [ -f "$inc_dir/$hdr" ]; then
            mkdir -p "$(dirname "$DEPS_DIR/include/$hdr")"
            ln -sf "$inc_dir/$hdr" "$DEPS_DIR/include/$hdr"
        fi
    done

    # GraphBLAS compatibility: ensure both include/GraphBLAS.h and include/suitesparse/GraphBLAS.h exist
    if [ "$lib_name" = "GraphBLAS" ]; then
        mkdir -p "$DEPS_DIR/include/suitesparse"
        if [ -f "$inc_dir/GraphBLAS.h" ]; then
            ln -sf "$inc_dir/GraphBLAS.h" "$DEPS_DIR/include/GraphBLAS.h"
            ln -sf "$inc_dir/GraphBLAS.h" "$DEPS_DIR/include/suitesparse/GraphBLAS.h"
        elif [ -f "$inc_dir/suitesparse/GraphBLAS.h" ]; then
            ln -sf "$inc_dir/suitesparse/GraphBLAS.h" "$DEPS_DIR/include/GraphBLAS.h"
            ln -sf "$inc_dir/suitesparse/GraphBLAS.h" "$DEPS_DIR/include/suitesparse/GraphBLAS.h"
        fi
    fi

    for libfile in "$lib_dir"/$lib_pattern; do
        if [ -e "$libfile" ]; then
            ln -sf "$libfile" "$DEPS_DIR/lib/$(basename "$libfile")"
        fi
    done

    if [ -n "$pkg_pc" ] && [ -f "$lib_dir/pkgconfig/$pkg_pc.pc" ]; then
        mkdir -p "$DEPS_DIR/lib/pkgconfig"
        ln -sf "$lib_dir/pkgconfig/$pkg_pc.pc" "$DEPS_DIR/lib/pkgconfig/$pkg_pc.pc"
    fi

    if [ -n "$cmake_name" ] && [ -d "$lib_dir/cmake/$cmake_name" ]; then
        mkdir -p "$DEPS_DIR/lib/cmake"
        ln -sfn "$lib_dir/cmake/$cmake_name" "$DEPS_DIR/lib/cmake/$cmake_name"
    fi

    log_info "System $lib_name linked into $DEPS_DIR"
}

install_from_mamba() {
    local pkg_name="$1"
    local check_header="$2"
    local check_lib_pattern="$3"
    local DEPS_DIR="$PROJECT_DIR/.deps"
    local TOOLS_DIR="$PROJECT_DIR/.tools"

    # If the check header is a symlink pointing outside .deps, remove it so mamba installs cleanly
    if [ -L "$DEPS_DIR/include/$check_header" ]; then
        local target
        target=$(readlink -f "$DEPS_DIR/include/$check_header" || true)
        if [[ "$target" != "$DEPS_DIR"* ]]; then
            rm -f "$DEPS_DIR/include/$check_header"
        fi
    fi

    if [ -f "$DEPS_DIR/include/$check_header" ] && compgen -G "$DEPS_DIR/lib/$check_lib_pattern" >/dev/null; then
        log_info "$pkg_name already installed in $DEPS_DIR"
        return 0
    fi

    log_info "Installing $pkg_name via micromamba into $DEPS_DIR..."
    local force_flag=()
    if compgen -G "$DEPS_DIR/conda-meta/${pkg_name}-*.json" >/dev/null; then
        force_flag=("--force-reinstall")
    fi
    "$TOOLS_DIR/bin/micromamba" install "${force_flag[@]}" -y -p "$DEPS_DIR" -c conda-forge "$pkg_name"
    log_info "$pkg_name installed successfully via micromamba"
}

install_pnetcdf() {
    enter_new_func "Setting up PnetCDF in .deps"
    local maybe_vars="PNETCDF_DIR PNETCDF_ROOT PARALLEL_NETCDF OLCF_PARALLEL_NETCDF_ROOT"
    local maybe_headers="pnetcdf.h pnetcdf pnetcdf.inc pnetcdf.mod"

    if find_system_library "pnetcdf.h" "libpnetcdf.*" "$maybe_vars" "pnetcdf" "pnetcdf-config"; then
        install_from_system "PnetCDF" "$SYSTEM_INC_DIR" "$SYSTEM_LIB_DIR" "libpnetcdf.*" "$maybe_headers" "pnetcdf"
        return 0
    fi

    log_info "System PnetCDF not found. Using micromamba..."
    install_from_mamba "libpnetcdf" "pnetcdf.h" "libpnetcdf.*"
}

setup_venv() {
    enter_new_func "Setting up Python virtualenv (.venv)"
    if [ ! -f "$PROJECT_DIR/.venv/bin/python" ]; then
        log_info "Creating Python uv venv at $PROJECT_DIR/.venv..."
        uv venv --python 3.12 "$PROJECT_DIR/.venv"
    else
        log_info "Python virtualenv already present at $PROJECT_DIR/.venv"
    fi
}

setup_parboil() {
    enter_new_func "Configuring PARBOIL benchmark suite"
    local PARBOIL_DIR="$PROJECT_DIR/PARBOIL"

    if [ ! -d "$PARBOIL_DIR/datasets/spmv" ]; then
        mkdir -p "$PARBOIL_DIR/datasets"
        curl -Ls https://github.com/Jubarte27/energyuq-data/raw/refs/heads/main/spmv.tar.gz | tar -xz -C "$PARBOIL_DIR/datasets"
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
