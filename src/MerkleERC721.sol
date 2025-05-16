// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {ERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract MerkleERC721 is ERC721EnumerableUpgradeable, OwnableUpgradeable {
    event SetWhitelist(bytes32 merkleRoot, uint256 presaleFee);
    event Mint(address user, uint256 tokenId);
    event WithdrawFunds();

    struct WhitelistInfo {
        bool isSet;
        uint224 presaleFee;
    }

    uint256 public constant MAX_SUPPLY = 3000;
    uint256 public constant ADMIN_MAX_MINT_AMOUNT = 2000;

    uint256 public presaleStartTime;
    uint256 public presaleEndTime;
    uint256 public mintFee;
    uint256 public adminMintedAmount;
    uint256 private _nextTokenId;

    mapping(bytes32 merkleRoot => WhitelistInfo) public whitelistInfo;
    mapping(address => bool) public hasMinted;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        string memory _name,
        string memory _symbol,
        uint256 _presaleStartTime,
        uint256 _presaleEndTime,
        uint256 _mintFee
    ) external initializer {
        __ERC721_init(_name, _symbol);
        __Ownable_init(_owner);
        presaleStartTime = _presaleStartTime;
        presaleEndTime = _presaleEndTime;
        mintFee = _mintFee;
    }

    function tokenURI(uint256) public pure override returns (string memory) {
        return
            "https://nft.goat.network/assets/848b19b3b6a0c172b5b067f818f76b93992d62aaf15c848dac03eb3e1fcbc95f.json";
    }

    function setTime(
        uint256 _presaleStartTime,
        uint256 _presaleEndTime
    ) external onlyOwner {
        require(_presaleStartTime < _presaleEndTime, "Invalid presale time");
        presaleStartTime = _presaleStartTime;
        presaleEndTime = _presaleEndTime;
    }

    function setMintFee(uint256 _mintFee) external onlyOwner {
        mintFee = _mintFee;
    }

    function getNextTokenId() external view returns (uint256) {
        return _nextTokenId;
    }

    // Function to generate Merkle Root from an array of addresses
    function generateWhitelistMerkleRoot(
        address[] memory addresses
    ) external pure returns (bytes32) {
        require(addresses.length > 0, "Array cannot be empty");

        // If only one address, return its hash as root
        if (addresses.length == 1) {
            return keccak256(abi.encodePacked(addresses[0]));
        }

        // Convert addresses to leaf nodes by hashing them
        bytes32[] memory leaves = new bytes32[](addresses.length);
        for (uint256 i = 0; i < addresses.length; i++) {
            leaves[i] = keccak256(abi.encodePacked(addresses[i]));
        }

        // Build the Merkle Tree
        while (leaves.length > 1) {
            bytes32[] memory tempLeaves = new bytes32[](
                (leaves.length + 1) / 2
            );

            for (uint256 i = 0; i < leaves.length; i += 2) {
                if (i + 1 < leaves.length) {
                    // Pair exists, hash them together
                    tempLeaves[i / 2] = _hashPair(leaves[i], leaves[i + 1]);
                } else {
                    // Odd leaf out, promote it to next level
                    tempLeaves[i / 2] = leaves[i];
                }
            }
            leaves = tempLeaves;
        }

        return leaves[0];
    }

    // Generate proof for a specific address
    function generateProof(
        address[] memory addresses,
        address target
    ) external pure returns (bytes32[] memory) {
        require(addresses.length > 0, "Array cannot be empty");

        // Create initial leaves
        bytes32[] memory leaves = new bytes32[](addresses.length);
        uint256 targetIndex = type(uint256).max;

        for (uint256 i = 0; i < addresses.length; i++) {
            leaves[i] = keccak256(abi.encodePacked(addresses[i]));
            if (addresses[i] == target) {
                targetIndex = i;
            }
        }
        require(targetIndex != type(uint256).max, "Target address not found");

        // Store proofs
        bytes32[] memory proof = new bytes32[](0);
        bytes32[] memory tempProof;

        // Build tree and collect proof
        while (leaves.length > 1) {
            bytes32[] memory tempLeaves = new bytes32[](
                (leaves.length + 1) / 2
            );
            uint256 newTargetIndex = targetIndex / 2; // Default to parent index

            for (uint256 i = 0; i < leaves.length; i += 2) {
                if (i + 1 < leaves.length) {
                    // Pair exists
                    tempLeaves[i / 2] = _hashPair(leaves[i], leaves[i + 1]);

                    // If target is in this pair, add sibling to proof
                    if (i == targetIndex) {
                        tempProof = new bytes32[](proof.length + 1);
                        for (uint256 j = 0; j < proof.length; j++) {
                            tempProof[j] = proof[j];
                        }
                        tempProof[proof.length] = leaves[i + 1]; // Right sibling
                        proof = tempProof;
                    } else if (i + 1 == targetIndex) {
                        tempProof = new bytes32[](proof.length + 1);
                        for (uint256 j = 0; j < proof.length; j++) {
                            tempProof[j] = proof[j];
                        }
                        tempProof[proof.length] = leaves[i]; // Left sibling
                        proof = tempProof;
                    }
                } else {
                    // Odd leaf
                    tempLeaves[i / 2] = leaves[i];
                    if (i == targetIndex) {
                        newTargetIndex = i / 2; // Update for odd leaf
                    }
                }
            }
            leaves = tempLeaves;
            targetIndex = newTargetIndex;
        }

        return proof;
    }

    // Function to verify if an address is in the Merkle Tree
    function verifyAddress(
        bytes32[] memory proof,
        bytes32 root,
        address addr
    ) public pure returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(addr));
        return MerkleProof.verify(proof, root, leaf);
    }

    // set merkle root and mint fee for whitelist
    function setWhitelist(
        bytes32 _merkleRoot,
        uint224 _presaleFee
    ) external onlyOwner {
        require(_merkleRoot != 0, "Invalid merkle root");
        whitelistInfo[_merkleRoot] = WhitelistInfo(true, _presaleFee);
        emit SetWhitelist(_merkleRoot, _presaleFee);
    }

    function batchMint(address _to, uint256 _amount) external onlyOwner {
        require(_to != address(0), "Invalid address");
        require(_amount > 0, "Invalid amount");
        require(block.timestamp >= presaleStartTime, "Presale not started");
        require(_nextTokenId + _amount <= MAX_SUPPLY, "Exceeded max supply");
        require(
            adminMintedAmount + _amount <= ADMIN_MAX_MINT_AMOUNT,
            "Exceeded max admin mint amount"
        );
        adminMintedAmount += _amount;
        uint256 tokenId = _nextTokenId;
        for (uint256 i = 0; i < _amount; i++) {
            _safeMint(_to, tokenId);
            emit Mint(_to, tokenId++);
        }
        _nextTokenId = tokenId;
    }

    // mint for whitelist users
    function whitelistMint(
        bytes32 _whitelistMerkleRoot,
        bytes32[] calldata _proof
    ) external payable {
        require(block.timestamp >= presaleStartTime, "Presale not started");
        require(block.timestamp < presaleEndTime, "Presale ended");
        require(
            whitelistInfo[_whitelistMerkleRoot].isSet,
            "Merkle root not set"
        );
        require(
            msg.value == whitelistInfo[_whitelistMerkleRoot].presaleFee,
            "Invalid funds"
        );
        require(
            verifyAddress(_proof, _whitelistMerkleRoot, msg.sender),
            "Not whitelisted"
        );
        _mintToken();
    }

    // mint for all users
    function mint() external payable {
        require(block.timestamp >= presaleEndTime, "Time not reached");
        require(msg.value == mintFee, "Invalid funds");
        _mintToken();
    }

    function _mintToken() internal {
        require(_nextTokenId < MAX_SUPPLY, "Exceeded max supply");
        require(hasMinted[msg.sender] == false, "Already minted");
        hasMinted[msg.sender] = true;
        uint256 tokenId = _nextTokenId++;
        _safeMint(msg.sender, tokenId);
        emit Mint(msg.sender, tokenId);
    }

    function withdrawFunds(address payable _to) external onlyOwner {
        _to.transfer(address(this).balance);
        emit WithdrawFunds();
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // Helper function to hash two nodes
    function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        // Ensure a < b to maintain consistent ordering
        return
            a < b
                ? keccak256(abi.encodePacked(a, b))
                : keccak256(abi.encodePacked(b, a));
    }
}
