// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ERC1155URIStorageUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155URIStorageUpgradeable.sol";
import {ERC1155BurnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import {ERC1155PausableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title FractionalRWA
 * @notice This upgradeable ERC1155 contract represents fractional ownership of real-world assets.
 *         Key features:
 *           - Role-based minting (admin/minter) and burning (admin/burner) restrictions
 *           - Asset status management (certified, in escrow, disputed, fraudulent)
 *           - Asset metadata management (URI)
 *           - Tracking of max and total shares minted for each asset
 *           - Optional KYC verification for asset transfers
 *           - Transparent Upgradeable Proxy compatible
 */
contract FractionalRWA is
    Initializable,
    ERC1155URIStorageUpgradeable,
    ERC1155BurnableUpgradeable,
    ERC1155PausableUpgradeable,
    AccessControlUpgradeable
{
    using Strings for uint256;

    /* ========== Roles ========== */
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant URI_SETTER_ROLE = keccak256("URI_SETTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /* ========== Asset Status Enum ========== */
    enum AssetStatus {
        Pending, // newly minted, unverified. Initial state.
        Certified, // verified by certifiers
        InEscrow, // currently in an escrow transaction. Non-transferrable
        Disputed, // a dispute has been filed. Non-transferrable
        Fraudulent // determined to be fraudulent. Non-transferrable and cannot be certified again.

    }

    /* ========== State Variables ========== */
    struct Asset {
        AssetStatus status;
    }

    // For each asset (tokenId), track its status in the lifecycle
    mapping(uint256 => Asset) public assets;

    // mapping for valid status transitions
    mapping(AssetStatus => AssetStatus[]) private _validTransitions;

    // (Optional) KYC tracking
    mapping(address => bool) private _kycVerified;

    // Keeps track of the current token ID for newly minted assets
    uint256 private _currentTokenId;

    // For each tokenId (asset), store the maximum shares that can ever be minted
    mapping(uint256 => uint256) private _maxShares;

    // For each tokenId, store total shares currently minted (sum of all balances)
    mapping(uint256 => uint256) private _totalShares;

    /* ========== Events ========== */
    event AssetMinted(uint256 indexed tokenId, address indexed owner, uint256 indexed amountMinted, string metadataURI);
    event AssetStatusUpdated(uint256 indexed tokenId, AssetStatus newStatus);
    event AssetTransferred(uint256 indexed tokenId, address indexed from, address indexed to, uint256 amount);
    event AssetDisputed(uint256 indexed tokenId, address indexed disputer);
    event AssetDisputeResolved(uint256 indexed tokenId, AssetStatus newStatus);
    event AssetCertified(uint256 indexed tokenId, address indexed certifier);
    event AssetInEscrow(uint256 indexed tokenId, address indexed escrowAgent);
    event AssetEscrowResolved(uint256 indexed tokenId, AssetStatus newStatus);
    event AssetFraudulent(uint256 indexed tokenId, address indexed reporter);
    event AssetBurned(uint256 indexed tokenId, address indexed burner);

    // Metadata events
    event AssetMetadataURIUpdated(uint256 indexed tokenId, string newURI);
    event BaseURIUpdated(string newBaseURI);

    // (Optional) KYC events
    event KYCVerified(address indexed account);
    event KYCRevoked(address indexed account);

    /* ========== Errors ========== */
    error InvalidMetadataURI(string metadataURI);
    error MaxSharesZero(uint256 tokenId);
    error InitialAmountExceedsMaxShares(uint256 tokenId, uint256 amount, uint256 maxShares);
    error MaxSharesExceeded(uint256 tokenId, uint256 totalShares, uint256 maxShares);
    error AssetNotFound(uint256 tokenId);
    error InvalidStatus(string status);
    error InvalidStatusTransition(AssetStatus oldStatus, AssetStatus newStatus);
    error FraudulentAsset();
    error TransferNotAllowed(string message, AssetStatus status);
    error NotKYCVerified(address account);
    error BurnerRoleRequired(string message);

    /* ========== Modifiers ========== */

    // Optional KYC-based restriction
    // Uncomment to enforce transfers only between KYCed addresses
    // modifier onlyKYCVerified(address _account) {
    //     if (!_kycVerified[_account]) {
    //         revert NotKYCVerified(_account);
    //     }
    //     _;
    // }

    /* ========== Initialization ========== */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers(); // Prevent usage of this constructor
    }

    /**
     * @dev Constructor replacement for upgradeable contracts.
     *      Must be called once via the proxy after deployment.
     * @param baseURI The base URI for token metadata (e.g., "ipfs://..." or "ar://...").
     * @param admin The address that will receive ADMIN_ROLE.
     */
    function initialize(string memory baseURI, address admin) public initializer {
        __ERC1155_init(baseURI);
        __AccessControl_init();
        __ERC1155URIStorage_init();
        __ERC1155Burnable_init();
        __ERC1155Pausable_init();

        _setBaseURI(baseURI);

        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
        _grantRole(URI_SETTER_ROLE, admin);
        _grantRole(BURNER_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        // Optionally, you might also give ADMIN_ROLE to msg.sender
        // if you're deploying via a script/tool:
        _grantRole(ADMIN_ROLE, _msgSender());

        // Make ADMIN_ROLE the admin of each role
        _setRoleAdmin(MINTER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(URI_SETTER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(BURNER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(PAUSER_ROLE, ADMIN_ROLE);

        // Initialize the token index
        _currentTokenId = 1;

        // Initialize valid status transitions from old status -> new status
        _validTransitions[AssetStatus.Pending] = [AssetStatus.Certified, AssetStatus.Fraudulent];
        _validTransitions[AssetStatus.Certified] = [AssetStatus.InEscrow, AssetStatus.Disputed];
        _validTransitions[AssetStatus.InEscrow] = [AssetStatus.Certified, AssetStatus.Disputed];
        _validTransitions[AssetStatus.Disputed] = [
            AssetStatus.Fraudulent,
            AssetStatus.Certified, // Dispute resolved, transaction complete
            AssetStatus.InEscrow // Dispute resolved, transaction still pending
        ];
        _validTransitions[AssetStatus.Fraudulent] = new AssetStatus[](0); // No transitions allowed
    }

    /* ========== Core Functions ========== */

    /**
     * @notice Mint a new asset (token) with a maximum share cap.
     * @param to Recipient of the initial minted shares (often the seller).
     * @param amount Number of fractional shares to mint initially.
     * @param metadataURI URI for asset metadata (e.g., location, images).
     * @param maxSharesCap The max number of shares allowed for this asset (cannot be exceeded later).
     *
     * Emits a {AssetMinted} event.
     */
    function mintAsset(address to, uint256 amount, string calldata metadataURI, uint256 maxSharesCap)
        external
        onlyRole(MINTER_ROLE)
        whenNotPaused
    {
        if (bytes(metadataURI).length == 0) {
            revert InvalidMetadataURI(metadataURI);
        }
        if (maxSharesCap == 0) {
            revert MaxSharesZero(_currentTokenId);
        }
        if (amount > maxSharesCap) {
            revert InitialAmountExceedsMaxShares(_currentTokenId, amount, maxSharesCap);
        }

        uint256 newTokenId = _currentTokenId;
        _currentTokenId++;

        // Initialize share tracking
        _maxShares[newTokenId] = maxSharesCap;
        _totalShares[newTokenId] = amount;

        // Set initial asset status (e.g. Pending)
        assets[newTokenId] = Asset(AssetStatus.Pending);

        _setURI(newTokenId, metadataURI);

        // Mint fractional shares to 'to'
        _mint(to, newTokenId, amount, "");

        emit AssetMinted(newTokenId, msg.sender, amount, metadataURI);
    }

    /**
     * @notice Mint additional shares for an existing asset, if not exceeding max shares.
     * @param tokenId The asset's token ID.
     * @param to Recipient of newly minted shares.
     * @param amount Number of shares to mint.
     */
    function mintAdditionalShares(uint256 tokenId, address to, uint256 amount)
        external
        onlyRole(MINTER_ROLE)
        whenNotPaused
    {
        if (_maxShares[tokenId] == 0) {
            revert AssetNotFound(tokenId);
        }
        if (_totalShares[tokenId] + amount > _maxShares[tokenId]) {
            revert MaxSharesExceeded(tokenId, _totalShares[tokenId], _maxShares[tokenId]);
        }
        if (assets[tokenId].status == AssetStatus.Fraudulent) {
            revert FraudulentAsset();
        }

        _totalShares[tokenId] += amount;
        _mint(to, tokenId, amount, "");

        emit AssetMinted(tokenId, msg.sender, amount, uri(tokenId));
    }

    /**
     * @notice Burn shares of an asset.
     * @param account The owner of the shares to burn.
     * @param id The asset's token ID.
     * @param value Number of shares to burn.
     */
    function burn(address account, uint256 id, uint256 value) public override whenNotPaused {
        bool isAuthorized =
            hasRole(BURNER_ROLE, _msgSender()) || account == _msgSender() || isApprovedForAll(account, _msgSender());

        if (!isAuthorized) {
            revert BurnerRoleRequired("Caller must have BURNER_ROLE or be owner/approved for all");
        }
        if (_maxShares[id] == 0) {
            revert AssetNotFound(id);
        }
        if (assets[id].status == AssetStatus.Fraudulent) {
            revert FraudulentAsset();
        }

        _totalShares[id] -= value;
        super.burn(account, id, value);

        emit AssetBurned(id, account);
    }

    /**
     * @notice Burn shares of multiple assets.
     * @param account The owner of the shares to burn.
     * @param ids The asset's token IDs.
     * @param values Number of shares to burn for each asset.
     */
    function burnBatch(address account, uint256[] memory ids, uint256[] memory values) public override whenNotPaused {
        bool isAuthorized =
            hasRole(BURNER_ROLE, _msgSender()) || account == _msgSender() || isApprovedForAll(account, _msgSender());

        if (!isAuthorized) {
            revert BurnerRoleRequired("Caller must have BURNER_ROLE or be owner/approved for all");
        }

        for (uint256 i = 0; i < ids.length; i++) {
            if (_maxShares[ids[i]] == 0) {
                revert AssetNotFound(ids[i]);
            }
            if (assets[ids[i]].status == AssetStatus.Fraudulent) {
                revert FraudulentAsset();
            }

            _totalShares[ids[i]] -= values[i];
        }

        super.burnBatch(account, ids, values);

        for (uint256 i = 0; i < ids.length; i++) {
            emit AssetBurned(ids[i], account);
        }
    }

    /**
     * @notice Change the base URI for metadata. Only admin can do this.
     * @param newBaseURI New base URI.
     */
    function setBaseURI(string memory newBaseURI) external onlyRole(URI_SETTER_ROLE) whenNotPaused {
        _setBaseURI(newBaseURI);

        emit BaseURIUpdated(newBaseURI);
    }

    function updateMetadataURI(uint256 tokenId, string calldata newURI)
        external
        onlyRole(URI_SETTER_ROLE)
        whenNotPaused
    {
        if (_maxShares[tokenId] == 0) {
            revert AssetNotFound(tokenId);
        }

        _setURI(tokenId, newURI);

        emit AssetMetadataURIUpdated(tokenId, newURI);
    }

    /* ========== Asset Status Management ========== */

    /**
     * @dev Updates the status of an NFT.
     * @param tokenId Token ID of the asset.
     * @param newStatus New status to assign.
     *
     * Emits an {AssetStatusUpdated} event.
     */
    function updateAssetStatus(uint256 tokenId, AssetStatus newStatus) external onlyRole(ADMIN_ROLE) whenNotPaused {
        if (_maxShares[tokenId] == 0) {
            revert AssetNotFound(tokenId);
        }
        if (assets[tokenId].status == AssetStatus.Fraudulent) {
            revert FraudulentAsset();
        }

        // Check if the status transition is valid
        bool isValidTransition = false;
        AssetStatus[] memory validTransitions = _validTransitions[assets[tokenId].status];
        for (uint256 i = 0; i < validTransitions.length; i++) {
            if (validTransitions[i] == newStatus) {
                isValidTransition = true;
                break;
            }
        }

        if (!isValidTransition) {
            revert InvalidStatusTransition(assets[tokenId].status, newStatus);
        }

        assets[tokenId].status = newStatus;

        emit AssetStatusUpdated(tokenId, newStatus);
    }

    /**
     * @notice Get the current status of an asset token.
     */
    function getAssetStatus(uint256 tokenId) external view returns (AssetStatus) {
        return assets[tokenId].status;
    }

    /**
     * @dev Retrieves the metadata URI for a specific token.
     * @param tokenId Token ID of the asset.
     * @return Metadata URI.
     */
    function getMetadataURI(uint256 tokenId) external view returns (string memory) {
        return uri(tokenId);
    }

    /* ========== KYC Functions (Optional) ========== */

    /**
     * @notice Mark a user's KYC as verified.
     */
    function verifyKYC(address account) external onlyRole(ADMIN_ROLE) whenNotPaused {
        _kycVerified[account] = true;
        emit KYCVerified(account);
    }

    /**
     * @notice Revoke KYC status of a user.
     */
    function revokeKYC(address account) external onlyRole(ADMIN_ROLE) whenNotPaused {
        _kycVerified[account] = false;
        emit KYCRevoked(account);
    }

    /**
     * @notice Check if a user is KYC verified.
     */
    function isKYCVerified(address account) external view returns (bool) {
        return _kycVerified[account];
    }

    /* ========== Transfer Overrides ========== */

    /**
     * @dev Overrides safeTransferFrom to enforce restrictions based on asset status and eventually KYC checks.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data // onlyKYCVerified(from)
    )
        public
        virtual
        override
        whenNotPaused // onlyKYCVerified(to)
    {
        if (assets[id].status == AssetStatus.Fraudulent) {
            revert FraudulentAsset();
        }
        if (assets[id].status != AssetStatus.Certified) {
            revert TransferNotAllowed("Asset must be Certified for transfer", assets[id].status);
        }

        super.safeTransferFrom(from, to, id, amount, data);

        emit AssetTransferred(id, from, to, amount);
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data // onlyKYCVerified(from)
    )
        public
        virtual
        override
        // onlyKYCVerified(to)
        whenNotPaused
    {
        // loop over all ids to check status
        for (uint256 i = 0; i < ids.length; i++) {
            if (assets[ids[i]].status == AssetStatus.Fraudulent) {
                revert FraudulentAsset();
            }
            if (assets[ids[i]].status != AssetStatus.Certified) {
                revert TransferNotAllowed("Asset must be Certified for transfer", assets[ids[i]].status);
            }
        }

        super.safeBatchTransferFrom(from, to, ids, amounts, data);

        for (uint256 i = 0; i < ids.length; i++) {
            emit AssetTransferred(ids[i], from, to, amounts[i]);
        }
    }

    /* ========== Pausable Functions ========== */

    /**
     * @notice Pause all transfers of assets.
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause all transfers of assets.
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /* ========== View Functions ========== */

    /**
     * @notice Get the total shares currently minted for a given asset tokenId.
     */
    function totalShares(uint256 tokenId) external view returns (uint256) {
        return _totalShares[tokenId];
    }

    /**
     * @notice Get the max shares cap for a given asset tokenId.
     */
    function maxShares(uint256 tokenId) external view returns (uint256) {
        return _maxShares[tokenId];
    }

    /**
     * @notice Returns the current token ID for minting new assets.
     */
    function getCurrentTokenId() external view returns (uint256) {
        return _currentTokenId;
    }

    /* ========== Required Overrides ========== */

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlUpgradeable, ERC1155Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function uri(uint256 tokenId)
        public
        view
        virtual
        override(ERC1155Upgradeable, ERC1155URIStorageUpgradeable)
        returns (string memory)
    {
        return super.uri(tokenId);
    }

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155Upgradeable, ERC1155PausableUpgradeable)
    {
        super._update(from, to, ids, values);
    }

    /* ========== Upgradeable Gap ========== */
    // Space reserved to add new state variables without shifting storage
    // in future upgrades (recommended by OZ to avoid storage collisions).
    uint256[50] private __gap;
}
