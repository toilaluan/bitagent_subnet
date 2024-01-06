#!/bin/bash
# The MIT License (MIT)
# Copyright © 2023 RogueTensor

# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
# documentation files (the “Software”), to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software,
# and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all copies or substantial portions of
# the Software.

# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
# THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.

# TODO for user - load subtensor to launch your local subnet
# following this tutorial: https://github.com/opentensor/bittensor-subnet-template/blob/main/docs/running_on_staging.md
# start it (from under the subtensor directory): BUILD_BINARY=0 ./scripts/localnet.sh

############ GET THE ARGS ############
programname=$0
function usage {
    echo ""
    echo "Creates wallets for the subnet (owner, validators, miners), funds them, registers them, then starts them."
    echo ""
    echo "usage: $programname --num_validators num --num_miners num --subnet_prefix string"
    echo ""
    echo "  --num_validators num     number of validators to launch"
    echo "                           (default: 1)"
    echo "  --num_miners     num     number of miners to launch"
    echo "                           (default: 2)"
    echo "  --subnet_prefix  string  the prefix of the subnet wallets"
    echo "                           (default: local_subnet_testing_bitqna)"
    echo "  --skip-wallet    num     pass in 0 to skip wallet creation"
    echo "                           (default: 1)"
    echo "  --skip-faucet    num     pass in 0 to skip wallet funding"
    echo "                           (default: 1)"
    echo "  --skip-subnet    num     pass in 0 to skip subnet creation"
    echo "                           (default: 1)"
    echo "  --skip-reg       num     pass in 0 to skip all registration to the subnet"
    echo "                           (default: 1)"
    echo "  --skip-val-reg   num     pass in 0 to skip validator registration to the subnet"
    echo "                           (default: 1)"
    echo "  --skip-miner-reg num     pass in 0 to skip miner registration to the subnet"
    echo "                           (default: 1)"
    echo "  --skip-launch    num     pass in 0 to skip validator and miner launching on the subnet"
    echo "                           (default: 1)"
    echo "  --only-launch    num     pass in 0 to skip everything but launching"
    echo "                           (default: 1)"
    echo ""
    echo "Example: ./scripts/setup_and_run.sh --skip-wallet 0 --skip-subnet 0 --skip-faucet 0 --skip-reg 0"
    echo "This will skip everything and just launch the already registered and funded validators and miners"
    echo ""
}

