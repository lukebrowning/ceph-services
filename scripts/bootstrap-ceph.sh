#!/usr/bin/env bash
#
# Copyright 2016 IBM Corp.
#
# All Rights Reserved.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

# This parameter controls the version of ceph-ansible that is installed
CEPH_ANSIBLE_TAG=${CEPH_ANSIBLE_TAG:-"84dad9a77545eca9295a75f7cf1ae2c564f898ae"}

# This parameter controls which ceph inventory (group_vars) to be used for testing
# purposes.  Presently, there is only one inventory supported.  aio_config_1 is an
# all in one configuration that does not require any dedicated disks.  Another
# variant say aio_config_2 might include 3 dedicated disks.  There are configuration
# requirements associated with each configuration that have to be satisfied by CICD
# in conjunction with the execution of each set of ceph inventory data as externally
# controlled by this variable
TEST_CONFIG=${CICD_INVENTORY:-"etc/test_config/aio_openstack_with_ceph"}

if [ "$1" == "--help" ]; then
    echo "Usage: bootstrap-ceph.sh"
    exit 1
fi

if [ ! -e scripts/bootstrap-ceph.sh ]; then
    echo "This script must be run in the root directory of the project.  ie. /root/os-services/ceph or /root/ceph"
    exit 1
fi
PCLD_DIR=`pwd`

SCRIPTS_DIR=$(dirname $0)
source $SCRIPTS_DIR/process-args.sh

echo "DEPLOY_AIO=$DEPLOY_AIO"
echo "infraNodes=$infraNodes"
echo "storageNodes=$storageNodes"
echo "allNodes=$allNodes"

INSTALL=False
if [ ! -d $CEPH_DIR ]; then
    echo "Installing ceph-ansible..."
    git-clone git://github.com/ceph/ceph-ansible $CEPH_ANSIBLE_TAG $CEPH_DIR
    INSTALL=True
fi

# If ceph is invoked as a standalone project, install ansible
type ansible >/dev/null 2>&1
if [ $? != 0 ]; then
    echo "Installing ansible..."
    $CEPH_DIR/install-ansible.sh
fi

# Apply patches iff ceph-ansible is installed above.  Code is designed to be reentrant
if [ "$INSTALL" == "True" ] && [ -d $PCLD_DIR/diffs ]; then
    echo "Applying patches"
    pushd / >/dev/null 2>&1
    for f in $PCLD_DIR/diffs/*.patch; do
        patch -N -p1 < $f
        rc=$?
        if [ $rc != 0 ]; then
            echo "scripts/bootstrap-ceph failed, rc=$rc"
            echo "Patch $f could not be applied"
            echo "Manual retry procedure:"
            echo "1) fix patch $f"
            echo "2) rm -rf /etc/ansible; rm -rf $CEPH_DIR"
            echo "3) re-run command"
            exit 1
        fi
    done
    popd >/dev/null 2>&1
fi

# Setup site.yml playbook for use
cp ${CEPH_DIR}/site.yml.sample ${CEPH_DIR}/site.yml
rc=$?
if [ $rc != 0 ]; then
    echo "scripts/bootstrap-ceph failed, rc=$rc"
    echo "Check whether ceph-ansible is properly installed at $CEPH_DIR"
    echo "Manual retry procedure:"
    echo "1) rm -rf $CEPH_DIR"
    echo "2) re-run command"
    exit 1
fi

# This is the normalized genesis style input source of inventory covering all configurations
if [ -r "$GENESIS_INVENTORY" ]; then
    echo "Using genesis inventory"
    ${PCLD_DIR}/scripts/ulysses_ceph/generate_ceph_ansible_input.py \
        --inventory $GENESIS_INVENTORY --output_directory $CEPH_DIR
    if [ $? != 0 ]; then
        echo "Error generating ceph inventory"
        exit 2
    fi
else
    echo "Generating ceph inventory from test configuration directory $TEST_CONFIG"
    if [ -r $TEST_CONFIG/playbooks/setup.yml ]; then
        pushd $TEST_CONFIG/playbooks >/dev/null 2>&1
            echo "Running playbook to setup test configuration"
            run_ansible setup.yml
            if [ $? != 0 ]; then
                echo "Error preparing test configuration"
                exit 3
            fi
        popd >/dev/null 2>&1
    fi
    cp $TEST_CONFIG/all $CEPH_DIR/group_vars
    cp $TEST_CONFIG/osds $CEPH_DIR/group_vars
    cp $TEST_CONFIG/hosts $CEPH_DIR/ceph-hosts
fi

echo "The ceph ansible control files are located at $CEPH_DIR/group_vars"
echo ""
echo "Settings may be customized if desired before they are activated by create cluster"
echo ""
echo "vi $CEPH_DIR/group_vars/all"
echo "vi $CEPH_DIR/group_vars/osds"
echo ""
echo "Note there is no requirement to modify any parameter"
