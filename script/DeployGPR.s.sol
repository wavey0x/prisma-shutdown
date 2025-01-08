// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import { GasPoolReimburser } from "src/GasPoolReimburser.sol";

contract DeployGPR is Script {
    address constant CORE = 0x5d17eA085F2FF5da3e6979D5d26F1dBaB664ccf8;
    address constant psm1 = 0x9d7634b2B99c2684611c0Ac3150bAF6AEEa4Ed77;
    address constant psm2 = 0xAe21Fe5B61998b143f721CE343aa650a6d5EadCe;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        GasPoolReimburser gpr1 = new GasPoolReimburser(
            CORE,
            psm1
        );

        GasPoolReimburser gpr2 = new GasPoolReimburser(
            CORE,
            psm2
        );

        vm.stopBroadcast();
    }
}

// forge script script/Deploy.s.sol:Deploy --rpc-url $MAINNET_URL --broadcast --verify -vvvv