while [ $# -gt 0 ]; do
    if [[ $1 == "--help" ]]; then
        usage
        exit 0
    elif [[ $1 == "-h" ]]; then
        usage
        exit 0
    elif [[ $1 == "--"* ]]; then
        v="${1/--/}"
        v="${v//-/_}"  # Replace hyphens with underscores

        # Check if the next argument is a value or another option
        if [[ $2 && ${2:0:2} != "--" ]]; then
            declare "$v"="$2"
            shift  # Shift past the value
        else
            declare "$v"=0  # Set a default value (true) for flags without a specific value
        fi
    fi
    shift
done

### SET DEFAULTS
num_validators=${num_validators:-1}
num_miners=${num_miners:-2}
subnet_prefix=${subnet_prefix:-local_subnet_testing_bitqna}
skip_wallet=${skip_wallet:-1}
skip_faucet=${skip_faucet:-1}
skip_subnet=${skip_subnet:-1}
skip_reg=${skip_reg:-1}
skip_val_reg=${skip_val_reg:-1}
skip_miner_reg=${skip_miner_reg:-1}
skip_launch=${skip_launch:-1}
only_launch=${only_launch:-1}

if [ $only_launch -eq 0 ]; then
    echo "Skipping everything but launching validators and miners"
    skip_wallet=0
    skip_faucet=0
    skip_subnet=0
    skip_reg=0
    skip_val_reg=0
    skip_miner_reg=0
fi

owner_coldkey="${subnet_prefix}_coldkey_owner"
validator_coldkey_prefix="${subnet_prefix}_coldkey_validator"
validator_hotkey_prefix="${subnet_prefix}_hotkey_validator"
miner_coldkey_prefix="${subnet_prefix}_coldkey_miner"
miner_hotkey_prefix="${subnet_prefix}_hotkey_miner"
############ CREATE THE WALLETS ############
if [ $skip_wallet -eq 1 ]; then
    prefix=$(dirname "$0")

    ### CREATE OWNER
    python3 ${prefix}/create_wallet.py --coldkey_name ${owner_coldkey} --hotkey_name ${subnet_prefix}_hotkey_owner --local True

    ### CREATE num_validators validators
    # this will return an index at the end like _0 for the first and _1 for the second and so on after the passed in key name
    python3 ${prefix}/create_wallet.py --coldkey_name ${validator_coldkey_prefix} --hotkey_name ${validator_hotkey_prefix} --num $num_validators --local True

    ### CREATE num_miners miners
    # this will return an index at the end like _0 for the first and _1 for the second and so on after the passed in key name
    python3 ${prefix}/create_wallet.py --coldkey_name ${miner_coldkey_prefix} --hotkey_name ${miner_hotkey_prefix} --num $num_miners --local True
fi

############ FUND THE WALLETS ############
if [ $skip_faucet -eq 1 ]; then
    ### FUND OWNER
    # needs to run 4 times to get 1200 tao
    for i in {1..4}
    do
        expect -c "
          spawn btcli wallet faucet --wallet.name ${owner_coldkey}_0 --subtensor.chain_endpoint ws://127.0.0.1:9946 --faucet.num_processes 8
          expect -re \"network:\" {send \"y\r\"; interact}
        "
    done

    ### FUND VALIDATORS
    for i in $(seq $num_validators)
    do
        expect -c "
          spawn btcli wallet faucet --wallet.name ${validator_coldkey_prefix}_$((i-1)) --subtensor.chain_endpoint ws://127.0.0.1:9946 --faucet.num_processes 8
          expect -re \"network:\" {send \"y\r\"; interact}
        "
    done

    ### FUND MINERS
    for i in $(seq $num_miners)
    do
        expect -c "
          spawn btcli wallet faucet --wallet.name ${miner_coldkey_prefix}_$((i-1)) --subtensor.chain_endpoint ws://127.0.0.1:9946 --faucet.num_processes 8
          expect -re \"network:\" {send \"y\r\"; interact}
        "
    done
fi

############ CREATE THE SUBNET ############
if [ $skip_subnet -eq 1 ]; then
    # create the subnet with the owner wallet
    expect -c "
        spawn btcli subnet create --wallet.name ${owner_coldkey}_0 --subtensor.chain_endpoint ws://127.0.0.1:9946
        expect -re \"register a subnet for\" {send \"y\r\"; interact}
    "
fi

############ REGISTER THE VALIDATORS TO THE SUBNET ############
if [ $skip_reg -eq 1 ]; then
    if [ $skip_val_reg -eq 1 ]; then
        for i in $(seq $num_validators)
        do
            expect -c "
                spawn btcli subnet register --wallet.name ${validator_coldkey_prefix}_$((i-1)) --wallet.hotkey ${validator_hotkey_prefix}_$((i-1)) --subtensor.chain_endpoint ws://127.0.0.1:9946
                expect -re \"Enter netuid\" {send \"1\r\";}
                expect -re \"want to continue?\" {send \"y\r\";}
                expect -re \"register on subnet:1\" {send \"y\r\"; interact} 
            "
        done
    fi

    ############ REGISTER THE MINERS TO THE SUBNET ############
    if [ $skip_miner_reg -eq 1 ]; then
        for i in $(seq $num_miners)
        do
            expect -c "
                spawn btcli subnet register --wallet.name ${miner_coldkey_prefix}_$((i-1)) --wallet.hotkey ${miner_hotkey_prefix}_$((i-1)) --subtensor.chain_endpoint ws://127.0.0.1:9946
                expect -re \"Enter netuid\" {send \"1\r\";}
                expect -re \"want to continue?\" {send \"y\r\";}
                expect -re \"register on subnet:1\" {send \"y\r\"; interact} 
            "
        done
    fi
fi

if [ $skip_launch -eq 1 ]; then
############ START THE MINERS ############
    echo "####################################################################################"
    echo "This is going to spawn a lot of jobs that you will lose terminal access to kill/stop"
    echo "IF this is the only python-related code running, you can use: killall -9 python3"
    echo "ELSE you can use: ps aux, and find the jobs to kill by pid with: kill -9 <pid>"
    echo "####################################################################################"
    for i in $(seq $num_miners)
    do
        python3 neurons/miner.py --netuid 1 --subtensor.chain_endpoint ws://127.0.0.1:9946 --wallet.name ${miner_coldkey_prefix}_$((i-1)) --wallet.hotkey ${miner_hotkey_prefix}_$((i-1)) --logging.debug --axon.port $((8090+i)) &
    done
    
############ START THE VALIDATORS ############
    sleep 2 # brief pause to let the miners fully launch

    for i in $(seq $num_validators)
    do
        python3 neurons/validator.py --netuid 1 --subtensor.chain_endpoint ws://127.0.0.1:9946 --wallet.name ${validator_coldkey_prefix}_$((i-1)) --wallet.hotkey ${validator_hotkey_prefix}_$((i-1)) --logging.debug --axon.port $((8090+i+num_miners)) &
    done
fi
