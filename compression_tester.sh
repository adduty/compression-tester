#!/usr/bin/env bash

# TODO(aduty): add spinner (to indicate activity)?
# TODO(aduty): deal with algs that support -0 compression level
# TODO(aduty): change status for compress alg since it doesn't have compression levels
# TODO(aduty): add checks to make sure version of things e.g. bash is new enough
# TODO(aduty): measure other stats with time command and add as CSV fields (or allow user to specify time format?)
# TODO(aduty): add option to turn on all algs except those specified- something like --reverse --zip to enable all but zip
# TODO(aduty): add support for testing range of numbers of threads

set -o errexit
set -o pipefail
set -o nounset

timer=$(which time)

usage() {
  echo "Usage: $0 [OPTION...] FILE..."
  echo 'Options:'
  echo '  -f,   --file=FILE     perform compression tests on FILE'
  echo '  -h,   --help          display usage info'
  echo '  -i,   --iterations=N  perform each test N times'
  echo '  -n,   --minimum=N     minimun compression level (1-9)'
  echo '  -o,   --output=FILE   output results to FILE (comp-test-DATE.csv if unspecified)'
  echo '  -x,   --maximum=N     maximum compression level (1-9)'
  echo '  -t,   --threads       number of threads to use for multi-threaded binaries (default 8)'
  echo
  echo 'Algorithms:'
  echo
  echo '  -a,   --all           enable all tests'
  echo '  -s,   --single        enable all single-threaded tests'
  echo '  -m,   --multi         enable all multi-threaded tests'
  echo '        --bzip2         enable bzip2 testing'
  echo '        --xz            enable xz testing'
  echo '        --gzip          enable gzip testing'
  echo '        --lzma          enable lzma testing'
  echo '        --lzip          enable lzip testing'
  echo '        --lzop          enable lzop testing'
  echo '        --compress      enable compress testing'
  echo '        --zip           enable zip testing'
  echo '        --lbzip2        enable lbzip2 (multi-threaded bzip2) support'
  echo '        --pbzip2        enable pbzip2 (parallel implementation of bzip2) support'
  echo '        --pigz          enable pigz (parallel implementation of gzip) support'
  echo '        --pxz           enable pxz (parallel LZMA compressor using XZ) support'

  echo 'By default, min=6 and max=6. You can change one or both.'
  exit 1
}

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
        which "${i}" &> /dev/null && rc=$? || rc=$?
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

# compression/decompression testing function 
# args: 1- compression bin, 2- other compression flags, 3- decompression bin, 4- decompression flags,
# 5- testfile, 6- compression level
# csv format: alg,comp_level,comp_time,comp_size,decomp_time,threads
test_routine() {
  printf '%s,%s,' "${1}" "${6/-/}" >> "${outfile}"
  # the function seems to pass empty quotes to compress when ${6} is empty and compress chokes
  if [[ "${1}" == 'compress' ]]; then
    t_1=$("${timer}" "${time_opts}" "${1}" "${2}" "${5}" 2>&1)
  else
    t_1=$("${timer}" "${time_opts}" "${1}" ${2} "${6}" "${5}" 2>&1)
  fi
  printf '%s,' "${t_1}" >> "${outfile}"
  stat --printf='%s,' "${5}.${exts[${1}]}" >> "${outfile}"
  t2=$("${timer}" "${time_opts}" "${3}" ${4} "${5}.${exts[${1}]}" 2>&1)
  printf '%s,' "${t2}" >> "${outfile}"
  if [[ "${1}" == 'lbzip2' ]] || [[ "${1}" == 'pbzip2' ]] || [[ "${1}" == 'pigz' ]] || [[ "${1}" == 'pxz' ]]; then
    printf '%s\r\n' "${threads}" >> "${outfile}"
  else
    printf '0\r\n' >> "${outfile}"
  fi
}

min='6'
max='6'
iterations='1'
file=''
date=$(date +%T-%d.%b.%Y)
outfile="comp-test-${date}.csv"
threads=''

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

st_algs=(
  'bzip2'
  'xz'
  'gzip'
  'lzma'
  'lzip'
  'lzop'
  'compress'
)

mt_algs=(
  'lbzip2'
  'pbzip2'
  'pigz'
  'pxz'
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
  ['zip']='zip'
)

zip='off'

OPTS=$(getopt --options asmn:x:f:o:hi:t: --long \
  minimum:,maximum:,file:,output:,help,iterations:,threads:,all,single,multi,bzip2,xz,gzip,lzma,lzip,lzop,compress,zip,lbzip2,pbzip2,pigz,pxz \
  --name 'compression_test.sh' -- "$@")
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
    -i|--iterations) iterations=${2}; shift 2 ;;
    -t|--threads) threads=${2}; shift 2 ;;
    -a|--all) for i in "${!algs[@]}"; do  algs[$i]='on'; done; zip='on'; shift ;;
    -s|--single) for i in "${st_algs[@]}"; do algs[${i}]='on'; done; zip='on'; shift ;;
    -m|--multi) for i in "${mt_algs[@]}"; do algs[${i}]='on'; done; shift ;;
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

