// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";

// OZ Transparent Proxy
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// Suppose you created a new version of the contract with additional logic
// import "../src/FractionalRWAV2.sol";

/**
 * @dev Foundry script to:
 *      1) Deploy FractionalRWAV2 (new implementation)
 *      2) Call ProxyAdmin.upgrade(...) to point the proxy to the new implementation
 */
contract UpgradeRWA is Script {
    function run() external {
        vm.startBroadcast();

        // 1. Retrieve existing addresses from environment or pass them in
        //    For example, from logs of DeployRWA
        // TODO: Replace with actual addresses
        address proxyAdminAddr = msg.sender;
        address proxyAddr = msg.sender;

        // 2. Deploy new implementation
        // FractionalRWAV2 implV2 = new FractionalRWAV2();

        // 3. Call upgrade on ProxyAdmin
        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddr);
        // proxyAdmin.upgradeAndCall(
        //     TransparentUpgradeableProxy(payable(proxyAddr)),
        //     address(implV2),
        //     ""
        // );

        vm.stopBroadcast();

        // console.log(
        //     "Upgraded Proxy at ",
        //     proxyAddr,
        //     " to new implementation:",
        //     address(implV2)
        // );
    }
}
