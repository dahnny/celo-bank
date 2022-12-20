// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

/**
    @title celo bank contract
    @author Realkayzee
    @notice This contract is a banking system for association
    - association can register their account with a certain number of executive members
    - the registered executive members are the only people eligible to withdraw association funds
    - withdrawal will only be successful when other registered excos approve to the withdrawal of a particular exco
*/

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract celoBank is Ownable {
/**
    ============================
    -----------Events-----------
    ============================
*/
    event _initTransaction(address, uint256);
    event _getAccountNumber(uint256);

/**
    ============================
    ------Error Messages--------
    ============================
*/

    error _assertExco(string);
    error _noZeroAmount(string);
    error _alreadyConfirmed(string);
    error _notApprovedYet(string);
    error _alreadyExecuted(string);
    error _addressZero(string);

/**
    ============================
    ------State Variables-------
    ============================
*/
    uint256 accountNumber = 1; // Association account number generator
    IERC20 tokenAddress;
    mapping(uint256 => AssociationDetails) public association; // track account number to associationDetails


/// @dev map creator to association created. creator can't create multiple account with the same associated address
    mapping(address => AssociationInfo) associationCreator; 

/// @dev A layout for the association
    struct AssociationDetails{
        string associationName;
        address[] excoAddr; // excutive addresses
        uint40 excoNumber; // The number of excutives an association register
        mapping(address => WithdrawalRequest) requestOrder; // to track a withdrawal request by an exco
        mapping(address => uint256) memberBalances; // to track the amount each member deposited
        mapping(address => mapping(address => bool)) confirmed; // to track an exco confirmation to a withdrawal request
        uint256 associationBalance;
    }

    struct WithdrawalRequest {
        address exco; // exco that initiate the withdrawal request
        uint40 noOfConfirmation;
        bool executed;
        uint216 amount;
    }

    struct AssociationInfo {
        string infoAssName;
        uint256 associationAcctNumber;
    }

/**
    @dev The modifier checks if an exco has confirmed before
    @param _associationAcctNumber: the association account number
    @param _exco the exco that initiated the withdrawal request to approve
*/
    modifier alreadyConfirmed(uint256 _associationAcctNumber, address _exco){
        AssociationDetails storage AD = association[_associationAcctNumber];
        if(AD.confirmed[_exco][msg.sender] == true) revert _alreadyConfirmed("You already approve");

        _;
    }

    modifier alreadyExecuted(uint256 _associationAcctNumber, address _exco){
        AssociationDetails storage AD = association[_associationAcctNumber];
        if(AD.requestOrder[_exco].executed == true) revert _alreadyExecuted("Transaction already executed");

        _;
    }

    constructor(IERC20 _addr) {
        tokenAddress = _addr;
    }
/**
    @dev function to change token contract address
    @param _contractAddress: to input token contract address
*/
    function changeContractAddress(IERC20 _contractAddress) external onlyOwner {
        tokenAddress = _contractAddress;
    }


    function onlyExco(uint256 _associationAcctNumber) internal view returns(bool check){
        AssociationDetails storage AD = association[_associationAcctNumber];
        for(uint i = 0; i < AD.excoAddr.length; i++){
            if(msg.sender == AD.excoAddr[i]){
                check = true;
            }
        }
    }

/**
    @dev Function to ensure address zero is not used as executive address
    @param _assExcoAddr: array of executive addresses
*/

    function noAddressZero(address[] memory _assExcoAddr) pure internal {
        for(uint i = 0; i < _assExcoAddr.length; i++) {
            if(address(0) == _assExcoAddr[i]) revert _addressZero("Account Creation: address zero can't be an exco");
        }
    }


/**
    @dev function to create account
    @param _associationName: the association name
    @param _assExcoAddr: association executive addresses - array of addresses
    @param _excoNumber: number of executives
    @notice this is responsible for creating association account
*/
    function createAccount(string memory _associationName, address[] memory _assExcoAddr, uint40 _excoNumber) external {
        require(associationCreator[msg.sender].associationAcctNumber == 0, "Account creation: can't create multiple account");
        if(_assExcoAddr.length != _excoNumber) revert _assertExco("Specified exco number not filled");
        noAddressZero(_assExcoAddr);
        AssociationDetails storage AD = association[accountNumber];
        AD.associationName = _associationName;
        AD.excoAddr = _assExcoAddr;
        AD.excoNumber = _excoNumber;


        // to track creator to association created by association name and association account number
        associationCreator[msg.sender] = AssociationInfo(_associationName, accountNumber);

        emit _getAccountNumber(accountNumber);

        accountNumber++;
    }



/// @dev Function to retrieve association account number
    function checkAssociationAccountNo(address _creatorAddr) public view returns(uint256){
        return associationCreator[_creatorAddr].associationAcctNumber;
    }


/// @dev function for users deposit to association bank
    function deposit(uint256 _associationAcctNumber, uint256 payFee) external payable {
        if(payFee == 0) revert _noZeroAmount("Deposit: zero deposit not allowed");
        AssociationDetails storage AD = association[_associationAcctNumber];
        require(tokenAddress.transferFrom(msg.sender, address(this), payFee), "Transfer Failed");
        AD.associationBalance += payFee;
        AD.memberBalances[msg.sender] += payFee;
    }

/// @dev function that initiate transaction
    function initTransaction(uint216 _amountToWithdraw, uint256 _associationAcctNumber) public {
        AssociationDetails storage AD = association[_associationAcctNumber];
        require(onlyExco(_associationAcctNumber), "Not an exco");
        require(_amountToWithdraw > 0, "Amount must be greater than zero");
        require(_amountToWithdraw  <= AD.associationBalance, "Insufficient Fund in association balance");

        AD.requestOrder[msg.sender] = WithdrawalRequest({
            exco: msg.sender,
            noOfConfirmation: 0,
            executed: false,
            amount: _amountToWithdraw
        });



        emit _initTransaction(msg.sender, _amountToWithdraw);
    }

/// @dev function for approving withdrawal

    function approveWithdrawal(address initiator, uint256 _associationAcctNumber) public alreadyExecuted(_associationAcctNumber, initiator) alreadyConfirmed(_associationAcctNumber, initiator){
        require(onlyExco(_associationAcctNumber), "Not an Exco");
        AssociationDetails storage AD = association[_associationAcctNumber];
        AD.confirmed[initiator][msg.sender] = true;
        AD.requestOrder[initiator].noOfConfirmation += 1;
    }


/// @dev function responsible for withdrawal after approval has been confirmed

    function withdrawal(uint256 _associationAcctNumber) public alreadyExecuted(_associationAcctNumber, msg.sender){
        require(onlyExco(_associationAcctNumber), "Not an Exco");
        AssociationDetails storage AD = association[_associationAcctNumber];
        WithdrawalRequest storage WR = AD.requestOrder[msg.sender];
        if(WR.noOfConfirmation == AD.excoNumber){
            WR.executed = true;
            AD.associationBalance -= WR.amount;
            require(tokenAddress.transfer(msg.sender, WR.amount), "Trasfer Failed");
        }
    }

/**
    @dev function that handles revertion of approval
    @param _associationAcctNumber: association account number
    @param initiator: address of the initiator
*/

    function revertApproval(uint256 _associationAcctNumber, address initiator) public alreadyExecuted(_associationAcctNumber, initiator){
        require(onlyExco(_associationAcctNumber), "Not an Exco");
        AssociationDetails storage AD = association[_associationAcctNumber];
        if(AD.confirmed[initiator][msg.sender] == false) revert _notApprovedYet("You have'nt approved yet");
        AD.confirmed[initiator][msg.sender] = false;
        AD.requestOrder[initiator].noOfConfirmation -= 1;
    }

/**
    @dev A function to check the amount an initiator/exco wants to withdraw
    @param _associationAcctNumber: association account number
    @param initiator: address of the initiator
*/


    function checkAmountRequest(uint256 _associationAcctNumber,address initiator) public view returns(uint256){
        AssociationDetails storage AD = association[_associationAcctNumber];
        return AD.requestOrder[initiator].amount;
    }


/**
    @dev function to check the amount own by an association
    @param _associationAcctNumber: association account number
*/ 
    function AmountInAssociationVault(uint256 _associationAcctNumber) public view returns(uint256 ){
        AssociationDetails storage AD = association[_associationAcctNumber];
        return AD.associationBalance;
    }

/**
    @dev function to check the total number of approval a transaction has reached
    @param _associationAcctNumber: association account number
*/ 

    function checkNumApproval(uint256 _associationAcctNumber, address initiator) public view returns (uint256) {
        AssociationDetails storage AD = association[_associationAcctNumber];
        return AD.requestOrder[initiator].noOfConfirmation;
    }

/**
    @dev functions that checks member balance in a particular association
    @param _associationAcctNumber: association account number
    @param _addr: member address to check
*/ 
    function checkUserDeposit(uint256 _associationAcctNumber, address _addr) public view returns(uint256) {
        AssociationDetails storage AD = association[_associationAcctNumber];
        return AD.memberBalances[_addr];
    }
}



// association 1
// ["0x5B38Da6a701c568545dCfcB03FcB875f56beddC4","0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2","0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db"]
