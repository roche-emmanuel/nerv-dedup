bdir=$(dirname "$0")
#echo "bdir=${bdir}"

PREV_LD_PATH="${LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH="${bdir}/bin:${LD_LIBRARY_PATH}"
luajit ${bdir}/main.lua ${bdir}/ "$@"
export LD_LIBRARY_PATH="${PREV_LD_PATH}"
