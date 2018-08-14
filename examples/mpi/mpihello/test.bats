load ../../../test/common
load ./test

# Note: This file is common for both mpihello flavors. Flavor-specific setup
# is in test.bash.

count_ranks () {
      echo "$1" \
    | grep -E '^0: init ok' \
    | tail -1 \
    | sed -r 's/^.+ ([0-9]+) ranks.+$/\1/'
}

@test "$EXAMPLE_TAG/MPI version" {
    run ch-run "$IMG" -- /hello/hello
    echo "$output"
    [[ $status -eq 0 ]]
    if [[ $CHTEST_MPI = openmpi ]]; then
        [[ $output = *'Open MPI'* ]]
    else
        [[ $CHTEST_MPI = mpich ]]
        if [[ $CHTEST_CRAY ]]; then
            [[ $output = *'CRAY MPICH'* ]]
        else
            [[ $output = *'MPICH Version:'* ]]
        fi
    fi
}

@test "$EXAMPLE_TAG/serial" {
    # This seems to start up the MPI infrastructure (daemons, etc.) within the
    # guest even though there's no mpirun.
    run ch-run "$IMG" -- /hello/hello
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *' 1 ranks'* ]]
    [[ $output = *'0: send/receive ok'* ]]
    [[ $output = *'0: finalize ok'* ]]
}

@test "$EXAMPLE_TAG/guest starts ranks" {
    [[ $CHTEST_CRAY && $CHTEST_MPI = mpich ]] && skip "issue #255"
    # shellcheck disable=SC2086
    run ch-run "$IMG" -- mpirun $CHTEST_MPIRUN_NP /hello/hello
    echo "$output"
    [[ $status -eq 0 ]]
    rank_ct=$(count_ranks "$output")
    echo "found $rank_ct ranks, expected $CHTEST_CORES_NODE"
    [[ $rank_ct -eq "$CHTEST_CORES_NODE" ]]
    [[ $output = *'0: send/receive ok'* ]]
    [[ $output = *'0: finalize ok'* ]]
}

@test "$EXAMPLE_TAG/host starts ranks" {
    multiprocess_ok
    echo "starting ranks with: $MPIRUN_CORE"

    GUEST_MPI=$(ch-run "$IMG" -- mpirun --version | head -1)
    echo "guest MPI: $GUEST_MPI"

    # shellcheck disable=SC2086
    run $MPIRUN_CORE ch-run --join "$IMG" -- /hello/hello
    echo "$output"
    [[ $status -eq 0 ]]
    rank_ct=$(count_ranks "$output")
    echo "found $rank_ct ranks, expected $CHTEST_CORES_TOTAL"
    [[ $rank_ct -eq "$CHTEST_CORES_TOTAL" ]]
    [[ $output = *'0: send/receive ok'* ]]
    [[ $output = *'0: finalize ok'* ]]
}

@test "$EXAMPLE_TAG/Cray bind mounts" {
    [[ $CHTEST_CRAY ]] || skip 'host is not a Cray'
    [[ $CHTEST_MPI = openmpi ]] && skip 'OpenMPI unsupported on Cray; issue #180'

    ch-run "$IMG" -- mount | grep -F /var/opt/cray/alps/spool
    ch-run "$IMG" -- mount | grep -F /var/opt/cray/hugetlbfs
}
