// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

/// @title PresaleToken Contract
/// @author Miltos Miltiadous
/// @notice This contract manages the presale of a token.
/// @dev It includes functions for transferring tokens, approving spending, and buying tokens during a sale.
contract PresaleToken {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    address public owner;
    bool public saleActive = false;
    uint256 public salePrice;
    bool public isStopped = false; // Emergency stop state variable
    bool private locked;
    address public pauser;
    bool public paused;
    uint256 public pauseTime;
    uint256 public pauseDuration;
    bool public saleInitialized;

    /// @dev Mapping from address to balance of tokens.
    mapping(address => uint256) public balanceOf;
    /// @dev Mapping from owner to spender to allowance.
    mapping(address => mapping(address => uint256)) public allowance;

    //uint256 public constant purchaseCooldown = 1 minutes; // Adjust cooldown period as needed
    mapping(address => uint256) lastPurchaseTimestamp;

    uint256 public constant maxTokensPerInterval = 100; // Maximum tokens allowed to be purchased per interval
    uint256 public constant buyInterval = 1 hours; // Time interval for rate limiting

    mapping(address => uint256) public lastPurchaseTime;
    mapping(address => uint256) public tokensPurchased;

    uint256 public constant purchaseCooldown = 1 hours; // Cooldown period for token purchases

    uint256 public constant revealPeriod = 1 hours; // Time period for reveal phase
    mapping(address => uint256) public commitTimestamp; // Mapping to store commit timestamps
    mapping(address => uint256) public committedValue; // Mapping to store committed values

    /// @dev Modifier to prevent reentrancy attacks.
    modifier nonReentrant() {
        require(!locked, "Reentrant call");
        locked = true;
        _;
        locked = false;
    }

    /// @dev Modifier to restrict access to the contract owner.
    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "Only the contract owner can call this function"
        );
        _;
    }

    /// @dev Modifier to ensure functions can only be called when the contract is not stopped.
    modifier stoppedInEmergency() {
        require(!isStopped, "Contract is stopped");
        _;
    }

    /// @dev Modifier to ensure functions can only be called when the contract is stopped.
    modifier onlyWhenStopped() {
        require(isStopped, "Contract is not stopped");
        _;
    }
    event SaleStarted();
    event EmergencyWithdrawal(address indexed user, uint256 amount);

    event Commit(address indexed buyer, uint256 commitValue);
    event Reveal(address indexed buyer, uint256 salt, uint256 revealValue);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    event SaleStarted(uint256 salePrice);

    event SaleEnded();

    /// @notice Constructor to initialize the contract.
    /// @param _name The name of the token.
    /// @param _symbol The symbol of the token.
    /// @param _decimals The number of decimals the token uses.
    /// @param _totalSupply The total supply of tokens.
    /// @param _salePrice The price of tokens during the sale, denominated in Wei.
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _totalSupply,
        uint256 _salePrice
    ) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        totalSupply = _totalSupply;
        salePrice = _salePrice;
        owner = msg.sender;
        balanceOf[owner] = totalSupply;
    }

    /// @notice Transfers tokens from the sender to another address.
    /// @param _to The address to transfer tokens to.
    /// @param _value The amount of tokens to transfer.
    /// @return success True if the transfer was successful.
    function transfer(address _to, uint256 _value)
        public
        nonReentrant
        returns (bool success)
    {
        require(_to != address(0), "Invalid recipient address");
        require(balanceOf[msg.sender] >= _value, "Insufficient balance");

        // Reduce allowance if applicable
        if (_value < allowance[msg.sender][_to]) {
            allowance[msg.sender][_to] -= _value;
            emit Approval(msg.sender, _to, allowance[msg.sender][_to]);
        }

        // Transfer tokens
        balanceOf[msg.sender] -= _value;
        balanceOf[_to] += _value;
        emit Transfer(msg.sender, _to, _value);
        return true;
    }

    /// @notice Approves another address to spend tokens on behalf of the sender.
    /// @param _spender The address to approve.
    /// @param _value The amount of tokens to approve.
    /// @return success True if the approval was successful.
    function approve(address _spender, uint256 _value)
        public
        nonReentrant
        returns (bool success)
    {
        allowance[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    /// @notice Transfers tokens from one address to another.
    /// @param _from The address to transfer tokens from.
    /// @param _to The address to transfer tokens to.
    /// @param _value The amount of tokens to transfer.
    /// @return success True if the transfer was successful.
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) public nonReentrant returns (bool success) {
        require(_to != address(0), "Invalid recipient address");
        require(_value <= balanceOf[_from], "Insufficient balance");
        require(
            _value <= allowance[_from][msg.sender],
            "Insufficient allowance"
        );

        // Reduce allowance if applicable
        if (_value < allowance[_from][msg.sender]) {
            allowance[_from][msg.sender] -= _value;
            emit Approval(_from, msg.sender, allowance[_from][msg.sender]);
        }

        // Transfer tokens
        balanceOf[_from] -= _value;
        balanceOf[_to] += _value;
        emit Transfer(_from, _to, _value);
        return true;
    }

    modifier whenNotPaused() {
        require(
            !paused || block.timestamp >= pauseTime + pauseDuration,
            "Contract is paused"
        );
        _;
    }

    modifier onlyPauser() {
        require(msg.sender == pauser, "Only the pauser can call this function");
        _;
    }

    function pauseContract(uint256 _pauseDuration) public onlyOwner {
        paused = true;
        pauser = msg.sender;
        pauseTime = block.timestamp;
        pauseDuration = _pauseDuration;
    }

    function unpauseContract() public onlyPauser {
        paused = false;
    }

    modifier onlySaleNotInitialized() {
        require(!saleInitialized, "Sale has already been initialized");
        _;
    }

    function initializeSale(uint256 _salePrice)
        public
        onlyOwner
        onlySaleNotInitialized
    {
        salePrice = _salePrice;
        saleInitialized = true;
    }

    function startSale() public onlyOwner {
        require(!saleActive, "Sale is already active.");
        saleActive = true;
        emit SaleStarted();
    }

    /// @notice Ends the token sale.
    function endSale() public onlyOwner {
        saleActive = false;
        emit SaleEnded();
    }

    /// @notice Buys tokens during the sale.
    function buyTokens(uint256 _commit)
        public
        payable
        nonReentrant
        stoppedInEmergency
    {
        require(saleActive, "Sale is not active.");
        require(msg.value > 0, "Invalid token purchase amount.");
        require(_commit > 0, "Invalid commit value.");

        // Store commit timestamp and value
        commitTimestamp[msg.sender] = block.timestamp;
        committedValue[msg.sender] = _commit;

        emit Commit(msg.sender, _commit);
    }

    function revealPurchase(uint256 _salt, uint256 _value) public nonReentrant stoppedInEmergency {
    require(commitTimestamp[msg.sender] > 0, "No commit found.");
    require(block.timestamp >= commitTimestamp[msg.sender] + revealPeriod, "Reveal period not started.");

    // Calculate the commitment hash
    bytes32 commitHash = keccak256(abi.encodePacked(_salt, _value));

    // Retrieve the committed value
   bytes32 committedHash = keccak256(abi.encodePacked(committedValue[msg.sender]));


    // Ensure that the revealed value matches the committed value
    require(commitHash == committedHash, "Invalid commit-reveal pair.");

    // Proceed with the token purchase
    uint256 tokensToBuy = _value / salePrice;
    require(balanceOf[owner] >= tokensToBuy, "Not enough tokens available.");

    // Transfer tokens
    balanceOf[owner] -= tokensToBuy;
    balanceOf[msg.sender] += tokensToBuy;

    // Emit events
    emit Transfer(owner, msg.sender, tokensToBuy);
    emit Reveal(msg.sender, _salt, _value);
}


    // Internal function to calculate tokens to buy based on Ether value
    function calculateTokensToBuy(uint256 _value)
        internal
        view
        returns (uint256)
    {
        return _value / salePrice;
    }

    /// @notice Stops the contract.
    function stopContract() public onlyOwner {
        isStopped = true;
    }

    /// @notice Resumes the contract.
    function resumeContract() public onlyOwner {
        isStopped = false;
    }

    /// @notice Allows the owner to withdraw a specified amount of Ether from the contract.
    /// @param _amount The amount of Ether to withdraw.
    function withdrawEther(uint256 _amount) public onlyOwner {
        require(_amount > 0, "Amount must be greater than 0");
        require(
            address(this).balance >= _amount,
            "Insufficient contract balance"
        );

        (bool success, ) = payable(owner).call{value: _amount}("");
        require(success, "Ether withdrawal failed");
    }

    /// @notice Allows users to view their token balance when the contract is stopped.
    function emergencyWithdraw() public onlyWhenStopped {
        uint256 amount = balanceOf[msg.sender];
        require(amount > 0, "No tokens to withdraw");

        // Update the user's balance
        balanceOf[msg.sender] = 0;

        // Transfer tokens to the user
        emit Transfer(msg.sender, address(0), amount);

        // Emit an event to indicate the withdrawal
        emit EmergencyWithdrawal(msg.sender, amount);
    }
}