# make sure threads specified if using any multi-threaded algs
for i in "${mt_algs[@]}"; do
  if [[ ${algs[$i]} == 'on' ]]; then
    if [[ -z ${threads} ]]; then
      echo "You must specify number of threads if usinig multi-threaded implementation (${i})."
      exit 1
    fi
    break
  fi
done


# make sure threads is positive integer
if [[ ! -z ${threads} ]]; then
  pat_threads="^[0-9]+$"
  if [[ ! ${threads// /} =~ ${pat_threads// /} ]] || [[ ${threads// /} == '0' ]]; then
    echo "Number of threads specified ('${threads}') is not a positive integer."
    exit 1
  fi
fi

# make sure iterations is positive integer
if [[ ! -z ${iterations} ]]; then
  pat_iterations="^[0-9]+$"
  if [[ ! ${iterations// /} =~ ${pat_iterations// /} ]] || [[ ${iterations// /} == '0' ]]; then
    echo "Number of iterations specified ('${iterations}') is not a positive integer."
    exit 1
  fi
fi

# check_int() {
#   if [[ ! -z ${1} ]]; then
#     pat_threads="^[0-9]+$"
#     if [[ ! ${1// /} =~ ${pat_threads// /} ]] || [[ ${1// /} == '0' ]]; then
#       echo "Number of ${2} specified ('${1}') is not a positive integer."
#       exit 1
#     fi
#   fi
# }

# make sure conditions are appropriate for testing
# echo 'TO GET VALID RESULTS, IT IS VERY IMPORTANT THAT YOU ARE NOT DOING ANYTHING ELSE CPU OR MEMORY INTENSIVE. Proceed (Y/N)?'
# read ans
# if [[ ! ${ans// /} =~ ${pat} ]]; then
#   exit 1
# fi

bin_check

tmp=$(mktemp --directory /tmp/comp_test_XXX)

cp --recursive "${file}" "${tmp}"

time_opts='--format=%e'

# initialize outfile with csv header
printf 'binary,compression_level,compression_time,compressed_size,decompression_time,threads\r\n' >> "${outfile}"

# record uncompressed file size
orig_size=$(du --bytes "${file}" | cut --fields 1)
printf '%s,,,,,\r\n' "${orig_size}" >> "${outfile}"

# do the tests
if [[ ${zip} == 'on' ]]; then
  for ((i=min;i<=max;i++)); do
    for ((iter='1';iter<=iterations;iter++)); do
      # unzipping into the existing directory causes unzip to hang
      test_routine zip "--recurse-paths --quiet ${tmp}/${file}" unzip "-qq -d ${tmp}/tmp_${i}" "${tmp}/${file}" "-${i}"
      # unzip has no option to delete the zip file
      rm "${tmp}/${file}.zip"
      rm --force --recursive "${tmp}/tmp_${i}"
    done
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
      for ((iter='1';iter<=iterations;iter++)); do
        test_routine compress "-f" uncompress "-f" "${tmp}/${file}.tar" ''
      done
    fi
    # for j in $(seq ${min} ${max}); do
    for ((j=min;j<=max;j++)); do
      for ((iter='1';iter<=iterations;iter++)); do
        case "${i}" in
          bzip2) test_routine bzip2 '--quiet' bzip2 '--decompress --quiet' "${tmp}/${file}.tar" "-${j}" ;;
          xz) test_routine xz '--compress --quiet' xz '--decompress --quiet' "${tmp}/${file}.tar" "-${j}" ;;
          gzip) test_routine gzip '--quiet' gzip '--decompress --quiet' "${tmp}/${file}.tar" "-${j}" ;;
          lzma) test_routine lzma '--compress --quiet' unlzma '--quiet' "${tmp}/${file}.tar" "-${j}" ;;
          lzip) test_routine lzip '--quiet' lzip '--decompress --quiet' "${tmp}/${file}.tar" "-${j}" ;;
          lzop) test_routine lzop '--delete --quiet' lzop '--decompress --delete --quiet' "${tmp}/${file}.tar" "-${j}" ;;
          lbzip2) test_routine lbzip2 "-n ${threads} --quiet" lbzip2 "-n ${threads} --decompress --quiet" "${tmp}/${file}.tar" "-${j}" ;;
          pbzip2) test_routine pbzip2 "-p${threads} --quiet" pbzip2 "-p${threads} --decompress --quiet" "${tmp}/${file}.tar" "-${j}" ;;
          pigz) test_routine pigz "--processes ${threads} --quiet" pigz "--processes ${threads} --decompress --quiet" "${tmp}/${file}.tar" "-${j}" ;;
          pxz) test_routine pxz "--threads ${threads} --quiet" pxz "--threads ${threads} --decompress --quiet" "${tmp}/${file}.tar" "-${j}" ;;
        esac
      done
    done
  fi
done

# clean up
rm --recursive --force "${tmp}"
