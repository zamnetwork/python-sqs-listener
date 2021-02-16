#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_NAME=${PWD##*/}

DO_CONDA=0
DO_VIRTUALENV_WRAPPER=0

VIRTUALENV_FILE="/usr/local/bin/virtualenvwrapper.sh"
REQUIREMENTS_FILE="$SCRIPT_DIR/requirements/dev.txt"
CONDA_ENV_FILE="$SCRIPT_DIR/conda.env.yml"

function _echo {
    ## if 2nd arg is 1, print in red
    ## else print in green
    ## reset colour at the end
    ECHO_PREFIX="[SETUP LOG]::"
    if [[ -z "$2" && $2 = 1 ]]
        then
        echo -e "\e[31m$ECHO_PREFIX$1 \e[0m"
    else
        echo -e "\e[32m$ECHO_PREFIX$1 \e[0m"
    fi
}

function _pipInstall {
    if [ -f "$REQUIREMENTS_FILE" ]
        then
        pip install -r $REQUIREMENTS_FILE
    else
        _echo "$REQUIREMENTS_FILE not found. Aborting!" 1
        exit 1
    fi
}

function _setupConda {
    _echo "Setting up conda environment"
    DO_PIP=0
    if [ -f "$CONDA_ENV_FILE" ]
        then
        conda env create -f $CONDA_ENV_FILE
        if [[ $? == 1 ]]; then
            _echo "Conda env already exists, trying to update instead"
            conda env update -f $CONDA_ENV_FILE --prune
        fi
    else
        _echo "$CONDA_ENV_FILE not found" 1
        conda create -y -n $PROJECT_NAME python=3.7
        DO_PIP=1
    fi
    ## initialize the new environment in the sub shell
    ## where this current bash script executes
    eval "$(conda shell.bash hook)"
    conda activate $1
    if [ $DO_PIP = 1 ]
        then
        _pipInstall
        _echo "Saving env to file $CONDA_ENV_FILE"
        ## exclude prefix key from conda yml as it points to local folder
        ## and is not required
        conda env export | grep -v "^prefix: " > $CONDA_ENV_FILE
    fi
}

function _setupVirtualEnv {
    _echo "Setting up virtualenv environment"
    source $VIRTUALENV_FILE
    mkvirtualenv $1
    _pipInstall
}

function _postSetup {
    _echo "Successfully setup dev env"
    if [ $2 = 1 ]
        then
        CMD="conda activate $1"
        DEACTIVATE="conda deactivate"
    else
        CMD="workon $1"
        DEACTIVATE="deactivate"
    fi
    _echo "To start developing in this env you'll have to first run:\n$CMD"
    _echo "To stop working in this env run:\n$DEACTIVATE"
    _echo "DONE"
}

function _setupCommitHooks {
    ## Run yarn install first as this will install husky
    ## husky sets up commit hooks for every git hook (can't specify individually)
    ## we only want to setup commitmsg to be handled by husky
    ## pre-commit & pre-push will be handled by pre-commit so
    ## install those after yarn.
    _echo "Running yarn install"
    yarn install
    _echo "Adding pre-commit hooks"
    pre-commit install -t pre-commit
    pre-commit install -t pre-push
}

## Check if conda executable exists
conda --version
if [ $? -eq 0 ]
    then
    _echo "conda installation found"
    DO_CONDA=1
else
    ## If conda not found, check if virtualenvwrapper is installed
    if [ -f "$VIRTUALENV_FILE" ]
        then
        _echo "virtualenvwrapper found"
        DO_VIRTUALENV_WRAPPER=1
    fi
fi

## Exit if neither conda or virtualenvwrapper exist
if [[ $DO_CONDA = 0 && $DO_VIRTUALENV_WRAPPER = 0 ]]
    then
    _echo "Either install Conda (https://docs.conda.io/projects/conda/en/latest/user-guide/install/index.html)\nor\
\ninstall virutalenvwrapper (https://virtualenvwrapper.readthedocs.io/en/latest/)\n" 1
    exit 1
fi

if [ $DO_CONDA = 1 ]
    then
    _setupConda $PROJECT_NAME
else
    _setupVirtualEnv $PROJECT_NAME
fi

## Setup commit hooks
_setupCommitHooks
## Echo commands on usage
_postSetup $PROJECT_NAME $DO_CONDA
