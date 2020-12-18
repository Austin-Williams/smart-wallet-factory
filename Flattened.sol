pragma solidity 0.7.5;
pragma experimental ABIEncoderV2;

// SPDX-License-Identifier: MIT

/**
Copyright (c) 2020 Austin Williams
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
**/

interface IWalletFactory {
    function updateOwnershipRecord(address _oldOwner) external;
}



interface IWallet {
    function owner() external view returns (address);
}



interface ICHI {
    function freeFromUpTo(address _addr, uint256 _amount) external returns (uint256);
}



contract FactoryNotifier {
    IWalletFactory immutable private _factory;
    
    constructor() {
        _factory = IWalletFactory(msg.sender);
    }
    
    function factory() public view returns (IWalletFactory) { return _factory; }
    
    function _notifyFactory(address _oldOwner) internal {
        factory().updateOwnershipRecord(_oldOwner);
    }
}



contract Ownable is FactoryNotifier {
    address private _owner;
    address private _pendingOwner;
    
    constructor(address _initialOwner) {
        _owner = _initialOwner;
    }
    
    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable::onlyOwner: Not owner.");
        _;
    }
    
    modifier onlyPendingOwner() {
        require(msg.sender == _pendingOwner, "Ownable::onlyPendingOwner: Not pending owner.");
        _;
    }
    
    // Since the Wallet contract can call functions ONLY via its `execute` and `executeMany` functions, and since both
    //  of those functions have the `onlyOwner` modifier, this `onlyAuthorizedCaller` modifier basically means "only the owner
    //  can call this function, and they can do so EITHER directly from the _owner address OR via the `execute` or `executeMany`
    //  functions on the Wallet contract".
    // The purpose of this is to allow functions with the `onlyAuthorizedCaller` modifier to be called via the `executeMany` function,
    //  so that the owner can "offer ownership" and also make other calls in a single transaction.
    modifier onlyAuthorizedCaller() {
        require(msg.sender == _owner || msg.sender == address(this), "Ownable::onlyAuthorizedCaller: Not authorized caller.");
        _;
    }
    
    event OwnershipOffered(address indexed owner, address indexed pendingOwner);
    event OwnershipTaken(address indexed oldOwner, address indexed newOnwer);
    
    // The owner can call this function directly from their _owner account, OR via the `execute` or `executeMany` functions
    //  on the Wallet contract
    function offerOwnership(address _newPendingOwner) external onlyAuthorizedCaller {
        require(_newPendingOwner != _owner, "Ownable::offerOwnership: Owner cannot transfer ownership to self."); // prevents UI confusion
        require(_newPendingOwner != address(this), "Ownable::offerOwnership: Wallet cannot own itself."); // removes a footgun (would brick the wallet)
        _pendingOwner = _newPendingOwner;
        emit OwnershipOffered(_owner, _newPendingOwner);
    }
    
    function takeOwnership() external onlyPendingOwner {
        // transfer ownership
        address oldOwner = _owner;
        address newOwner = _pendingOwner;
        _owner = newOwner;
        
        // remove _pendingOwner
        _pendingOwner = address(0);
        
        // notify the factory of the ownership change
        _notifyFactory(oldOwner);
        emit OwnershipTaken(oldOwner, newOwner);
    }
    
    function owner() public view returns (address) { return _owner; }
    function pendingOwner() public view returns (address) { return _pendingOwner; }
}



contract CHIEnabled {
    ICHI  constant private chi = ICHI(0x0000000000004946c0e9F43F4Dee607b0eF1fA1c);
    
    modifier useCHI {
        uint256 gasStart = gasleft();
        _;
        uint256 gasSpent = 21000 + gasStart - gasleft() + (16 * msg.data.length);
        chi.freeFromUpTo(msg.sender, (gasSpent + 14154) / 41947);
    }
}



