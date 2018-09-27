crayify_mpi_maybe () {
    if [[ $CHTEST_CRAY ]]; then
        # shellcheck disable=SC2086
        $MPIRUN_NODE ch-fromhost --cray-mpi "$1"
    fi
}

docker_tag_p () {
    printf 'image tag %s ... ' "$1"
    hash_=$(sudo docker images -q "$1" | sort -u)
    if [[ $hash_ ]]; then
        echo "$hash_"
        return 0
    else
        echo 'not found'
        return 1
    fi
}

docker_ok () {
    docker_tag_p "$1"
    docker_tag_p "$1:latest"
    docker_tag_p "$1:$(ch-run --version |& tr '~+' '--')"
}

env_require () {
    if [[ -z ${!1} ]]; then
        # shellcheck disable=SC2016
        printf '$1 is empty or not set\n\n' >&2
        exit 1
    fi
}

image_ok () {
    ls -ld "$1" "$1/WEIRD_AL_YANKOVIC" || true
    test -d "$1"
    ls -ld "$1" || true
    byte_ct=$(du -s -B1 "$1" | cut -f1)
    echo "$byte_ct"
    [[ $byte_ct -ge 3145728 ]]  # image is at least 3MiB
}

multiprocess_ok () {
    [[ $CHTEST_MULTIPROCESS ]] || skip 'no multiprocess launch tool found'
    # If the MPI in the container is MPICH, we only try host launch on Crays.
    # For the other settings (workstation, other Linux clusters), it may or
    # may not work; we simply haven't tried.
    [[ $CHTEST_MPI = mpich && -z $CHTEST_CRAY ]] \
        && skip 'MPICH untested'
    # Conversely, if the MPI in the container is OpenMPI, the current examples
    # do not use the Aries network but rather the "tcp" BTL, which has
    # grotesquely poor performance. Thus, we skip those tests as
    # well.
    [[ $CHTEST_MPI = openmpi && $CHTEST_CRAY ]] \
       && skip 'OpenMPI unsupported on Cray; issue #180'
    # Exit function successfully.
    true
}

need_docker () {
    # Skip test if $CH_TEST_SKIP_DOCKER is true. If argument provided, use
    # that tag as missing prerequisite sentinel file.
    PQ=$TARDIR/$1.pq_missing
    if [[ $PQ ]]; then
        rm -f "$PQ"
    fi
    if [[ $CH_TEST_SKIP_DOCKER ]]; then
        if [[ $PQ ]]; then
            touch "$PQ"
        fi
        skip 'Docker not found or user-skipped'
    fi
}

prerequisites_ok () {
    if [[ -f $TARDIR/$1.pq_missing ]]; then
        skip 'build prerequisites not met'
    fi
}

scope () {
    case $1 in  # $1 is the test's scope
        quick)
            ;;  # always run quick-scope tests
        standard)
            if [[ $CH_TEST_SCOPE = quick ]]; then
                skip "$1 scope"
            fi
            ;;
        full)
            if [[ $CH_TEST_SCOPE = quick || $CH_TEST_SCOPE = standard ]]; then
                skip "$1 scope"
            fi
            ;;
        skip)
            skip "developer-skipped; see comments and/or issues"
            ;;
        *)
            exit 1
    esac
}

tarball_ok () {
    ls -ld "$1" || true
    test -f "$1"
    test -s "$1"
}

# Predictable sorting and collation
export LC_ALL=C

# Set path to the right Charliecloud. This uses a symlink in this directory
# called "bin" which points to the corresponding bin directory, either simply
# up and over (source code) or set during "make install".
#
# Note that sudo resets $PATH, so if you want to run any Charliecloud stuff
# under sudo, you must use an absolute path.
CH_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/bin" && pwd)"
CH_BIN="$(readlink -f "$CH_BIN")"
export PATH=$CH_BIN:$PATH
# shellcheck disable=SC2034
CH_RUN_FILE=$(command -v ch-run)
# shellcheck disable=SC2034
CH_LIBEXEC=$(ch-build --libexec-path)
if [[ ! -x $CH_BIN/ch-run ]]; then
    printf 'Must build with "make" before running tests.\n\n' >&2
    exit 1
fi

# Charliecloud version.
CH_VERSION=$(ch-run --version 2>&1)
# shellcheck disable=SC2034
CH_VERSION_DOCKER=$(echo "$CH_VERSION" | tr '~+' '--')

# User-private temporary directory in case multiple users are running the
# tests simultaenously.
btnew=$BATS_TMPDIR/bats.tmp.$USER
mkdir -p "$btnew"
chmod 700 "$btnew"
export BATS_TMPDIR=$btnew
[[ $(stat -c %a "$BATS_TMPDIR") = '700' ]]

# Separate directories for tarballs and images
TARDIR=$CH_TEST_TARDIR
IMGDIR=$CH_TEST_IMGDIR

