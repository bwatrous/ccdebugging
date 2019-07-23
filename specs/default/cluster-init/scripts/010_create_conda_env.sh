#!/bin/bash
#
# See: https://docs.dask.org/en/stable/install.html
#
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.
source /etc/profile.d/anaconda-env.sh

set -x
set -e

conda update -n base -c defaults conda


# Setup Channels
conda config --add channels idontexist
conda config --add channels conda-forge
conda config --add channels defaults

# Create the default environments
for PKG in dask dask-jobqueue bokeh; do
    conda install -y ${PKG}
done

conda create -n dask dask dask-jobqueue