contract Wallet is Ownable, CHIEnabled {
    
    fallback () external payable {}
    receive() external payable {}
    
    constructor(address _initialOwner) Ownable(_initialOwner) { }
    
    event ExecuteTransaction(address target, uint256 value, string signature, bytes data, bytes returnData);
    
    function _execute(address _target, uint256 _value, string memory _signature, bytes memory _data) private {
        bytes memory callData;

        if (bytes(_signature).length == 0) {
            callData = _data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(_signature))), _data);
        }

        // solium-disable-next-line
        (bool success, bytes memory returnData) = _target.call{value: _value}(callData);
        require(success, "Wallet::executeTransaction: Transaction execution reverted.");

        emit ExecuteTransaction(_target, _value, _signature, _data, returnData);
    }
    
    function _executeMany(address[] memory _targets, uint256[] memory _values, string[] memory _signatures, bytes[] memory _data) private {
        uint256 numInputs = _targets.length;
        require(
            _values.length == numInputs && _signatures.length == numInputs && _data.length == numInputs,
            "Wallet::executeMany: Invalid input lengths."
        );

        for (uint256 i = 0; i < numInputs; i++) {
            _execute(_targets[i], _values[i], _signatures[i], _data[i]);
        }
    }
    
    function execute(address _target, uint256 _value, string memory _signature, bytes memory _data) external payable onlyOwner {
        _execute(_target, _value, _signature, _data);
    }
    
    function executeWithCHI(address _target, uint256 _value, string memory _signature, bytes memory _data) external payable useCHI onlyOwner {
        _execute(_target, _value, _signature, _data);
    }
    
    function executeMany(address[] memory _targets, uint256[] memory _values, string[] memory _signatures, bytes[] memory _data) external payable onlyOwner {
        _executeMany(_targets, _values, _signatures, _data);
    }
    
    function executeManyWithCHI(address[] memory _targets, uint256[] memory _values, string[] memory _signatures, bytes[] memory _data) external payable useCHI onlyOwner {
        _executeMany(_targets, _values, _signatures, _data);
    }
}



contract WalletFactory is CHIEnabled {
    
    using EnumerableSet for EnumerableSet.AddressSet;
    
    mapping (address => bool) private _factoryCreatedWallet;
    mapping (address => EnumerableSet.AddressSet) private _ownerToWallets;
    
    event NewWalletCreated(address indexed owner, address walletAddress);
    event OwnershipTransferred(address indexed wallet, address indexed oldOwner, address indexed newOwner);
    
    // create new wallet
    function _createNewWallet() private returns (address) {
        address newWalletAddress = address(new Wallet(msg.sender));
        _factoryCreatedWallet[newWalletAddress] = true;
        require(_ownerToWallets[msg.sender].add(newWalletAddress), "Factory::createNewWallet: Failed to add record.");
        emit NewWalletCreated(msg.sender, newWalletAddress);
        return newWalletAddress;
    }
    
    // create new wallet
    function createNewWallet() external returns (address) {
        return _createNewWallet();
    }
    
    // create new wallet
    function createNewWalletWithCHI() external useCHI returns (address) {
        return _createNewWallet();
    }
    
    // update ownership record upon notification
    function updateOwnershipRecord(address _oldOwner) external {
        require(isFactoryCreatedWallet(msg.sender), "Wallet::updateOwnershipRecord: Not factory created wallet.");
        require(_ownerToWallets[_oldOwner].contains(msg.sender), "Wallet::updateOwnershipRecord: The address did not own this wallet.");
        address newOwner = IWallet(msg.sender).owner();
        require(_ownerToWallets[_oldOwner].remove(msg.sender), "Wallet::updateOwnershipRecord: Error removing wallet record.");
        require(_ownerToWallets[newOwner].add(msg.sender), "Wallet::updateOwnershipRecord: Error adding wallet record.");
        emit OwnershipTransferred(msg.sender, _oldOwner, newOwner);
    }
    
    /** ==============
     *  View Functions 
     * =============== **/
    
    // check whether a given wallet was created by this factory
    function isFactoryCreatedWallet(address _walletAddress) public view returns (bool) {
        return _factoryCreatedWallet[_walletAddress];
    }
    
    // check whether a given user is registered as owning a given wallet
    function userOwnsWallet(address _user, address _wallet) external view returns (bool) {
        return _ownerToWallets[_user].contains(_wallet);
    }
    
    // returns the number of wallets registered to a given user
    function ownerWalletCount(address _owner) external view returns (uint256) {
        return _ownerToWallets[_owner].length();
    }
    
    function ownerWalletAt(address _owner, uint256 _index) external view returns (address) {
        return _ownerToWallets[_owner].at(_index);
    }
}



