#!/bin/bash

# build steps.
# Edit setup.py to use -flto, and -fuse-ld arguments, then
# rm -rf build
# python setup.py build
# ./inject.sh
# python setup.py install

PWD=/DATA/SDH/jgwohlbier/DSSoC/DASH/pytorch_build/pytorch_sparse
P=./build/lib.linux-x86_64-3.7/torch_sparse
FILES="_convert.so
       _diag.so
       _metis.so
       _relabel.so
       _rw.so
       _saint.so
       _sample.so
       _spmm.so
       _spspmm.so
       _version.so"

OPT="/DATA/SDH/packages/spack/opt/spack/linux-ubuntu18.04-broadwell/clang-9.0.1/llvm-9.0.1-mupwetisd3upwdfojfn6ztdmxmgfy3kz/bin/opt -load /DATA/SDH/jgwohlbier/DSSoC/DASH/TraceAtlas/build/lib/AtlasPasses.so"
COMP="/DATA/SDH/packages/spack/opt/spack/linux-ubuntu18.04-broadwell/clang-9.0.1/llvm-9.0.1-mupwetisd3upwdfojfn6ztdmxmgfy3kz/bin/clang++ -O2 -g -DNDEBUG -pthread -shared -B /DATA/SDH/packages/anaconda3/envs/dash_gs_env/compiler_compat -fuse-ld=lld -fPIC"
LINK="-L/DATA/SDH/packages/anaconda3/envs/dash_gs_env/lib -Wl,-rpath=/DATA/SDH/packages/anaconda3/envs/dash_gs_env/lib -Wl,--no-as-needed -Wl,--sysroot=/ -L/DATA/SDH/packages/anaconda3/envs/dash_gs_env/lib/python3.7/site-packages/torch/lib -lc10 -ltorch -ltorch_cpu -ltorch_python"
LINK="${LINK} -L/DATA/SDH/jgwohlbier/DSSoC/DASH/TraceAtlas/build/lib -Wl,-rpath,/DATA/SDH/jgwohlbier/DSSoC/DASH/TraceAtlas/build/lib -lAtlasBackend -lz"

TAI=0
TAVI=0
for f in ${FILES}; do
    echo ""
    echo "Injecting: ${f}"
    echo "opt pass 1:"
    # use '.ea.bc' for EncodedAnnotate
    cmd="${OPT} -EncodedAnnotate ${P}/${f} -o ${P}/${f}.ea.bc -tai ${TAI} -tavi ${TAVI}"
    echo "${cmd}"
    output=$(eval ${cmd})
    while read -r line; do
        echo "$line"
    done <<< "$output"
    numbers=$(echo "$output" | sed -e 's/[^0-9 ]//g')
    TAI=$(echo $numbers | cut -d " " -f 1)
    TAVI=$(echo $numbers | cut -d " " -f 2)

    echo ""
    echo "opt pass 2:"
    # use '.et.bc' for EncodedTrace
    cmd="${OPT} -EncodedTrace -sa ${P}/${f}.ea.bc -o ${P}/${f}.et.bc"
    echo "${cmd}"
    eval ${cmd}

    echo ""
    echo "link:"
    cmd="${COMP} ${P}/${f}.et.bc -o ${P}/${f} ${LINK}" # overwrites orig .so
    #cmd="${COMP} ${P}/${f}.et.bc -o ${P}/${f}.et.bc.so ${LINK}" # no overwrite
    echo "${cmd}"
    eval ${cmd}
done

# link bitcode from first pass to give to cartographer
linkfiles=""
for f in ${FILES}; do
    linkfiles="$linkfiles ${P}/${f}.ea.bc"
done
echo ""
echo "Link the bitcode for cartographer"
cmd="llvm-link ${linkfiles} -o ${P}/pts.bc"
echo "${cmd}"
eval ${cmd}

# add _sample.so.ea.bc since the block ID's were getting dropped.
echo ""
echo "Run test:"
echo "python setup.py test --addopts test/test_spspmm.py"
echo "Cartographer command:"
echo "/DATA/SDH/jgwohlbier/DSSoC/DASH/TraceAtlas/build/bin/cartographer -b ${PWD}/${P}/pts.bc -b ${PWD}/${P}/_sample.so.ea.bc -i raw.trc -k kernel.json --nb --pf -v  6"
echo "dagExtractor command:"
echo "/DATA/SDH/jgwohlbier/DSSoC/DASH/TraceAtlas/build/bin/dagExtractor -k kernel.json --nb -o dag.json -t raw.trace -v 6"
