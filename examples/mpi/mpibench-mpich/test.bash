setup_specific () {
    prerequisites_ok mpibench-mpich
    IMG=$IMGDIR/mpibench-mpich
    crayify_mpi_maybe "$IMG"
}