/**
 * @dev Library for managing
 * https://en.wikipedia.org/wiki/Set_(abstract_data_type)[sets] of primitive
 * types.
 *
 * Sets have the following properties:
 *
 * - Elements are added, removed, and checked for existence in constant time
 * (O(1)).
 * - Elements are enumerated in O(n). No guarantees are made on the ordering.
 *
 * ```
 * contract Example {
 *     // Add the library methods
 *     using EnumerableSet for EnumerableSet.AddressSet;
 *
 *     // Declare a set state variable
 *     EnumerableSet.AddressSet private mySet;
 * }
 * ```
 *
 * As of v3.3.0, sets of type `bytes32` (`Bytes32Set`), `address` (`AddressSet`)
 * and `uint256` (`UintSet`) are supported.
 */
library EnumerableSet {
    // To implement this library for multiple types with as little code
    // repetition as possible, we write it in terms of a generic Set type with
    // bytes32 values.
    // The Set implementation uses private functions, and user-facing
    // implementations (such as AddressSet) are just wrappers around the
    // underlying Set.
    // This means that we can only create new EnumerableSets for types that fit
    // in bytes32.

    struct Set {
        // Storage of set values
        bytes32[] _values;

        // Position of the value in the `values` array, plus 1 because index 0
        // means a value is not in the set.
        mapping (bytes32 => uint256) _indexes;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function _add(Set storage set, bytes32 value) private returns (bool) {
        if (!_contains(set, value)) {
            set._values.push(value);
            // The value is stored at length-1, but we add 1 to all indexes
            // and use 0 as a sentinel value
            set._indexes[value] = set._values.length;
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function _remove(Set storage set, bytes32 value) private returns (bool) {
        // We read and store the value's index to prevent multiple reads from the same storage slot
        uint256 valueIndex = set._indexes[value];

        if (valueIndex != 0) { // Equivalent to contains(set, value)
            // To delete an element from the _values array in O(1), we swap the element to delete with the last one in
            // the array, and then remove the last element (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 toDeleteIndex = valueIndex - 1;
            uint256 lastIndex = set._values.length - 1;

            // When the value to delete is the last one, the swap operation is unnecessary. However, since this occurs
            // so rarely, we still do the swap anyway to avoid the gas cost of adding an 'if' statement.

            bytes32 lastvalue = set._values[lastIndex];

            // Move the last value to the index where the value to delete is
            set._values[toDeleteIndex] = lastvalue;
            // Update the index for the moved value
            set._indexes[lastvalue] = toDeleteIndex + 1; // All indexes are 1-based

            // Delete the slot where the moved value was stored
            set._values.pop();

            // Delete the index for the deleted slot
            delete set._indexes[value];

            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function _contains(Set storage set, bytes32 value) private view returns (bool) {
        return set._indexes[value] != 0;
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function _length(Set storage set) private view returns (uint256) {
        return set._values.length;
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function _at(Set storage set, uint256 index) private view returns (bytes32) {
        require(set._values.length > index, "EnumerableSet: index out of bounds");
        return set._values[index];
    }

    // Bytes32Set

    struct Bytes32Set {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _add(set._inner, value);
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _remove(set._inner, value);
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(Bytes32Set storage set, bytes32 value) internal view returns (bool) {
        return _contains(set._inner, value);
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(Bytes32Set storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(Bytes32Set storage set, uint256 index) internal view returns (bytes32) {
        return _at(set._inner, index);
    }

    // AddressSet

    struct AddressSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(AddressSet storage set, address value) internal returns (bool) {
        return _add(set._inner, bytes32(uint256(value)));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(AddressSet storage set, address value) internal returns (bool) {
        return _remove(set._inner, bytes32(uint256(value)));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(AddressSet storage set, address value) internal view returns (bool) {
        return _contains(set._inner, bytes32(uint256(value)));
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(AddressSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(AddressSet storage set, uint256 index) internal view returns (address) {
        return address(uint256(_at(set._inner, index)));
    }


    // UintSet

    struct UintSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(UintSet storage set, uint256 value) internal returns (bool) {
        return _add(set._inner, bytes32(value));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(UintSet storage set, uint256 value) internal returns (bool) {
        return _remove(set._inner, bytes32(value));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(UintSet storage set, uint256 value) internal view returns (bool) {
        return _contains(set._inner, bytes32(value));
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function length(UintSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(UintSet storage set, uint256 index) internal view returns (uint256) {
        return uint256(_at(set._inner, index));
    }
}



