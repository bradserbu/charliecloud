load ../common

fromhost_clean () {
    [[ $1 ]]
    for file in {lib,mnt,usr/bin}/sotest \
                {lib,mnt,usr/lib,usr/local/lib}/libsotest.so.1{.0,} \
                /usr/local/cuda-9.1/targets/x86_64-linux/lib/libsotest.so.1{.0,} \
                /mnt/sotest.c \
                /etc/ld.so.cache ; do
        rm -f "$1/$file"
    done
    ch-run -w "$1" -- /sbin/ldconfig  # restore default cache
    fromhost_clean_p "$1"
}

fromhost_clean_p () {
    ch-run "$1" -- /sbin/ldconfig -p | grep -F libsotest && return 1
    run fromhost_ls "$1"
    echo "$output"
    [[ $status -eq 0 ]]
    [[ -z $output ]]
}

fromhost_ls () {
    find "$1" -xdev -name '*sotest*' -ls
}

@test 'ch-fromhost (Debian)' {
    scope standard
    prerequisites_ok debian9
    IMG=$IMGDIR/debian9

    # inferred path is what we expect
    [[ $(ch-fromhost --lib-path "$IMG") = /usr/local/lib ]]

    # --file
    fromhost_clean "$IMG"
    ch-fromhost -v --file sotest/files_inferrable.txt "$IMG"
    fromhost_ls "$IMG"
    test -f "$IMG/usr/bin/sotest"
    test -f "$IMG/usr/local/lib/libsotest.so.1.0"
    test -L "$IMG/usr/local/lib/libsotest.so.1"
    ch-run "$IMG" -- /sbin/ldconfig -p | grep -F libsotest
    ch-run "$IMG" -- sotest
    rm "$IMG/usr/bin/sotest"
    rm "$IMG/usr/local/lib/libsotest.so.1.0"
    rm "$IMG/usr/local/lib/libsotest.so.1"
    ch-run -w "$IMG" -- /sbin/ldconfig
    fromhost_clean_p "$IMG"

    # --cmd
    ch-fromhost -v --cmd 'cat sotest/files_inferrable.txt' "$IMG"
    ch-run "$IMG" -- sotest
    fromhost_clean "$IMG"

    # --path
    ch-fromhost -v --path sotest/bin/sotest \
                   --path sotest/lib/libsotest.so.1.0 \
                   "$IMG"
    ch-run "$IMG" -- sotest
    fromhost_clean "$IMG"

    # --cmd and --file
    ch-fromhost -v --cmd 'cat sotest/files_inferrable.txt' \
                   --file sotest/files_inferrable.txt "$IMG"
    ch-run "$IMG" -- sotest
    fromhost_clean "$IMG"

    # --dest
    ch-fromhost -v --file sotest/files_inferrable.txt \
                   --dest /mnt "$IMG" \
                   --path sotest/sotest.c
    ch-run "$IMG" -- sotest
    ch-run "$IMG" -- test -f /mnt/sotest.c
    fromhost_clean "$IMG"

    # --dest overrides inference, but ldconfig still run
    ch-fromhost -v --dest /lib \
                   --file sotest/files_inferrable.txt \
                   "$IMG"
    ch-run "$IMG" -- /lib/sotest
    fromhost_clean "$IMG"

    # --no-ldconfig
    ch-fromhost -v --no-ldconfig --file sotest/files_inferrable.txt "$IMG"
    test -f "$IMG/usr/bin/sotest"
    test -f "$IMG/usr/local/lib/libsotest.so.1.0"
    ! test -L "$IMG/usr/local/lib/libsotest.so.1"
    ! ( ch-run "$IMG" -- /sbin/ldconfig -p | grep -F libsotest )
    run ch-run "$IMG" -- sotest
    echo "$output"
    [[ $status -eq 127 ]]
    [[ $output = *'libsotest.so.1: cannot open shared object file'* ]]
    fromhost_clean "$IMG"

    # no --verbose
    ch-fromhost --file sotest/files_inferrable.txt "$IMG"
    ch-run "$IMG" -- sotest
    fromhost_clean "$IMG"
}

