// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import { PrismaPSM } from "src/PrismaPSM.sol";

// Deploy a contract to a deterministic address with create2 factory.
contract DeployPSM is Script {
    address constant CORE = 0x5d17eA085F2FF5da3e6979D5d26F1dBaB664ccf8;
    address constant mkUSD = 0x4591DBfF62656E7859Afe5e45f6f47D3669fBB28;
    address constant crvUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address constant ultra = 0x35282d87011f87508D457F08252Bc5bFa52E10A0;
    address constant borrowerOps = 0x72c590349535AD52e6953744cb2A36B409542719;
    address constant borrowerOps2 = 0xeCabcF7d41Ca644f87B25704cF77E3011D9a70a1;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        PrismaPSM psm1 = new PrismaPSM(
            CORE,
            mkUSD,      // debtToken
            crvUSD,     // buyToken
            borrowerOps // borrowerOps
        );

        PrismaPSM psm2 = new PrismaPSM(
            CORE,
            ultra,       // debtToken
            crvUSD,      // buyToken
            borrowerOps2 // borrowerOps
        );

        vm.stopBroadcast();
    }
}

// forge script script/Deploy.s.sol:Deploy --rpc-url $MAINNET_URL --broadcast --verify -vvvv