# MPICH requires different handling from OpenMPI. Set a variable to enable
# some kludges.
if [[ $BATS_TEST_DIRNAME =~ 'mpich' ]]; then
    CHTEST_MPI=mpich
    # First kludge. MPICH's internal launcher is called "Hydra". If Hydra sees
    # Slurm environment variables, it tries to launch even local ranks with
    # "srun". This of course fails within the container. You can't turn it off
    # by building with --without-slurm like OpenMPI, so we fall back to this
    # environment variable at run time.
    export HYDRA_LAUNCHER=fork
else
    CHTEST_MPI=openmpi
fi

# Crays are special.
if [[ -f /etc/opt/cray/release/cle-release ]]; then
    CHTEST_CRAY=yes
else
    CHTEST_CRAY=
fi

# Some test variables
EXAMPLE_TAG=$(basename "$BATS_TEST_DIRNAME")
EXAMPLE_IMG=$IMGDIR/$EXAMPLE_TAG
CHTEST_TARBALL=$TARDIR/chtest.tar.gz
CHTEST_IMG=$IMGDIR/chtest
if [[ $SLURM_JOB_ID ]]; then
    # $SLURM_NTASKS isn't always set, nor is $SLURM_CPUS_ON_NODE despite the
    # documentation.
    if [[ -z $SLURM_CPUS_ON_NODE ]]; then
        SLURM_CPUS_ON_NODE=$(echo "$SLURM_JOB_CPUS_PER_NODE" | cut -d'(' -f1)
    fi
    CHTEST_NODES=$SLURM_JOB_NUM_NODES
    CHTEST_CORES_NODE=$SLURM_CPUS_ON_NODE
else
    CHTEST_NODES=1
    CHTEST_CORES_NODE=$(getconf _NPROCESSORS_ONLN)
fi
CHTEST_CORES_TOTAL=$((CHTEST_NODES * CHTEST_CORES_NODE))
if [[ $CHTEST_MPI = mpich ]]; then
    CHTEST_MPIRUN_NP="-np $CHTEST_CORES_NODE"
else
    CHTEST_MPIRUN_NP='--use-hwthread-cpus'
fi
if [[ $SLURM_JOB_ID ]]; then
    CHTEST_MULTINODE=yes                    # can run on multiple nodes
    CHTEST_MULTIPROCESS=yes                 # can run multiple processes
    MPIRUN_NODE='srun --ntasks-per-node 1'  # one process/node
    MPIRUN_CORE='srun --cpus-per-task 1'    # one process/core
    MPIRUN_2='srun -n2'                     # two processes on different nodes
    MPIRUN_2_1NODE='srun -N1 -n2'           # two processes on one node
else
    CHTEST_MULTINODE=
    if ( command -v mpirun >/dev/null 2>&1 ); then
        CHTEST_MULTIPROCESS=yes
        MPIRUN_NODE='mpirun --map-by ppr:1:node'
        MPIRUN_CORE="mpirun $CHTEST_MPIRUN_NP"
        MPIRUN_2='mpirun -np 2'
        MPIRUN_2_1NODE='mpirun -np 2'
    else
        CHTEST_MULTIPROCESS=
        MPIRUN_NODE=''
        MPIRUN_CORE=false
        MPIRUN_2=false
        MPIRUN_2_1NODE=false
    fi
fi

# If the variable CH_TEST_SKIP_DOCKER is true, we skip all the tests that
# depend on Docker. It's true if user-set or command "docker" is not in $PATH.
if ( ! command -v docker >/dev/null 2>&1 ); then
    CH_TEST_SKIP_DOCKER=yes
fi

# Validate CH_TEST_SCOPE and set if empty.
if [[ -z $CH_TEST_SCOPE ]]; then
    CH_TEST_SCOPE=standard
elif [[    $CH_TEST_SCOPE != quick \
        && $CH_TEST_SCOPE != standard \
        && $CH_TEST_SCOPE != full ]]; then
    # shellcheck disable=SC2016
    printf '$CH_TEST_SCOPE value "%s" is invalid\n\n' $CH_TEST_SCOPE >&2
    exit 1
fi

# Do we have sudo?
if ( command -v sudo >/dev/null 2>&1 && sudo -v >/dev/null 2>&1 ); then
    # This isn't super reliable; it returns true if we have *any* sudo
    # privileges, not specifically to run the commands we want to run.
    # shellcheck disable=SC2034
    CHTEST_HAVE_SUDO=yes
fi

# Do we have what we need?
env_require CH_TEST_TARDIR
env_require CH_TEST_IMGDIR
env_require CH_TEST_PERMDIRS
if ( bash -c 'set -e; [[ 1 = 0 ]]; exit 0' ); then
    # Bash bug: [[ ... ]] expression doesn't exit with set -e
    # https://github.com/sstephenson/bats/issues/49
    printf 'Need at least Bash 4.1 for these tests.\n\n' >&2
    exit 1
fi
if ( mount | grep -Fq "$IMGDIR" ); then
    printf 'Something is mounted under %s.\n\n' "$IMGDIR" >&2
    exit 1
fi
