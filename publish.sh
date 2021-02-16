#!/bin/bash

## some functions are from https://github.com/whereisaaron/get-aws-profile-bash/blob/master/get-aws-profile.sh

function _cfg_parser () {
  IFS=$'\n' && ini=( $(<$1) ) # convert to line-array
  ini=( ${ini[*]//;*/} )      # remove comments ;
  ini=( ${ini[*]//\#*/} )     # remove comments #
  ini=( ${ini[*]/\	=/=} )  # remove tabs before =
  ini=( ${ini[*]/=\	/=} )   # remove tabs be =
  ini=( ${ini[*]/\ *=\ /=} )   # remove anything with a space around  =
  ini=( ${ini[*]/#[/\}$'\n'cfg.section.} ) # set section prefix
  ini=( ${ini[*]/%]/ \(} )    # convert text2function (1)
  ini=( ${ini[*]/=/=\( } )    # convert item to array
  ini=( ${ini[*]/%/ \)} )     # close array parenthesis
  ini=( ${ini[*]/%\\ \)/ \\} ) # the multiline trick
  ini=( ${ini[*]/%\( \)/\(\) \{} ) # convert text2function (2)
  ini=( ${ini[*]/%\} \)/\}} ) # remove extra parenthesis
  ini[0]="" # remove first element
  ini[${#ini[*]} + 1]='}'    # add the last brace
  eval "$(echo "${ini[*]}")" # eval the result
}

function _echo {
    ## if 2nd arg is 1, print in red
    ## else print in green
    ## reset colour at the end
    ECHO_PREFIX="[PUBLISH LOG]::"
    if [[ -z "$2" && $2 = 1 ]]
        then
        echo -e "\e[31m$ECHO_PREFIX$1 \e[0m"
    else
        echo -e "\e[32m$ECHO_PREFIX$1 \e[0m"
    fi
}

VERSION=''
function _get_version () {
    filename=$1
    IFS=$'\n'
    for next in `cat $filename`; do
        IFS='"'
        read -ra SPLITZ <<< "$next";
        VERSION="${SPLITZ[1]}"
    done
}


SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
VERSION_FILE="$SCRIPT_DIR/_version.py"


_echo "Fetching version info"
_get_version "${VERSION_FILE}"

_echo "Cleaning old builds"
rm -rf "$SCRIPT_DIR/dist"
rm -rf "$SCRIPT_DIR/build"

_echo "Building package"
python setup.py sdist bdist_wheel

_echo "Trying to fetch AWS credentials"
AWS_DIR="$HOME/.aws"
CREDENTIALS_FILE="$AWS_DIR/credentials"

if [ -f "$CREDENTIALS_FILE" ]
    then
    _cfg_parser "${CREDENTIALS_FILE}"
    if [[ $? -ne 0 ]]
        then
        _echo "Parsing credentials file '${CREDENTIALS_FILE}' failed" 1
        exit 1
    fi
    cfg.section.default
    _echo "Setting env vars"
    export PP_S3_ACCESS_KEY=${aws_access_key_id}
    export PP_S3_SECRET_KEY=${aws_secret_access_key}
    export PP_S3_SESSION_TOKEN=${aws_session_token}

    _echo "Publishing to pypi repo"
    pypi-private -v -c ./pypi-private.cfg publish zamvault $VERSION
elif [[ -v AWS_ACCESS_KEY_ID && -v AWS_SECRET_ACCESS_KEY ]]
    then
    _echo "$CREDENTIALS_FILE not found. But found aws env vars"
    _echo "Setting env vars"
    export PP_S3_ACCESS_KEY=${AWS_ACCESS_KEY_ID}
    export PP_S3_SECRET_KEY=${AWS_SECRET_ACCESS_KEY}
    _echo "Publishing to pypi repo"
    pypi-private -v -c ./pypi-private.cfg publish pySqsListener $VERSION
else
    _echo "$CREDENTIALS_FILE not found. Aborting!" 1
    exit 1
fi
