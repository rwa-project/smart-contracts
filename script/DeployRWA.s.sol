// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";

// OZ Transparent Proxy
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// Your logic contract
import "../src/FractionalRWA.sol";

/**
 * @dev Foundry script to deploy:
 *      1) ProxyAdmin
 *      2) FractionalRWA (implementation logic)
 *      3) TransparentUpgradeableProxy
 */
contract DeployRWA is Script {
    function run() external {
        // 1. Start broadcast so that subsequent calls use the private key from foundry.toml or CLI
        vm.startBroadcast();

        //    Example addresses: put your own here or load from environment
        string memory baseURI = "ipfs://baseURI/";
        address adminAddress = msg.sender; // or a dedicated admin
        address minterAddress = msg.sender; // or a separate minter

        // 2. Deploy the ProxyAdmin
        ProxyAdmin proxyAdmin = new ProxyAdmin(adminAddress);

        // 3. Deploy the FractionalRWA Implementation (logic) contract
        FractionalRWA implV1 = new FractionalRWA();

        // 4. Encode the initializer call
        //    "initialize(string memory baseURI, address admin, address minter)"

        bytes memory initData =
            abi.encodeWithSelector(FractionalRWA.initialize.selector, baseURI, adminAddress, minterAddress);

        // 5. Deploy the TransparentUpgradeableProxy
        //    constructor args: (logic, proxyAdmin, initData)
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implV1), address(proxyAdmin), initData);

        // 6. Optionally, cast the proxy to the contract interface for convenience
        FractionalRWA rwaProxy = FractionalRWA(address(proxy));

        // 7. Stop the broadcast
        vm.stopBroadcast();

        // 8. You may log addresses
        console.log("ProxyAdmin deployed at:", address(proxyAdmin));
        console.log("Implementation V1 at: ", address(implV1));
        console.log("Proxy (RWA) at:       ", address(proxy));
        console.log("RWA Proxy (interface) at:", address(rwaProxy));
    }
}
