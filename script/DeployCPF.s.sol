// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import { CustomPriceFeed } from "src/CustomPriceFeed.sol";

contract DeployCPF is Script {
    address constant CORE = 0x5d17eA085F2FF5da3e6979D5d26F1dBaB664ccf8;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        CustomPriceFeed cpf = new CustomPriceFeed(CORE);

        vm.stopBroadcast();
    }
}

// forge script script/DeployCPF.s.sol:DeployCPF --rpc-url $MAINNET_URL --broadcast --verify -vvvv