@test 'ch-fromhost (CentOS)' {
    scope full
    prerequisites_ok centos7
    IMG=$IMGDIR/centos7

    fromhost_clean "$IMG"
    ch-fromhost -v --file sotest/files_inferrable.txt "$IMG"
    fromhost_ls "$IMG"
    test -f "$IMG/usr/bin/sotest"
    test -f "$IMG/lib/libsotest.so.1.0"
    test -L "$IMG/lib/libsotest.so.1"
    ch-run "$IMG" -- /sbin/ldconfig -p | grep -F libsotest
    ch-run "$IMG" -- sotest
    rm "$IMG/usr/bin/sotest"
    rm "$IMG/lib/libsotest.so.1.0"
    rm "$IMG/lib/libsotest.so.1"
    rm "$IMG/etc/ld.so.cache"
    fromhost_clean_p "$IMG"
}

@test 'ch-fromhost errors' {
    scope standard
    prerequisites_ok debian9
    IMG=$IMGDIR/debian9

    # no image
    run ch-fromhost --path sotest/sotest.c
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'no image specified'* ]]
    fromhost_clean_p "$IMG"

    # image is not a directory
    run ch-fromhost --path sotest/sotest.c /etc/motd
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'image not a directory: /etc/motd'* ]]
    fromhost_clean_p "$IMG"

    # two image arguments
    run ch-fromhost --path sotest/sotest.c "$IMG" foo
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'duplicate image: foo'* ]]
    fromhost_clean_p "$IMG"

    # no files argument
    run ch-fromhost "$IMG"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'empty file list'* ]]
    fromhost_clean_p "$IMG"

    # file that needs --dest but not specified
    run ch-fromhost -v --path sotest/sotest.c "$IMG"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'no destination for: sotest/sotest.c'* ]]
    fromhost_clean_p "$IMG"

    # file with colon in name
    run ch-fromhost -v --path 'foo:bar' "$IMG"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"paths can't contain colon: foo:bar"* ]]
    fromhost_clean_p "$IMG"
    # file with newlines in name
    run ch-fromhost -v --path $'foo\nbar' "$IMG"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"no destination for: foo"* ]]
    fromhost_clean_p "$IMG"

    # --cmd no argument
    run ch-fromhost "$IMG" --cmd
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'--cmd must not be empty'* ]]
    fromhost_clean_p "$IMG"
    # --cmd empty
    run ch-fromhost --cmd true "$IMG"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'empty file list'* ]]
    fromhost_clean_p "$IMG"
    # --cmd fails
    run ch-fromhost --cmd false "$IMG"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'command failed: false'* ]]
    fromhost_clean_p "$IMG"

    # --file no argument
    run ch-fromhost "$IMG" --file
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'--file must not be empty'* ]]
    fromhost_clean_p "$IMG"
    # --file empty
    run ch-fromhost --file /dev/null "$IMG"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'empty file list'* ]]
    fromhost_clean_p "$IMG"
    # --file does not exist
    run ch-fromhost --file /doesnotexist "$IMG"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'/doesnotexist: No such file or directory'* ]]
    [[ $output = *'cannot read file: /doesnotexist'* ]]
    fromhost_clean_p "$IMG"

    # --path no argument
    run ch-fromhost "$IMG" --path
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'--path must not be empty'* ]]
    fromhost_clean_p "$IMG"
    # --path does not exist
    run ch-fromhost --dest /mnt --path /doesnotexist "$IMG"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'No such file or directory'* ]]
    [[ $output = *'cannot inject: /doesnotexist'* ]]
    fromhost_clean_p "$IMG"

    # --dest no argument
    run ch-fromhost "$IMG" --dest
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'--dest must not be empty'* ]]
    fromhost_clean_p "$IMG"
    # --dest not an absolute path
    run ch-fromhost --dest relative --path sotest/sotest.c "$IMG"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'not an absolute path: relative'* ]]
    fromhost_clean_p "$IMG"
    # --dest does not exist
    run ch-fromhost --dest /doesnotexist --path sotest/sotest.c "$IMG"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'not a directory:'* ]]
    fromhost_clean_p "$IMG"
    # --dest is not a directory
    run ch-fromhost --dest /bin/sh --file sotest/sotest.c "$IMG"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'not a directory:'* ]]
    fromhost_clean_p "$IMG"

    # image does not exist
    run ch-fromhost --file sotest/files_inferrable.txt /doesnotexist
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'image not a directory: /doesnotexist'* ]]
    fromhost_clean_p "$IMG"
    # image specified twice
    run ch-fromhost --file sotest/files_inferrable.txt "$IMG" "$IMG"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'duplicate image'* ]]
    fromhost_clean_p "$IMG"
}

