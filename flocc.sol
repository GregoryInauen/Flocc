pragma solidity ^0.4.17;

contract Dao {
    //init parameters
    uint256 public holdingTime;
    uint256 public generationRate;

    //Address to get token data from
    address ledgerAddress;
    Flocc ledger;

    // number of addresses participating in voting
    uint256 public nrAddresses = 0;

    // Size of Pool
    uint256  poolMax = 3000000000000000;

    //Amount currently in pool
    function getPool() public view returns (uint) {
        return this.balance / 1000000000000000;
    }

    //Mappings to keep track of Proposed values
    mapping(address => uint256) public proposedHoldingTime;
    mapping(address => uint256) public proposedGenerationRate;

    //used to iterate through addresses
    mapping(uint256 => address) addressAtIndex;

    //total tokens in circulation
    uint256 public totalSupply;
    

    function setLedgerAddress (address _ledgerAddress) public { // Set ledger address, must do it
        ledgerAddress = _ledgerAddress;
        ledger = Flocc(ledgerAddress);
    }

    // Can be called by user to propose a value for generationRate and holdingTime
    function setValue (uint256 _newHt, uint256 _newGr) public payable {
        require(msg.value == 1000000000000000); // cost for vote
        require(_newGr != 0 && _newHt != 0);
        if (proposedHoldingTime[msg.sender] == 0) { // if not voted yet
            nrAddresses++;
            addressAtIndex[nrAddresses] = msg.sender; // add to voting addresses

        }
        proposedHoldingTime[msg.sender] = _newHt; // set new proposals
        proposedGenerationRate[msg.sender] = _newGr;
        if (this.balance >= poolMax) { //check if pool is full
            updatePool(msg.sender); // update global values
            msg.sender.transfer(poolMax); // Pay Caller gas used to update DAO
        }
    }

    // update value
    function updatePool(address) private {
        uint256 htCount;
        uint256 grCount;
        uint256 nullValues;
        uint256 currWeight;
        uint256 totalWeight;
        totalSupply = getTotalToken();
        
        for (uint256 i = 1; i <= nrAddresses; i++) { //iterate using addressAtIndex mapping to get addresses
            currWeight = getWeight(addressAtIndex[i]);
            if (currWeight == 0) {
                nullValues++;
            }
            htCount += proposedHoldingTime[addressAtIndex[i]] * currWeight;
            grCount += proposedGenerationRate[addressAtIndex[i]] * currWeight;
            totalWeight += currWeight;
        }
        getHtGr();
        htCount += holdingTime * (1000 - totalWeight);
        grCount += generationRate * (1000 - totalWeight);
        
        // update value
        holdingTime = htCount / ((nrAddresses - nullValues) * 1000); // divide per 1000 to set back origianl value
        generationRate = grCount / ((nrAddresses - nullValues) * 1000);
        
        //updatesValues on Ledger
        ledger.updateValues(holdingTime, generationRate);

        // Reset values
        for (uint k = 1; k <= nrAddresses; k++) {
            proposedHoldingTime[addressAtIndex[k]] = 0;
            proposedGenerationRate[addressAtIndex[k]] = 0;
        }
        nrAddresses = 0;
    }

    // computes weight using token balance from Ledger constract
    function getWeight(address adr) private returns (uint) { 
        getTotalToken();
        require(totalSupply != 0);
        return (ledger.balanceOf(adr) * 1000) / totalSupply; // multiplying by 1000 to avoid rounding in integer division
    }

    //gets total amount of tokens in circulation
    function getTotalToken() private returns (uint256) { 
        totalSupply = ledger.getTotalSupply();
        return ledger.getTotalSupply();
    }
    
    function getHtGr() public {
        holdingTime = ledger.holdingTime();
        generationRate = ledger.generationRate();
    }

    // Proposed holdingTime and generationRate of caller
    function getMyProposals() public view returns (uint256, uint256) {
        return (proposedHoldingTime[msg.sender], proposedGenerationRate[msg.sender]);
    }

    function getBalanceForUser(address user) public returns (uint) {
        Flocc floccname = Flocc(ledgerAddress);
        return floccname.balanceOf(user);
    }
 }


