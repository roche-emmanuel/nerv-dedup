bdir=$(dirname "$0")

#echo "bdir=${bdir}"
luajit ${bdir}/main.lua ${bdir}/ "$@"
 
