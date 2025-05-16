pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {MerkleERC721} from "../src/MerkleERC721.sol";
import {UpgradeableProxy} from "../src/UpgradeableProxy.sol";

contract MerkleERC721Test is Test {
    string public constant TOKEN_URI = "TOKEN_URI";

    MerkleERC721 public nftContract;

    address public msgSender = address(1);
    address public admin = address(2);
    address public proxyAdmin = address(3);
    uint256 public startTime;

    function setUp() public virtual {
        // deploy mock OFT
        uint256 startTime = block.timestamp + 10 minutes;
        uint256 endTime = startTime + 20 minutes;
        nftContract = new MerkleERC721(startTime, endTime, 1 ether);
        UpgradeableProxy proxy = new UpgradeableProxy(
            address(nftContract),
            proxyAdmin,
            ""
        );
        nftContract = MerkleERC721(payable(proxy));
        nftContract.initialize(admin, "TEST NFT", "TEST");

        assertEq(nftContract.presaleStartTime(), startTime);
        assertEq(nftContract.presaleEndTime(), endTime);
        assertEq(nftContract.mintFee(), 1 ether);

        vm.deal(msgSender, 100 ether);
    }

    function test_MintProcess() public {
        vm.startPrank(msgSender);
        uint256 initialTokenId = nftContract.getNextTokenId();

        assertEq(nftContract.balanceOf(msgSender), 0);
        assertEq(nftContract.hasMinted(msgSender), false);

        vm.expectRevert("Time not reached");
        nftContract.mint();

        skip(30 minutes); // skip to public mint time

        vm.expectRevert("Invalid funds");
        nftContract.mint{value: 2 ether}();

        vm.expectEmit();
        emit MerkleERC721.Mint(msgSender, initialTokenId);
        nftContract.mint{value: 1 ether}();
        assertEq(nftContract.balanceOf(msgSender), 1);
        assertEq(nftContract.hasMinted(msgSender), true);

        vm.expectRevert("Already minted");
        nftContract.mint{value: 1 ether}();
        vm.stopPrank();
    }

    function test_WhitelistMintProcess() public {
        // setup merkle root
        vm.startPrank(admin);
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address[] memory whitelistAddresses = new address[](3);
        whitelistAddresses[0] = msgSender;
        whitelistAddresses[1] = user1;
        whitelistAddresses[2] = user2;

        bytes32 merkleRoot = nftContract.generateWhitelistMerkleRoot(
            whitelistAddresses
        );
        bytes32[] memory proof = nftContract.generateProof(
            whitelistAddresses,
            msgSender
        );
        assertEq(nftContract.verifyAddress(proof, merkleRoot, msgSender), true);
        nftContract.setWhitelist(merkleRoot, 1 ether);
        vm.stopPrank();

        vm.startPrank(msgSender);
        uint256 initialTokenId = nftContract.getNextTokenId();

        assertEq(nftContract.balanceOf(msgSender), 0);
        assertEq(nftContract.hasMinted(msgSender), false);

        vm.expectRevert("Presale not started");
        nftContract.whitelistMint{value: 1 ether}(merkleRoot, proof);

        skip(10 minutes); // skip to presale time

        vm.expectRevert("Invalid funds");
        nftContract.whitelistMint{value: 2 ether}(merkleRoot, proof);

        vm.expectEmit();
        emit MerkleERC721.Mint(msgSender, initialTokenId);
        nftContract.whitelistMint{value: 1 ether}(merkleRoot, proof);
        assertEq(nftContract.balanceOf(msgSender), 1);
        assertEq(nftContract.hasMinted(msgSender), true);

        vm.expectRevert("Already minted");
        nftContract.whitelistMint{value: 1 ether}(merkleRoot, proof);

        proof[0] = 0;
        vm.expectRevert("Not whitelisted");
        nftContract.whitelistMint{value: 1 ether}(merkleRoot, proof);

        skip(20 minutes); // skip to public sale time
        vm.expectRevert("Presale ended");
        nftContract.whitelistMint{value: 1 ether}(merkleRoot, proof);

        vm.stopPrank();
    }

    function test_AdminMintProcess() public {
        vm.startPrank(admin);
        uint256 initialTokenId = nftContract.getNextTokenId();
        uint256 mintAmount = 100;
        assertEq(initialTokenId, 0);

        vm.expectRevert("Presale not started");
        nftContract.batchMint(admin, mintAmount);

        skip(10 minutes); // skip to start time

        vm.expectRevert("Invalid address");
        nftContract.batchMint(address(0), mintAmount);

        vm.expectRevert("Invalid amount");
        nftContract.batchMint(admin, 0);

        uint256 maxSupply = nftContract.MAX_SUPPLY();
        vm.expectRevert("Exceeded max supply");
        nftContract.batchMint(admin, maxSupply + 1);

        uint256 adminMaxAmount = nftContract.ADMIN_MAX_MINT_AMOUNT();
        vm.expectRevert("Exceeded max admin mint amount");
        nftContract.batchMint(admin, adminMaxAmount + 1);

        nftContract.batchMint(admin, mintAmount);
        assertEq(nftContract.getNextTokenId(), mintAmount);
    }
}