contract Owned { //bridge-contract to make DAO the owner
    address public owner; //address of DAO
    uint  decimals = 18; //1 flocc = 10**18 pablo's
    uint  floccMax; //Flocc-Cap. Total amount of possible Floccs in the market
    address ledgerAddress;

    function Owned() public {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    function transferOwnership(address newOwner, uint _floccMax) public onlyOwner {
        Flocc floccname = Flocc(ledgerAddress);
        floccname.setFloccMax(floccMax);
        owner = newOwner;
        floccMax = _floccMax * 10 ** uint(decimals);
    }

    function getFloccMax() view public returns(uint) {
        return floccMax;
    }
    
    function getOwner() view public returns (address) {
        return owner;
    }
}


contract Flocc is Owned { //actual Token-contract
    string public name;
    string public symbol;
    uint public totalSupply = 0; //amount of floccs in market
    uint public minPointer; //points on oldest relevant transaction on TransactionLedger(mapping)
    uint public maxPointer; //points on newest transaction on TransactionLedger(mapping)
    uint public holdingTime = 120; //in seconds
    uint public generationRate; // every spent ether = generationRate floccs

    mapping(address => uint) public balanceOf; //tracks balances
    mapping(address => mapping(address => uint)) public allowed; //tracks 3rd parties'access
    mapping(uint => Receiver) transactionLedger; //tracks all Flocc-transactions. later used for re-attribution

    event TransferEvent(address indexed from, address indexed to, uint value); //use unknown
    event ApprovalEvent(address indexed tokenOwner, address indexed spender, uint amount); //use unknown
    
    function createTransaction(address _owner, uint _amount) internal {
        transactionLedger[maxPointer].timestamp = now;
        transactionLedger[maxPointer].receiver = _owner;
        transactionLedger[maxPointer].amount = _amount;
        maxPointer++;
    }
    
    function getTransactionLedger(uint index) view public returns (uint, address, uint) {
        checkTime();
        return (transactionLedger[index].timestamp, transactionLedger[index].receiver, transactionLedger[index].amount);
    } 
    
    function checkTime() public { // Check if the oldest transaction is past the holdingTime
        uint timestampNow = now;
        //for (uint i = minPointer; transactionLedger[i].timestamp > (timestampNow - holdingTime); i++) {
        for (uint i = minPointer; i < maxPointer; i++) {
            if (transactionLedger[i].timestamp < (timestampNow - holdingTime)) {
                if(balanceOf[transactionLedger[i].receiver] - transactionLedger[i].amount < 0) {
                    balanceOf[transactionLedger[i].receiver] = 0;
                } else {
                    balanceOf[transactionLedger[i].receiver] -= transactionLedger[i].amount;
                }
                totalSupply -= transactionLedger[i].amount;
                transactionLedger[i].amount = 0;
                if (minPointer++ < maxPointer) {
                    minPointer++;
                } else {
                    minPointer = maxPointer;
                }
            }
        }
    }
    

    struct Receiver { //the data which later stands in the transactionLedger
        uint timestamp; //in seconds
        address receiver; //address of receiver
        uint amount; //amount of floccs in this transaction
    }

    function Flocc() public { //flocc-constructor
        name = "Flocc";
        symbol = "FLO";
        floccMax = 100;
        owner = msg.sender;
    }    

    function mintToken(address target, uint mintedAmount) public onlyOwner { //creates or re-attributes Flocc-Coins
        createTransaction(target, mintedAmount);
        checkTime();
        if (totalSupply >= floccMax) {//all Floccs in market. check for oldest
            uint stealAmount = mintedAmount;
            uint i = minPointer;
            
            while (stealAmount > 0) { 
                if (stealAmount <= transactionLedger[i].amount) { //this transaction is big enough
                    transferForMintToken(transactionLedger[i].receiver, target, stealAmount);
                    transactionLedger[i].amount -= stealAmount;
                    stealAmount = 0;
                } else { //need also to have a look at newer transaction
                    transferForMintToken(transactionLedger[i].receiver, target, transactionLedger[i].amount);
                    stealAmount -= transactionLedger[i].amount;
                    transactionLedger[i].amount = 0;
                    i++;
                }
            }
            minPointer = i;

        } else { // not all Floccs in market. create new token
            uint stillFree = floccMax - totalSupply;
            if (stillFree >= mintedAmount) { //everything possible by creating tokens
                balanceOf[target] += mintedAmount;
                totalSupply += mintedAmount;
                TransferEvent(owner, target, mintedAmount);
            } else { //have to re-attribut as well
                balanceOf[target] += stillFree;
                totalSupply += stillFree;
                TransferEvent(owner, target, stillFree);
                uint stealAmount2 = mintedAmount - stillFree;
                uint j = minPointer;
                
                while (stealAmount2 > 0) {
                    if (stealAmount2 <= transactionLedger[j].amount) { //this transaction is big enough
                        transferForMintToken(transactionLedger[j].receiver, target, stealAmount2);
                        transactionLedger[j].amount -= stealAmount2;
                        stealAmount2 = 0;
                    } else { //need also to have a look at newer transaction
                        transferForMintToken(transactionLedger[j].receiver, target, transactionLedger[j].amount);
                        stealAmount -= transactionLedger[j].amount;
                        transactionLedger[j].amount = 0;
                        j++;
                    }
                }
                minPointer = j;
            }
        }
    }

    function transferForMintToken(address from, address to, uint value) private onlyOwner {//intern function for mintToken-function, to make transfer
        balanceOf[from] -= value;
        balanceOf[to] += value;
    }

    function transfer(address _to, uint _value) public returns(bool) { //to have the transfer internally
        checkTime();
        _transfer(msg.sender, _to, _value);
    }

    function _transfer(address _from, address _to, uint _value) internal onlyOwner {
        checkTime();
        require(_to != 0x0); //not necessairy, required for burning
        require(balanceOf[_from] >= _value); //has enough floccs
        require(balanceOf[_to]+_value > balanceOf[_to]); // prevent overflow
        balanceOf[_from] -= _value; //take floccs away
        balanceOf[_to] += _value; // give floccs
        uint remaining = _value; //everything underneath is for: iterate over transactionLedger & substract as long from sender balance until _value reached
        uint i = minPointer;

        while (remaining > 0) {
            if (transactionLedger[i].receiver == _from) { //receiver of this transaction was our "_from"
                if (remaining <= transactionLedger[i].amount) { //transaction big enough
                    transactionLedger[i].amount -= remaining;
                    remaining = 0;
                } else {
                    remaining -= transactionLedger[i].amount;
                    transactionLedger[i].amount = 0;
                    i++;
                }
            } else { //another receiver
                i++;
            }
        }

        if (0 != maxPointer) {
            maxPointer++;
        }
        transactionLedger[maxPointer].amount = _value; //create new transaction for transactionLedger
        transactionLedger[maxPointer].receiver = _to;
        transactionLedger[maxPointer].timestamp = now;
        TransferEvent(_from, _to, _value); //event
    }

    function transferFrom (address _from, address _to, uint _value) public returns(bool) { //makes possible to allow 3rd parties to handle your transfer
        checkTime();
        uint allowance = allowed[_from][msg.sender];
        require(balanceOf[_from] >= _value && allowance >= _value);
        _transfer(_from, _to, _value);
        return true;
    }

    function getBalance(address _owner) public onlyOwner returns(uint) {
        checkTime();
        uint reward = calcReward(_owner); //check now for possible token-reward
        if (reward != 0) { //has right to get floccs
            mintToken(_owner, reward);
        }
        return balanceOf[_owner];
    }

    function calcReward(address user) public returns (uint) {
        //check blockchain-transactions & decide wheter this user gets floccs
        uint spent = 10;
        return spent * generationRate; //just until we are able to read the data out. returns 0 if no reward
    }

    function allowance(address tokenOwner, address spender) public view returns (uint remaining) { //returns the amount of which 3rd partie still can access
        return allowed[tokenOwner][spender];
    }

    function approve(address spender, uint amount) public returns (bool success) {//gives you opportunity to give someone an allowance
        allowed[msg.sender][spender] = amount;
        ApprovalEvent(msg.sender,spender,amount);
        return true;
    }
    
    function timeNow() view public returns (uint) {
        return now;
    }

    function updateValues(uint _newHt,uint _newGr) public onlyOwner{ 
        holdingTime = _newHt;
        generationRate = _newGr;
    }

    function getTotalSupply() public constant returns (uint) { //return totalsupply(=total amount of Floccs on market)
        return totalSupply;
    }

    function calcUserCap(address user) public returns(uint) { //calculates the max of floccs the user can hold
        //read ether-balance out of blockchain & calculate via formula the users cap(max floccs possible for him)
        return 1000; //just for test-case
    }

    function setFloccMax(uint _floccMax) public onlyOwner {
        floccMax = _floccMax;
    }

    function getTransactionLedger() view public returns (uint) {
        return floccMax;
    }
}