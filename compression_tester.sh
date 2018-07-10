#!/usr/bin/env bash

# TODO(aduty): check if binaries exist for algs that are turned on
# TODO(aduty): add tests to generate decompression data
# TODO(aduty): add ability to plot results?
# TODO(aduty): add spinner (to indicate activity)?
# TODO(aduty): check if outfile exists, ask to overwrite

set -o xtrace
set -o errexit
set -o pipefail
set -o nounset

t=$(which time)
alias time="${t}"

usage() {
  echo "Usage: $0 [OPTION...] FILE..."
  echo 'Options:'
  echo '  -f,  --file=FILE    perform compression tests on FILE'
  echo '  -h,  --help         display usage info'
  echo '  -n,  --minimum=N    minimun compression level (1-9)'
  echo '  -o, --output=FILE   output results to FILE instead of STDOUT'
  echo '  -x,  --maximum=N    maximum compression level (1-9)'
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

  echo 'By default, min=1 and max=9. You can change one or both.'
  exit 1
}

min='1'
max='9'
file=''
outfile=''

declare -A algs
algs=( ['bzip2']='off' ['xz']='off' ['gzip']='off' ['lzma']='off' ['lzip']='off' ['lzop']='off' ['compress']='off' )
zip='off'

OPTS=`getopt -o n:x:f:o:h --long minimum:,maximum:,file:,output:,help,all,bzip2,xz,gzip,lzma,lzip,lzop,compress -n 'compression_test.sh' -- "$@"`
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
    -f|--file) file=${2}; shift 2 ;;
    -o|--output) outfile=${2}; shift 2 ;;
    -h|--help) usage; shift ;;
    --all) for i in "${!algs[@]}"; do  algs[$i]='on'; echo ${algs[$i]}; done; zip='on'; shift ;;
    --bzip2) algs['bzip2']='on'; shift ;;
    --xz) algs['xz']='on'; shift ;;
    --gzip) algs['gzip']='on'; shift ;;
    --lzma) algs['lzma']='on'; shift ;;
    --lzip) algs['lzip']='on'; shift ;;
    --lzop) algs['lzop']='on'; shift ;;
    --compress) algs['compress']='on'; shift ;;
    --zip) zip='on'; shift ;;
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

# make sure conditions are appropriate for testing
echo 'TO GET VALID RESULTS, IT IS VERY IMPORTANT THAT YOU ARE NOT DOING ANYTHING ELSE CPU OR MEMORY INTENSIVE. Proceed (Y/N)?'
read ans
pat=" *[yY] *$"
if [[ ! ${ans} =~ ${pat} ]]; then
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

tmp=$(mktemp --directory /tmp/comp_testXXX)

cp --recursive ${file} ${tmp}

sha=$(sha256sum ${tmp}/${file})

if [[ -z "${outfile}" ]]; then
  time_opts='--format=%e'
else
  time_opts="--format=%e --output=${outfile} --append"
fi

# compression/decompression testing function 
# args: 1- compression bin, 2- compression level, 3- other compression flags, 4- decompression bin, 5- decompression flags,
# 6- testfile, 7- outfile
test_routine() {
  echo "Testing ${1} at compression level ${2}:" | tee ${7}
  time ${time_opts} ${1} ${3} -${2} ${6} | tee ${7}
  du ${6} | tee ${7}
  echo "Testing ${4} at compression level ${2}:" | tee ${7}
  time ${time_opts} ${4} ${5} ${6} | tee ${7}
}

# do the tests
if [[ ${zip} == 'on' ]]; then
  for ((i=${min};i<=${max};i++)); do
    test_routine zip ${i} '--recurse-paths --quiet' unzip '--quiet' "${tmp}/${file}" "${outfile}"
  done
fi

# create tarball if testing any other algorithms
for i in "${!algs[@]}"; do
  if [[ ${algs[$i]} == 'on' ]]; then
    tar --create --file=${tmp}/${file}.tar ${file}
    break
  fi
done

for i in "${!algs[@]}"; do
  if [[ ${algs[$i]} == 'on' ]]; then
    if [[ ${i} == 'compress' ]]; then
      time ${time_opts} compress --quiet ${tmp}/${file}.tar
    fi
    # for j in $(seq ${min} ${max}); do
    for ((j=${min};j<=${max};j++)); do
      case "${i}" in
        bzip2) test_routine bzip2 ${j} '--quiet' bzip2 '--decompress --quiet' "${tmp}/${file}.tar" "${outfile}" ;;
        xz) test_routine xz ${j} '--compress --quiet' xz '--decompress --quiet' "${tmp}/${file}.tar" "${outfile}" ;;
        gzip) test_routine gzip ${j} '--quiet' gzip '--decompress --quiet' "${tmp}/${file}.tar" "${outfile}" ;;
        lzma) test_routine xz ${j} '--compress --format=lzma --quiet' xz '--decompress --format=lzma --quiet' "${tmp}/${file}.tar" "${outfile}" ;;
        lzip) test_routine lzip ${j} '--quiet' lzip '--decompress --quiet' "${tmp}/${file}.tar" "${outfile}" ;;
        lzop) test_routine lzop ${j} '--quiet' lzop '--decompress --quiet' "${tmp}/${file}.tar" "${outfile}" ;;
      esac
    done
  fi
done

# clean up
rm -rf ${tmp}