@test 'ch-fromhost --cray-mpi not on a Cray' {
    scope full
    [[ $CHTEST_CRAY ]] && skip 'host is a Cray'
    run ch-fromhost --cray-mpi "$CHTEST_IMG"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *'are you on a Cray?'* ]]
}

@test 'ch-fromhost --cray-mpi with no MPI installed' {
    scope full
    [[ $CHTEST_CRAY ]] || skip 'host is not a Cray'
    run ch-fromhost --cray-mpi "$CHTEST_IMG"
    echo "$output"
    [[ $status -eq 1 ]]
    [[ $output = *"can't find MPI in image"* ]]
}

@test 'ch-fromhost --nvidia with GPU' {
    scope full
    prerequisites_ok nvidia
    command -v nvidia-container-cli >/dev/null 2>&1 \
        || skip 'nvidia-container-cli not in PATH'
    IMG=$IMGDIR/nvidia

    # nvidia-container-cli --version (to make sure it's linked correctly)
    nvidia-container-cli --version

    # Skip if nvidia-container-cli can't find CUDA.
    run nvidia-container-cli list --binaries --libraries
    echo "$output"
    if [[ $status -eq 1 ]]; then
        if [[ $output = *'cuda error'* ]]; then
            skip "nvidia-container-cli can't find CUDA"
        fi
        false
    fi

    # --nvidia
    ch-fromhost -v --nvidia "$IMG"

    # nvidia-smi runs in guest
    ch-run "$IMG" -- nvidia-smi -L

    # nvidia-smi -L matches host
    host=$(nvidia-smi -L)
    echo "host GPUs:"
    echo "$host"
    guest=$(ch-run "$IMG" -- nvidia-smi -L)
    echo "guest GPUs:"
    echo "$guest"
    cmp <(echo "$host") <(echo "$guest")

    # --nvidia and --cmd
    fromhost_clean "$IMG"
    ch-fromhost --nvidia --file sotest/files_inferrable.txt "$IMG"
    ch-run "$IMG" -- nvidia-smi -L
    ch-run "$IMG" -- sotest
    # --nvidia and --file
    fromhost_clean "$IMG"
    ch-fromhost --nvidia --cmd 'cat sotest/files_inferrable.txt' "$IMG"
    ch-run "$IMG" -- nvidia-smi -L
    ch-run "$IMG" -- sotest

    # CUDA sample
    SAMPLE=/matrixMulCUBLAS
    # should fail without ch-fromhost --nvidia
    fromhost_clean "$IMG"
    run ch-run "$IMG" -- $SAMPLE
    echo "$output"
    [[ $status -eq 127 ]]
    [[ $output =~ 'matrixMulCUBLAS: error while loading shared libraries' ]]
    # should succeed with it
    fromhost_clean_p "$IMG"
    ch-fromhost --nvidia "$IMG"
    run ch-run "$IMG" -- $SAMPLE
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output =~ 'Comparing CUBLAS Matrix Multiply with CPU results: PASS' ]]
}

@test 'ch-fromhost --nvidia without GPU' {
    scope full
    prerequisites_ok nvidia
    IMG=$IMGDIR/nvidia

    # --nvidia should give a proper error whether or not nvidia-container-cli
    # is available.
    if ( command -v nvidia-container-cli >/dev/null 2>&1 ); then
        # nvidia-container-cli in $PATH
        run nvidia-container-cli list --binaries --libraries
        echo "$output"
        if [[ $status -eq 0 ]]; then
            # found CUDA; skip
            skip 'nvidia-container-cli found CUDA'
        else
            [[ $status -eq 1 ]]
            [[ $output = *'cuda error'* ]]
            run ch-fromhost -v --nvidia "$IMG"
            echo "$output"
            [[ $status -eq 1 ]]
            [[ $output = *'does this host have GPUs'* ]]
        fi
    else
        # nvidia-container-cli not in $PATH
        run ch-fromhost -v --nvidia "$IMG"
        echo "$output"
        [[ $status -eq 1 ]]
        r="nvidia-container-cli: (command )?not found"
        [[ $output =~ $r ]]
        [[ $output =~ 'nvidia-container-cli failed' ]]
    fi
}

