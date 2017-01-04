pragma solidity ^0.4.4;

import "./dependencies/Assertive.sol";

/// @title Simple multi signature contract
/// @author Melonport AG <team@melonport.com>
/// @notice Allows multiple owners to agree on any given transaction before execution
/// @notice Inspired by https://github.com/ethereum/dapp-bin/blob/master/wallet/wallet.sol
contract MultiSigWallet is Assertive {

    // TYPES

    struct Transaction {
        address destination;
        uint value;
        bytes data;
        uint nonce;
        bool executed;
    }

    // FILEDS

    // Fields that are only changed in constructor
    address[] multiSigOwners; // Address with signing authority
    mapping (address => bool) public isMultiSigOwner; // Has address siging authority
    uint public requiredSignatures; // Number of signatures required to execute a transaction

    // Fields that can be changed by functions
    bytes32[] transactionList; // Array of transactions hashes
    mapping (bytes32 => Transaction) public transactions; // Maps transaction hash [bytes32[ to Transaction [struct]
    mapping (bytes32 => mapping (address => bool)) public confirmations; // Whether [bool] transaction hash [bytes32] has been confirmed by by owner [address]

    // EVENTS

    event Confirmation(address sender, bytes32 txHash);
    event Revocation(address sender, bytes32 txHash);
    event Submission(bytes32 txHash);
    event Execution(bytes32 txHash);
    event Deposit(address sender, uint value);

    // MODIFIERS

    modifier is_multi_sig_owners_signature(bytes32 txHash, uint8[] v, bytes32[] rs) {
        for (uint i = 0; i < v.length; i++)
            assert(isMultiSigOwner[ecrecover(txHash, v[i], rs[i], rs[v.length + i])]);
        _;
    }

    modifier only_multi_sig_owner {
        assert(isMultiSigOwner[msg.sender]);
        _;
    }

    modifier msg_sender_has_confirmed(bytes32 txHash) {
        assert(confirmations[txHash][msg.sender]);
        _;
    }

    modifier msg_sender_has_not_confirmed(bytes32 txHash) {
        assert(!confirmations[txHash][msg.sender]);
        _;
    }

    modifier transaction_is_not_executed(bytes32 txHash) {
        assert(!transactions[txHash].executed);
        _;
    }

    modifier address_not_null(address destination) {
        //TODO: Test empty input
        assert(destination != 0);
        _;
    }

    modifier valid_amount_of_required_signatures(uint ownerCount, uint required) {
        assert(ownerCount != 0);
        assert(required != 0);
        assert(required <= ownerCount);
        _;
    }

    modifier transaction_is_confirmed(bytes32 txHash) {
        assert(isConfirmed(txHash));
        _;
    }

    // CONSTANT METHODS

    function isConfirmed(bytes32 txHash) constant returns (bool) { return requiredSignatures <= confirmationCount(txHash); }

    function confirmationCount(bytes32 txHash) constant returns (uint count)
    {
        for (uint i = 0; i < multiSigOwners.length; i++)
            if (confirmations[txHash][multiSigOwners[i]])
                count += 1;
    }

    function getPendingTransactions() constant returns (bytes32[]) { return filterTransactions(true); }

    function getExecutedTransactions() constant returns (bytes32[]) { return filterTransactions(false); }

    function filterTransactions(bool isPending) constant returns (bytes32[] transactionListFiltered)
    {
        bytes32[] memory transactionListTemp = new bytes32[](transactionList.length);
        uint count = 0;
        for (uint i = 0; i < transactionList.length; i++)
            if (   isPending && !transactions[transactionList[i]].executed
                || !isPending && transactions[transactionList[i]].executed)
            {
                transactionListTemp[count] = transactionList[i];
                count += 1;
            }
        transactionListFiltered = new bytes32[](count);
        for (i = 0; i < count; i++)
            if (transactionListTemp[i] > 0)
                transactionListFiltered[i] = transactionListTemp[i];
    }

    // NON-CONSTANT INTERNAL METHODS

    function addTransaction(address destination, uint value, bytes data, uint nonce)
        internal
        address_not_null(destination)
        returns (bytes32 txHash)
    {
        txHash = sha3(destination, value, data, nonce);
        if (transactions[txHash].destination == 0) {
            transactions[txHash] = Transaction({
                destination: destination,
                value: value,
                data: data,
                nonce: nonce,
                executed: false
            });
            transactionList.push(txHash);
            Submission(txHash);
        }
    }

    function addConfirmation(bytes32 txHash, address owner)
        internal
        msg_sender_has_not_confirmed(txHash)
    {
        confirmations[txHash][owner] = true;
        Confirmation(owner, txHash);
    }

    // NON-CONSTANT PUBLIC METHODS

    // Methods to submit a transaction
    function submitTransaction(address destination, uint value, bytes data, uint nonce)
        returns (bytes32 txHash)
    {
        txHash = addTransaction(destination, value, data, nonce);
        confirmTransaction(txHash);
    }

    function submitTransactionWithSignatures(address destination, uint value, bytes data, uint nonce, uint8[] v, bytes32[] rs)
        returns (bytes32 txHash)
    {
        txHash = addTransaction(destination, value, data, nonce);
        confirmTransactionWithSignatures(txHash, v, rs);
    }

    // Methods to confirm a given transaction
    function confirmTransaction(bytes32 txHash)
        only_multi_sig_owner
    {
        addConfirmation(txHash, msg.sender);
        if (isConfirmed(txHash))
            executeTransaction(txHash);
    }

    function confirmTransactionWithSignatures(bytes32 txHash, uint8[] v, bytes32[] rs)
        is_multi_sig_owners_signature(txHash, v, rs)
    {
        for (uint i = 0; i < v.length; i++)
            addConfirmation(txHash, ecrecover(txHash, v[i], rs[i], rs[i + v.length]));
        if (isConfirmed(txHash))
            executeTransaction(txHash);
    }

    // Method to revoke a given transaction
    function revokeConfirmation(bytes32 txHash)
        only_multi_sig_owner
        msg_sender_has_confirmed(txHash)
        transaction_is_not_executed(txHash)
    {
        confirmations[txHash][msg.sender] = false;
        Revocation(msg.sender, txHash);
    }

    // Method to execute a given transaction
    function executeTransaction(bytes32 txHash)
        transaction_is_not_executed(txHash)
        transaction_is_confirmed(txHash)
    {
        Transaction tx = transactions[txHash];
        tx.executed = true;
        assert(tx.destination.call.value(tx.value)(tx.data));
        Execution(txHash);
    }

    function MultiSigWallet(address[] setOwners, uint setRequiredSignatures)
        valid_amount_of_required_signatures(setOwners.length, setRequiredSignatures)
    {
        for (uint i = 0; i < setOwners.length; i++)
            isMultiSigOwner[setOwners[i]] = true;
        multiSigOwners = setOwners;
        requiredSignatures = setRequiredSignatures;
    }

    function() payable { Deposit(msg.sender, msg.value); }

}