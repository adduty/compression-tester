#!/usr/bin/env bash

# TODO(aduty): add ability to plot results?
# TODO(aduty): add spinner (to indicate activity)?
# TODO(aduty): deal with algs that support -0 compression level
# TODO(aduty): change status for compress alg since it doesn't have compression levels
# TODO(aduty): add option to allow for multiple iterations (for taking an average- outside of script)?
# TODO(aduty): add pigz, lbzip2, pbzip2, pxz support
# TODO(aduty): add checks to make sure version of things e.g. bash is new enough

set -o xtrace
set -o errexit
set -o pipefail
set -o nounset

timer=$(which time)

usage() {
  echo "Usage: $0 [OPTION...] FILE..."
  echo 'Options:'
  echo '  -f,   --file=FILE     perform compression tests on FILE'
  echo '  -h,   --help          display usage info'
  echo '  -n,   --minimum=N     minimun compression level (1-9)'
  echo '  -o,   --output=FILE   output results to FILE instead of STDOUT'
  echo '  -x,   --maximum=N     maximum compression level (1-9)'
  echo '  -t,   --threads       number of threads to use for multi-threaded binaries (default 8)'
  echo
  echo 'Algorithms:'
  echo
  echo '      --bzip2         enable bzip2 testing'
  echo '      --xz            enable xz testing'
  echo '      --gzip          enable gzip testing'
  echo '      --lzma          enable lzma testing'
  echo '      --lzip          enable lzip testing'
  echo '      --lzop          enable lzop testing'
  echo '      --compress      enable compress testing'
  echo '      --zip           enable zip testing'
  echo '      --lbzip2        enable lbzip2 (multi-threaded bzip2) support'
  echo '      --pbzip2        enable pbzip2 (parallel implementation of bzip2) support'
  echo '      --pigz          enable pigz (parallel implementation of gzip) support'
  echo '      --pxz           enable pxz (parallel LZMA compressor using XZ) support'

  echo 'By default, min=6 and max=6. You can change one or both.'
  exit 1
}

min='6'
max='6'
file=''
outfile=''
threads='8'

declare -A algs
declare -A exts
algs=(
  ['bzip2']='off'
  ['xz']='off'
  ['gzip']='off'
  ['lzma']='off'
  ['lzip']='off'
  ['lzop']='off'
  ['compress']='off'
  ['lbzip2']='off'
  ['pbzip2']='off'
  ['pigz']='off'
  ['pxz']='off'
)

exts=(
  ['bzip2']='bz2'
  ['xz']='xz'
  ['gzip']='gz'
  ['lzma']='lzma'
  ['lzip']='lz'
  ['lzop']='lzo'
  ['compress']='Z'
  ['lbzip2']='bz2'
  ['pbzip2']='bz2'
  ['pigz']='gz'
  ['pxz']='xz'
)
zip='off'

OPTS=$(getopt -o n:x:f:o:ht: --long \
  minimum:,maximum:,file:,output:,help,threads:,all,bzip2,xz,gzip,lzma,lzip,lzop,compress,zip,lbzip2,pbzip2,pigz,pxz \
  -n 'compression_test.sh' -- "$@")
eval set -- "${OPTS}"

while true; do
  case "${1}" in
    -n|--minimum)
      case "${2}" in
        "") min='1'; shift 2 ;;
        *) min=${2}; shift 2 ;;
      esac
      ;;
    -x|--maximum)
      case "${2}" in
        "") max='9'; shift 2 ;;
        *) max=${2}; shift 2 ;;
      esac
      ;;
    -f|--file) file=${2%/}; shift 2 ;;
    -o|--output) outfile=${2}; shift 2 ;;
    -h|--help) usage; shift ;;
    -t|--threads) threads=${2}; shift 2 ;;
    --all) for i in "${!algs[@]}"; do  algs[$i]='on'; echo ${algs[$i]}; done; zip='on'; shift ;;
    --bzip2) algs['bzip2']='on'; shift ;;
    --xz) algs['xz']='on'; shift ;;
    --gzip) algs['gzip']='on'; shift ;;
    --lzma) algs['lzma']='on'; shift ;;
    --lzip) algs['lzip']='on'; shift ;;
    --lzop) algs['lzop']='on'; shift ;;
    --compress) algs['compress']='on'; shift ;;
    --zip) zip='on'; shift ;;
    --lbzip2) algs['lbzip2']='on'; shift ;;
    --pbzip2) algs['pbzip2']='on'; shift ;;
    --pigz) algs['pigz']='on'; shift ;;
    --pxz) algs['pxz']='on'; shift ;;
    --) shift; break ;;
    *) usage; break ;;
  esac
done

# make sure a target file has been specified and that it exists
if [[ -z ${file} ]]; then
  echo 'You must set a target file using -f or --file.'
  exit 1
elif [[ ! -e ${file} ]]; then
  echo "Target file '${file}' does not exist."
  exit 1
fi

pat="^[yY]$"

