pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";

import {MerkleERC721} from "../src/MerkleERC721.sol";
import {UpgradeableProxy} from "../src/UpgradeableProxy.sol";

contract TaskTest is Script {
    address public deployer;
    address public admin;

    function run() public {
        admin = vm.envAddress("ADMIN_ADDR");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.createWallet(deployerPrivateKey).addr;
        vm.startBroadcast(deployerPrivateKey);

        deploy();

        vm.stopBroadcast();
    }

    function deploy() public {
        // deploy contracts
        MerkleERC721 nftContract = new MerkleERC721(
            1747288800,
            1747375200,
            10 ** 12
        );
        UpgradeableProxy proxy = new UpgradeableProxy(
            address(nftContract),
            deployer,
            ""
        );
        nftContract = MerkleERC721(payable(proxy));
        nftContract.initialize(admin, "TEST NFT", "TEST");
        console.log("nftContract contract address: ", address(nftContract));
    }
}
