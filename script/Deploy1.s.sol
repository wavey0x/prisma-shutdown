// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import { EmissionSchedule } from "src/EmissionSchedule.sol";
import { BoostCalculator } from "src/BoostCalculator.sol";

// Deploy a contract to a deterministic address with create2 factory.
contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        EmissionSchedule emissionSchedule = new EmissionSchedule();
        // BoostCalculator boostCalculator = new BoostCalculator();

        vm.stopBroadcast();
    }
}

// forge script script/Deploy.s.sol:Deploy --rpc-url $MAINNET_URL --broadcast --verify -vvvv