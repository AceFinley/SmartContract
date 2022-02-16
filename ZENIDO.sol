// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (token/ERC20/utils/SafeERC20.sol)

pragma solidity ^0.8.0;

import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";

library MerkleProof {
    /**
     * @dev Returns true if a `leaf` can be proved to be a part of a Merkle tree
     * defined by `root`. For ,this a `proof` must be provided, containing
     * sibling hashes on the branch from the leaf to the root of the tree. Each
     * pair of leaves and each pair of pre-images are assumed to be sorted.
     */
    function verify(bytes32[] memory proof, bytes32 root, bytes32 leaf) internal pure returns (bool) {
        bytes32 computedHash = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];

            if (computedHash <= proofElement) {
                // Hash(current computed hash + current element of the proof)
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                // Hash(current element of the proof + current computed hash)
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }

        // Check if the computed hash (root) is equal to the provided root
        return computedHash == root;
    }
}

contract Ido is ReentrancyGuard{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    address private creator;
    
    address public immutable zentoken;
    uint256 public immutable startDate = block.timestamp + 30 days;
    uint256 public exchangeRate = 2;
    uint256 public minAllocation = 1e17;
    uint256 public maxAllocation = 100 * 1e18;  // 18 decimals
    uint256 public immutable maxFundsRaised;
    uint256 public totalRaise;
    uint256 public heldTotal;
    address payable public immutable ETHWallet;
    bool public transferStatus = true;
    bool public isFunding = true;
    
    bytes32 public merkleRoot;

    mapping(address => uint256) public heldTokens;
    mapping(address => uint256) public heldTimeline;

    event Contribution(address from, uint256 amount);
    event ReleaseTokens(address from, uint256 amount);
    event CloseSale(address from);
    event SetMerkleRoot(address from);
    event SetMinAllocation(address from, uint256 minAllocation);
    event SetMaxAllocation(address from, uint256 maxAllocation);
    event UpdateRate(address from, uint256 rate);
    event ChangeCreator(address from);
    event ChangeTransferStats(address from);

    modifier onlyOwner() {
        require(msg.sender == creator, "Ido: caller is not the owner");
        _;
    }

    modifier checkStart(){
        require(block.timestamp >= startDate, "The project has not yet started");
        _;
    }

    constructor(
        address payable _wallet,
        address _zentoken,
        uint256 _maxFundsRaised

        // uint256 _startDate
    ) public {
        // startDate = _startDate;   // One block in 3 seconds, 24h hours later ( current block + 28800  )
        maxFundsRaised = _maxFundsRaised;   // 18 decimals
        creator = msg.sender;
       require(address(_wallet) != address(0), "Ido: wallet is 0" );
        ETHWallet = _wallet;
        require(address(_zentoken) != address(0), "Ido: zentoken is 0");
        zentoken = _zentoken;
    }

    function closeSale() external onlyOwner {
        isFunding = false;
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner{
        merkleRoot = _merkleRoot;
    }

    function setMinAllocation(uint256 _minAllocation) external onlyOwner {
        minAllocation = _minAllocation;
    }

    function setMaxAllocation(uint256 _maxAllocation) external onlyOwner {
        maxAllocation = _maxAllocation;
    }

    // CONTRIBUTE FUNCTION
    // converts ETH to TOKEN and sends new TOKEN to the sender
    receive() external payable nonReentrant checkStart {
        require(msg.value > minAllocation && msg.value <= maxAllocation, "The subscription quantity exceeds the limit");
        require(isFunding, "ido is closed");
        require(totalRaise + msg.value <= maxFundsRaised, "The total raise is higher than maximum raised funds");

        uint256 heldAmount = exchangeRate * msg.value;
        totalRaise += msg.value;
        if (totalRaise >= maxFundsRaised){
            isFunding = false;
        }
        IERC20(ETHWallet).safeTransfer(ETHWallet, msg.value);
        createHoldToken(msg.sender, heldAmount);
        emit Contribution(msg.sender, heldAmount);
    }

    // CONTRIBUTE FUNCTION
    // converts ETH to TOKEN and sends new TOKEN to the sender
    function contribut(uint256 index, address account, uint256 amount, bytes32[] calldata merkleProof) external payable nonReentrant checkStart {
        // require(msg.value >= minAllocation && msg.value <= maxAllocation, "The quantity exceeds the limit");
        require(msg.value >= minAllocation, "The quantity is too low");
        require(msg.value <= maxAllocation, "The quantity is too high");

        require(isFunding, "ido is closed");
        require(totalRaise + msg.value <= maxFundsRaised, "The total raise is higher than maximum raised funds");

        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(index, msg.sender, amount));
        require(MerkleProof.verify(merkleProof, merkleRoot, node), 'Whitelist: Invalid proof.');

        uint256 heldAmount = exchangeRate * msg.value;
        totalRaise += msg.value;
        if (totalRaise >= maxFundsRaised){
            isFunding = false;
        }
        IERC20(ETHWallet).safeTransfer(ETHWallet, msg.value);
        createHoldToken(msg.sender, heldAmount);
        emit Contribution(msg.sender, heldAmount);
    }

    // update the ETH/COIN rate
    function updateRate(uint256 rate) external onlyOwner {
        require(isFunding, "ido is closed");
        require(rate <= 100_100*100, "Rate is higher than total supply");
        exchangeRate = rate;
    }

    // change creator address
    function changeCreator(address _creator) external onlyOwner {
        require(address(_creator) != address(0), "Ido: _creator is 0");
        creator = _creator;
    }

    // change transfer status for ERC20 token
    function changeTransferStatus(bool _allowed) external onlyOwner {
        transferStatus = _allowed;
    }

    // public function to get the amount of tokens held for an address
    function getHeldCoin(address _address) external view returns (uint256) {
        return heldTokens[_address];
    }

    // function to create held tokens for developer
    function createHoldToken(address _to, uint256 amount) internal {
        heldTokens[_to] = amount;
        heldTimeline[_to] = block.number;
        heldTotal += amount;
    }

    // function to release held tokens for developers
    function releaseHeldCoins() external checkStart {
        
        require(!isFunding, "Haven't reached the claim goal");
        require(heldTokens[msg.sender] > 0, "Number of holdings is 0");
        require(block.number >= heldTimeline[msg.sender], "Abnormal transaction");
        require(transferStatus, "Transaction stopped");
        uint256 held = heldTokens[msg.sender];
        heldTokens[msg.sender] = 0;
        heldTimeline[msg.sender] = 0;
        IERC20(zentoken).transfer(msg.sender, held);
        emit ReleaseTokens(msg.sender, held);
    }
}