# overwrite if outfile exists?
if [[ -e ${outfile} ]]; then
  echo "File named '${outfile}' already exists. Overwrite?"
  read over
  if [[ ! ${over// /} =~ ${pat} ]]; then
    exit 1
  fi
fi

# make sure threads is positive integer
if [[ ! -z ${threads} ]]; then
  pat_threads="^[0-9]+$"
  if [[ ! ${threads// /} =~ ${pat_threads// /} ]] || [[ ${threads// /} == '0' ]]; then
    echo "Number of threads specified ('${threads}') is not a positive integer."
    exit 1
  fi
fi

# make sure conditions are appropriate for testing
echo 'TO GET VALID RESULTS, IT IS VERY IMPORTANT THAT YOU ARE NOT DOING ANYTHING ELSE CPU OR MEMORY INTENSIVE. Proceed (Y/N)?'
read ans
if [[ ! ${ans// /} =~ ${pat} ]]; then
  exit 1
fi

rc_check() {
  if [[ ${rc} -ne 0 ]]; then
    echo "${i} test enabled but binary was not found."
    exit 1
  fi
}

# make sure binaries for enabled algorithms exist on system and are in path
# for now, assume decompression binaries installed if corresponding compression bins exist
bin_check() {
  for i in "${!algs[@]}"; do
    if [[ ${algs[$i]} == 'on' ]]; then
      if [[ ${i} != 'lzma' ]]; then
        which ${i} &> /dev/null && rc=$? || rc=$?
        rc_check
      elif [[ ${i} == 'lzma' ]]; then
        which xz &> /dev/null && rc=$? || rc=$?
        rc_check
      fi
    fi
  done
  if [[ ${zip} == 'on' ]]; then
    which zip &> /dev/null && rc=$? || rc=$?
    rc_check
  fi
}

bin_check

tmp=$(mktemp --directory /tmp/comp_test_XXX)

cp --recursive "${file}" "${tmp}"

# sha=$(sha256sum ${tmp}/${file})

time_opts='--format=%e'

# compression/decompression testing function 
# args: 1- compression bin, 2- compression level, 3- other compression flags, 4- decompression bin, 5- decompression flags,
# 6- testfile, 7- outfile
# csv format: alg,comp_level,comp_time,comp_size,decomp_time
test_routine() {
  printf '%s,%s,' "${1}" "${2/-/}" >> "${7}"
  t_1=$("${timer}" "${time_opts}" "${1}" "${3}" "${2}" "${6}" 2>&1)
  printf '%s,' "${t_1}" >> "${7}"
  stat --printf='%s,' "${6}.${exts[${1}]}" >> "${7}"
  t2=$("${timer}" "${time_opts}" "${4}" ${5} "${6}.${exts[${1}]}" 2>&1)
  printf '%s\n' "${t2}" >> "${7}"
}

# do the tests
if [[ ${zip} == 'on' ]]; then
  for ((i=min;i<=max;i++)); do
    test_routine zip "-${i}" '--recurse-paths --quiet' unzip '--quiet' "${tmp}/${file}" "${outfile}"
  done
fi

# create tarball if testing any other algorithms
for i in "${!algs[@]}"; do
  if [[ ${algs[$i]} == 'on' ]]; then
    tar --create --file="${tmp}/${file}.tar" "${file}"
    break
  fi
done

for i in "${!algs[@]}"; do
  if [[ ${algs[$i]} == 'on' ]]; then
    if [[ ${i} == 'compress' ]]; then
      test_routine compress '' '-f' uncompress '-f' "${tmp}/${file}.tar" "${outfile}"
    fi
    # for j in $(seq ${min} ${max}); do
    for ((j=min;j<=max;j++)); do
      case "${i}" in
        bzip2) test_routine bzip2 "-${j}" '--quiet' bzip2 '--decompress --quiet' "${tmp}/${file}.tar" "${outfile}" ;;
        xz) test_routine xz "-${j}" '--compress --quiet' xz '--decompress --quiet' "${tmp}/${file}.tar" "${outfile}" ;;
        gzip) test_routine gzip "-${j}" '--quiet' gzip '--decompress --quiet' "${tmp}/${file}.tar" "${outfile}" ;;
        lzma) test_routine xz "-${j}" '--compress --format=lzma --quiet' xz '--decompress --format=lzma --quiet' "${tmp}/${file}.tar" "${outfile}" ;;
        lzip) test_routine lzip "-${j}" '--quiet' lzip '--decompress --quiet' "${tmp}/${file}.tar" "${outfile}" ;;
        lzop) test_routine lzop "-${j}" '--delete --quiet' lzop '--decompress --delete --quiet' "${tmp}/${file}.tar" "${outfile}" ;;
        lbzip2) test_routine lbzip2 "-${j}" "-n ${threads} --quiet" lbzip2 "-n ${threads} --decompress --quiet" "${tmp}/${file}.tar" "${outfile}" ;;
        pbzip2) test_routine pbzip2 "-${j}" "-p${threads} --quiet" pbzip2 "-p${threads} --decompress --quiet" "${tmp}/${file}.tar" "${outfile}" ;;
        pigz) test_routine pigz "-${j}" "--processes ${threads} --quiet" pigz "--processes ${threads} --decompress --quiet" "${tmp}/${file}.tar" "${outfile}" ;;
        pxz) test_routine pxz "-${j}" "--threads ${threads} --quiet" pxz "--threads ${threads} --decompress --quiet" "${tmp}/${file}.tar" "${outfile}" ;;
      esac
    done
  fi
done

# clean up
rm --recursive --force "${tmp}"
